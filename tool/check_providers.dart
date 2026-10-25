// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка Riverpod-провайдеров на хосте, без эмулятора. Запуск:
// dart-aurora run tool/check_providers.dart
//
// Что проверяем:
//   * граф db -> DAO -> репозитории собирается и кэшируется;
//   * databaseProvider подменяется overrideWithValue — паттерн тестов М5+;
//   * списки-FutureProvider читают через репозитории и обновляются
//     по invalidate (контракт обновления для экранов);
//   * container.dispose() закрывает SQLite через ref.onDispose.

// Скрипты tool/ осознанно печатают отчёт в консоль - отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:expense_tracker/state/providers.dart';
import 'package:expense_tracker/state/expense_filter.dart';
import 'package:riverpod/riverpod.dart';

int _passed = 0;
int _failed = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    _passed++;
    print('OK   $name');
  } else {
    _failed++;
    print('FAIL $name - ожидалось: $expected, получено: $actual');
  }
}

Future<void> main() async {
  final db = DatabaseService.inMemory();
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );

  // Слушатели фиксируют граф: без них провайдеры без слушателей могут
  // утилизироваться контейнером, и проверки кэша станут плавающими.
  container.listen(databaseProvider, (_, _) {});
  container.listen(categoryDaoProvider, (_, _) {});
  container.listen(tripDaoProvider, (_, _) {});
  container.listen(expenseDaoProvider, (_, _) {});
  container.listen(categoryRepositoryProvider, (_, _) {});
  container.listen(tripRepositoryProvider, (_, _) {});
  container.listen(expenseRepositoryProvider, (_, _) {});
  container.listen(categoriesProvider, (_, _) {});
  container.listen(tripsProvider, (_, _) {});
  container.listen(expensesProvider, (_, _) {});

  // ---------- Сборка графа и кэш ----------
  check(
    'overrideWithValue: провайдер отдаёт подменённую БД',
    identical(container.read(databaseProvider), db),
    true,
  );
  check(
    'databaseProvider кэшируется (два чтения - один экземпляр)',
    identical(container.read(databaseProvider), container.read(databaseProvider)),
    true,
  );
  check(
    'categoryDaoProvider кэшируется',
    identical(container.read(categoryDaoProvider), container.read(categoryDaoProvider)),
    true,
  );
  check(
    'tripRepositoryProvider кэшируется',
    identical(container.read(tripRepositoryProvider), container.read(tripRepositoryProvider)),
    true,
  );

  // ---------- Категории: сид приезжает через провайдеры ----------
  final categories = await container.read(categoriesProvider.future);
  check('categoriesProvider: сид дал 9 категорий', categories.length, 9);
  // Порядок DAO: стандартные по алфавиту — первая "Здоровье",
  // "Без категории" идёт последней среди стандартных.
  check('categoriesProvider: первая - «Здоровье»', categories.first.name, 'Здоровье');

  // ---------- Командировки: insert -> invalidate ----------
  check(
    'tripsProvider: пусто в свежей БД',
    (await container.read(tripsProvider.future)).length,
    0,
  );

  final tripId = container.read(tripRepositoryProvider).insert(
    const Trip(title: 'Сапсан', startDateIso: '2026-10-22', endDateIso: '2026-10-25'),
  );
  check('insert через репозиторий: id > 0', tripId > 0, true);
  check(
    'FutureProvider кэширует: без invalidate список старый',
    (await container.read(tripsProvider.future)).length,
    0,
  );

  container.invalidate(tripsProvider);
  final trips = await container.read(tripsProvider.future);
  check('после invalidate поездка видна', trips.length, 1);
  check('и это та самая поездка «Сапсан»', trips.first.title, 'Сапсан');

  // ---------- Траты: JOIN категории через провайдеры ----------
  final products = categories.firstWhere((c) => c.name == 'Продукты');
  final expenseId = container.read(expenseRepositoryProvider).insert(
    Expense(
      amountKopecks: 19999,
      dateIso: '2026-10-23',
      categoryId: products.id!,
      payee: 'ООО "Ромашка"',
      comment: 'Кофе на переговоры',
      tripId: tripId,
    ),
  );
  check('insert траты через репозиторий: id > 0', expenseId > 0, true);

  container.invalidate(expensesProvider);
  final expenses = await container.read(expensesProvider.future);
  check('expensesProvider: трата видна', expenses.length, 1);
  check('expensesProvider: JOIN принёс категорию', expenses.first.category.name, 'Продукты');
  check('expensesProvider: привязка к поездке на месте', expenses.first.expense.tripId, tripId);

  // ---------- М6.1: фильтры трат ----------
  container.listen(expenseFilterProvider, (_, _) {});
  container.listen(filteredExpensesProvider, (_, _) {});

  check(
    'фильтр по умолчанию пуст',
    container.read(expenseFilterProvider),
    const ExpenseFilter(),
  );

  container.invalidate(filteredExpensesProvider);
  check(
    'filteredExpensesProvider без фильтров = полный список',
    (await container.read(filteredExpensesProvider.future)).length,
    expenses.length,
  );

  container.read(expenseFilterProvider.notifier).setCategory(products.id!);
  container.invalidate(filteredExpensesProvider);
  final filteredByCategory = await container.read(filteredExpensesProvider.future);
  check(
    'фильтр по категории: все строки нужной категории',
    filteredByCategory.every((item) => item.category.id == products.id),
    true,
  );
  check(
    'бейдж: активна 1 группа фильтров',
    container.read(expenseFilterProvider).activeCount,
    1,
  );

  container.read(expenseFilterProvider.notifier).setFrom('2030-01-01');
  container.invalidate(filteredExpensesProvider);
  check(
    'период в будущем даёт пустой список',
    (await container.read(filteredExpensesProvider.future)).isEmpty,
    true,
  );

  container.read(expenseFilterProvider.notifier).reset();
  container.invalidate(filteredExpensesProvider);
  check(
    'сброс вернул полный список',
    (await container.read(filteredExpensesProvider.future)).length,
    expenses.length,
  );

  // ---------- поиск по получателю и комментарию ----------
  container.read(expenseFilterProvider.notifier).setSearch('КОФЕ');
  container.invalidate(filteredExpensesProvider);
  check(
    'поиск без учёта регистра находит по комментарию',
    (await container.read(filteredExpensesProvider.future)).length,
    expenses.length,
  );

  container.read(expenseFilterProvider.notifier).setPayment(PaymentMethod.cash);
  container.invalidate(filteredExpensesProvider);
  check(
    'поиск + чужой способ оплаты = пусто (комбинация AND)',
    (await container.read(filteredExpensesProvider.future)).isEmpty,
    true,
  );

  container.read(expenseFilterProvider.notifier).reset();
  container.invalidate(filteredExpensesProvider);
  check(
    'после сброса снова полный список (М6.2)',
    (await container.read(filteredExpensesProvider.future)).length,
    expenses.length,
  );

  // ---------- Пользовательская категория ----------
  final newCategoryId = container.read(categoryRepositoryProvider).insert('Питание в дороге');
  check('insert категории через репозиторий: id > 0', newCategoryId > 0, true);
  container.invalidate(categoriesProvider);
  final categoriesAfter = await container.read(categoriesProvider.future);
  check(
    'новая категория видна после invalidate',
    categoriesAfter.any((c) => c.id == newCategoryId),
    true,
  );

  // ---------- Утилизация контейнера закрывает БД ----------
    // Основной сценарий окончен. При overrideWithValue владение БД у
  // проверки: провайдер значение не строил и не закрывает — закрываем сами.
  container.dispose();
  db.close();

  // ---------- Полный цикл databaseProvider: build -> dispose ----------
  // Живой провайдер (без overrideWithValue — тот обходит build!):
  // подменяем только путь через databasePathProvider, чтобы не создавать
  // файл в ~/.local/share. Проверяются настоящий build и ref.onDispose.
  final tempDir = Directory.systemTemp.createTempSync('et_check_db_');
  final liveContainer = ProviderContainer(
    overrides: [
      databasePathProvider.overrideWithValue('${tempDir.path}/expenses.db'),
    ],
  );
  liveContainer.listen(databaseProvider, (_, _) {});
  final liveDb = liveContainer.read(databaseProvider);

  check(
    'databaseProvider: файл БД создан по подменённому пути',
    File('${tempDir.path}/expenses.db').existsSync(),
    true,
  );

  liveContainer.dispose();
  var liveClosed = false;
  try {
    liveDb.rawSelect('SELECT 1;');
  } catch (_) {
    liveClosed = true;
  }
  check('container.dispose закрыл SQLite через ref.onDispose', liveClosed, true);

  tempDir.deleteSync(recursive: true);

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');

  exit(0); // Riverpod держит фоновые задачи планировщика,
           // без exit() VM в CLI не завершается
}
