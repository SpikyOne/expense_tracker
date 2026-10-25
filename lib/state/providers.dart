// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Riverpod-провайдеры: граф "БД -> DAO -> репозитории -> списки".
//
// Цепочка (читать сверху вниз):
//
//   databaseProvider
//     -> categoryRepositoryProvider / tripRepositoryProvider / expenseRepositoryProvider
//     -> categoriesProvider / tripsProvider / expensesProvider
//
//   (отдельная утилитарная ветка для М6 и проверок:)
//     databaseProvider -> categoryDaoProvider / tripDaoProvider / expenseDaoProvider

import 'package:expense_tracker/data/dao/category_dao.dart';
import 'package:expense_tracker/data/dao/expense_dao.dart';
import 'package:expense_tracker/data/dao/trip_dao.dart';
import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/data/repositories/category_repository_impl.dart';
import 'package:expense_tracker/data/repositories/expense_repository_impl.dart';
import 'package:expense_tracker/data/repositories/trip_repository_impl.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:expense_tracker/domain/repositories/repositories.dart';
import 'package:riverpod/riverpod.dart';

import 'expense_filter.dart';

// ---------- База данных ----------

/// Путь к файлу БД; null — стандартный XDG-путь приложения.
///
/// Конфиг-провайдер: в приложении не переопределяется, в проверках и
/// тестах подменяется, чтобы БД жила во временной папке и не трогала
/// данные на машине разработчика.
final databasePathProvider = Provider<String?>((ref) => null);

/// Единственное соединение с БД приложения.
///
/// Ленивое: пока ни один провайдер не прочитан, SQLite не открывается
/// вообще — main() остаётся пустым без TODO. [DatabaseService.open] сам
/// создаёт каталог, накатывает миграции и делает сид категорий.
/// Закрытие привязано к жизни провайдера: контейнер утилизирован -
/// SQLite закрыт (ref.onDispose).
final databaseProvider = Provider<DatabaseService>((ref) {
  final path = ref.watch(databasePathProvider);
  final db = path == null ? DatabaseService.open() : DatabaseService.open(path);
  ref.onDispose(db.close);
  return db;
});

// ---------- DAO ----------

final categoryDaoProvider = Provider<CategoryDao>(
  (ref) => CategoryDao(ref.watch(databaseProvider)),
);

final tripDaoProvider = Provider<TripDao>(
  (ref) => TripDao(ref.watch(databaseProvider)),
);

final expenseDaoProvider = Provider<ExpenseDao>(
  (ref) => ExpenseDao(ref.watch(databaseProvider)),
);

// ---------- Репозитории ----------

/// Наружу отдаём интерфейсы домена: экраны не должны знать про impl.
final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepositoryImpl(ref.watch(databaseProvider)),
);

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepositoryImpl(ref.watch(databaseProvider)),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepositoryImpl(ref.watch(databaseProvider)),
);

// ---------- Фильтры трат (М6.1) ----------

/// Активный фильтр экрана трат. Не знает ни про UI, ни про SQL:
/// доменные параметры, пробрасываемые в ExpenseRepository.query.
///
/// Riverpod 3: вместо legacy StateProvider — NotifierProvider, мутации
/// инкапсулированы методами, UI не собирает copyWith сам.
final expenseFilterProvider = NotifierProvider<ExpenseFilterNotifier, ExpenseFilter>(
  ExpenseFilterNotifier.new,
);

/// Состояние и мутации фильтра трат.
class ExpenseFilterNotifier extends Notifier<ExpenseFilter> {
  @override
  ExpenseFilter build() => const ExpenseFilter();

  /// null снимает границу периода.
  void setFrom(String? dateIso) =>
      state = state.copyWith(fromDateIso: dateIso, clearFrom: dateIso == null);

  /// null снимает границу периода.
  void setTo(String? dateIso) =>
      state = state.copyWith(toDateIso: dateIso, clearTo: dateIso == null);

  /// null = «все категории».
  void setCategory(int? id) =>
      state = state.copyWith(categoryId: id, clearCategory: id == null);

  /// null = «все способы оплаты».
  void setPayment(PaymentMethod? method) =>
      state = state.copyWith(paymentMethod: method, clearPayment: method == null);

  /// М6.2: UI поиска появится позже — провайдер готов уже сейчас.
  void setSearch(String? text) => state = state.copyWith(
      searchText: text, clearSearch: text == null || text.trim().isEmpty);

  void reset() => state = const ExpenseFilter();
}

// ---------- Списки для экранов ----------

/// Категории в порядке DAO: стандартные, затем пользовательские.
final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).getAll(),
);

/// Командировки: позже начинающиеся раньше.
final tripsProvider = FutureProvider<List<Trip>>(
  (ref) => ref.watch(tripRepositoryProvider).query(),
);

/// Траты с категориями: новые раньше. Пока без параметров — фильтры и
/// поиск из М6 сделаем отдельным параметризованным провайдером поверх
/// того же ExpenseDao.query, этот останется «полным списком».
final expensesProvider = FutureProvider<List<ExpenseWithCategory>>(
  (ref) => ref.watch(expenseRepositoryProvider).query(),
);

/// Траты с учётом expenseFilterProvider: параметры пробрасываются в
/// ExpenseDao.query (все фильтры и поиск уже реализованы в DAO).
/// Полный список по-прежнему в expensesProvider — дашборду фильтры
/// не нужны (пригодится в М11).
final filteredExpensesProvider = FutureProvider<List<ExpenseWithCategory>>((ref) {
  final filter = ref.watch(expenseFilterProvider);
  return ref.watch(expenseRepositoryProvider).query(
    fromDateIso: filter.fromDateIso,
    toDateIso: filter.toDateIso,
    categoryId: filter.categoryId,
    paymentMethod: filter.paymentMethod,
    searchText: filter.searchText,
  );
});
