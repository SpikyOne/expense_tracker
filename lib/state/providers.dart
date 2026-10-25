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
