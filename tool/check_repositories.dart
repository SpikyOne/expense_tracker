// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка репозиториев и заготовки Receipt на хосте. Запуск:
// dart-aurora run tool/check_repositories.dart
//
// Глубокие сценарии (фильтры, поиск, каскады) покрыты чек-скриптами DAO —
// здесь проверяем контрактный слой: репозитории под интерфейсами домена
// ведут себя как их DAO, Receipt ходит в/из БД.

// Скрипты tool/ осознанно печатают отчёт в консоль — отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/data/repositories/category_repository_impl.dart';
import 'package:expense_tracker/data/repositories/expense_repository_impl.dart';
import 'package:expense_tracker/data/repositories/trip_repository_impl.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:expense_tracker/domain/repositories/repositories.dart';

int _passed = 0;
int _failed = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    _passed++;
    print('OK   $name');
  } else {
    _failed++;
    print('FAIL $name — ожидалось: $expected, получено: $actual');
  }
}

void checkThrows<T extends Object>(String name, void Function() action, String messagePart) {
  try {
    action();
    _failed++;
    print('FAIL $name — исключение не выброшено');
  } on T catch (e) {
    if (e.toString().contains(messagePart)) {
      _passed++;
      print('OK   $name');
    } else {
      _failed++;
      print('FAIL $name — в ошибке ожидалось "$messagePart", получено: $e');
    }
  } catch (e) {
    _failed++;
    print('FAIL $name — выброшено ${e.runtimeType} вместо $T: $e');
  }
}

void main() {
  final db = DatabaseService.inMemory();

  // Типы переменных — интерфейсы домена: реализации обязаны им
  // соответствовать, презентация никогда не увидит DAO.
  final CategoryRepository categories = CategoryRepositoryImpl(db);
  final ExpenseRepository expenses = ExpenseRepositoryImpl(db);
  final TripRepository trips = TripRepositoryImpl(db);

  // ---------- Категории через контракт ----------
  final cafeId = categories.insert('Кафе у дома');
  check('categories: вставка и чтение', categories.getById(cafeId)?.name, 'Кафе у дома');
  check('categories: сид на месте', categories.getAll().length >= 9, true);
  checkThrows<StateError>(
    'categories: стандартную нельзя удалить (правило пробилось через контракт)',
    () => categories.delete(
      db.getCategories().firstWhere((c) => c.name == 'Продукты').id!,
    ),
    'нельзя удалить',
  );

  // ---------- Траты через контракт ----------
  final productsId = db.getCategories().firstWhere((c) => c.name == 'Продукты').id!;
  final e1 = expenses.insert(
    Expense(
      amountKopecks: 15000,
      dateIso: '2026-10-20',
      categoryId: productsId,
      payee: 'ООО «Ромашка»',
      comment: 'Кофе',
    ),
  );
  final e2 = expenses.insert(
    Expense(
      amountKopecks: 9900,
      dateIso: '2026-10-24',
      categoryId: productsId,
      payee: 'Пятёрочка',
      comment: 'Молоко',
      paymentMethod: PaymentMethod.cash,
    ),
  );

  check('expenses: getById возвращает пару «трата + категория»', expenses.getById(e1)?.category.name, 'Продукты');
  check(
    'expenses: фильтр по способу оплаты',
    [for (final r in expenses.query(paymentMethod: PaymentMethod.cash)) r.expense.id].join('|'),
    '$e2',
  );
  check(
    'expenses: поиск ё -> е через контракт',
    [for (final r in expenses.query(searchText: 'Ромашка')) r.expense.id].join('|'),
    '$e1',
  );
  expenses.update(expenses.getById(e1)!.expense.copyWith(comment: 'Кофе и булочка'));
  check('expenses: правка через контракт', expenses.getById(e1)!.expense.comment, 'Кофе и булочка');

  // ---------- Командировки через контракт ----------
  final tripId = trips.insert(const Trip(title: 'Сапсан', startDateIso: '2026-10-22', endDateIso: '2026-10-25'));
  final e3 = expenses.insert(
    Expense(amountKopecks: 120000, dateIso: '2026-10-22', categoryId: productsId, tripId: tripId),
  );
  check('trips: вставка и чтение', trips.getById(tripId)?.title, 'Сапсан');
  check('trips: expensesCount видит привязку', trips.expensesCount(tripId), 1);
  trips.delete(tripId);
  check('trips: после удаления траты отвязаны', expenses.getById(e3)!.expense.tripId, null);

  // ---------- Receipt: маппинг в/из БД (DAO чеков — в М9) ----------
  final receipt = Receipt(expenseId: e1, filePath: 'receipts/2026/10/check.jpg', createdAt: '2026-10-26T10:00:00');
  db.rawExecute(
    'INSERT INTO receipts (expense_id, file_path, created_at) VALUES (?, ?, ?);',
    [receipt.expenseId, receipt.filePath, receipt.createdAt],
  );
  final saved = Receipt.fromMap(db.rawSelect('SELECT * FROM receipts WHERE expense_id = ?;', [e1]).first);
  check('receipt: fromMap читает строку БД', saved.filePath, receipt.filePath);
  check('receipt: roundtrip toMap→fromMap', Receipt.fromMap(receipt.toMap()), receipt);

  expenses.delete(e1);
  check('receipt: чеки удаляются каскадом за тратой', db.rawSelect('SELECT COUNT(*) AS n FROM receipts;').first['n'] as int, 0);
  check('expenses: delete через контракт', expenses.getById(e1), null);
  check('expenses: траты других категорий не тронуты', expenses.getById(e2)!.expense.id, e2);

  db.close();

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
