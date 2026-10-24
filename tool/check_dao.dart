// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка CategoryDao на хосте, без эмулятора (flutter test в форке
// не работает). Запуск: dart-aurora run tool/check_dao.dart

// Скрипты tool/ осознанно печатают отчёт в консоль — отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/data/dao/category_dao.dart';
import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:sqlite3/sqlite3.dart';

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

/// Проверка, что [action] выбрасывает исключение ровно типа [T], причём
/// текст ошибки содержит [messagePart] — иначе можно пройти «не за ту»
/// ошибку (например, UNIQUE вместо ArgumentError).
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
  final dao = CategoryDao(db);

  const seededCount = 9; // 8 категорий из ТЗ + «Без категории»
  final uncategorizedId = db
      .rawSelect(
        'SELECT id FROM categories WHERE name = ?;',
        [DatabaseService.uncategorizedName],
      )
      .first['id'] as int;

  // ---------- Вставка ----------
  final cafeId = dao.insert('  Кафе у дома  ');
  check('insert: возвращает id больше нуля', cafeId > 0, true);
  final taxiId = dao.insert('Такси');
  check('insert: id увеличивается', taxiId > cafeId, true);
  final cafe = dao.getById(cafeId);
  check('insert: категория появилась в базе', cafe != null, true);
  check('insert: имя обрезано от пробелов', cafe?.name, 'Кафе у дома');
  check('insert: пользовательская, не стандартная', cafe?.isDefault, false);

  checkThrows<ArgumentError>(
    'insert: имя из одних пробелов отклонено',
    () => dao.insert('   '),
    'пустым',
  );
  checkThrows<SqliteException>(
    'insert: дубликат имени отклонён (UNIQUE)',
    () => dao.insert('Такси'),
    'UNIQUE',
  );
  checkThrows<SqliteException>(
    'insert: имя совпало со стандартной категорией (UNIQUE)',
    () => dao.insert('Продукты'),
    'UNIQUE',
  );
  check(
    'insert: отклонённые вставки не изменили список',
    dao.getAll().length,
    seededCount + 2,
  );

  // ---------- Чтение ----------
  // Ожидание вычисляем, а не хардкодим: compareTo в Dart по кодовым
  // единицам совпадает с BINARY-порядком SQLite для заглавной кириллицы.
  final stdSorted = [
    ...DatabaseService.defaultCategoryNames.where(
      (n) => n != DatabaseService.uncategorizedName,
    ),
  ]..sort();
  final expectedOrder = [...stdSorted, DatabaseService.uncategorizedName, 'Кафе у дома', 'Такси'];
  check(
    'getAll: стандартные по алфавиту, «Без категории» последней, затем пользовательские',
    dao.getAll().map((c) => c.name).join('|'),
    expectedOrder.join('|'),
  );

  final products = db.getCategories().firstWhere((c) => c.name == 'Продукты');
  final byId = dao.getById(products.id!);
  check('getById: стандартная категория найдена', byId?.name, 'Продукты');
  check('getById: стандартная — isDefault = 1', byId?.isDefault, true);
  check('getById: несуществующий id — null', dao.getById(-1), null);

  // ---------- Переименование ----------
  dao.rename(taxiId, '  Такси Макси  ');
  check('rename: имя изменилось и обрезано', dao.getById(taxiId)?.name, 'Такси Макси');

  checkThrows<ArgumentError>(
    'rename: пустое имя отклонено',
    () => dao.rename(taxiId, '   '),
    'пустым',
  );
  checkThrows<StateError>(
    'rename: стандартную категорию нельзя переименовать',
    () => dao.rename(products.id!, 'Супермаркет'),
    'нельзя переименовать',
  );
  check('rename: стандартная не изменилась', dao.getById(products.id!)?.name, 'Продукты');
  checkThrows<StateError>(
    'rename: несуществующий id',
    () => dao.rename(-1, 'Нигде'),
    'не найдена',
  );

  // ---------- Удаление ----------
  // Фикстуры-траты: search_text заполняет слой Dart — так же, как будет
  // делать ExpenseDao (М3.3); урок check_database из М3.1.
  void insertExpense(int categoryId, String payee, String comment) {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payee, comment, payment_method, search_text) '
      'VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        15000,
        '2026-10-25',
        categoryId,
        payee,
        comment,
        'card',
        Expense.buildSearchText(payee, comment),
      ],
    );
  }

  insertExpense(cafeId, 'Кофейня', 'Латте');
  insertExpense(cafeId, 'Кофейня', 'Чизкейк');
  insertExpense(products.id!, 'Пятёрочка', 'Молоко');

  checkThrows<StateError>(
    'delete: стандартную категорию нельзя удалить',
    () => dao.delete(products.id!),
    'нельзя удалить',
  );
  checkThrows<StateError>(
    'delete: «Без категории» — приёмник, тоже нельзя удалить',
    () => dao.delete(uncategorizedId),
    'нельзя удалить',
  );
  checkThrows<StateError>(
    'delete: несуществующий id',
    () => dao.delete(-1),
    'не найдена',
  );

  dao.delete(cafeId);
  check('delete: категория исчезла', dao.getById(cafeId), null);
  int countExpensesByCategory(int categoryId) => db
      .rawSelect('SELECT COUNT(*) AS n FROM expenses WHERE category_id = ?;', [categoryId])
      .first['n'] as int;
  check(
    'delete: обе траты переехали в «Без категории»',
    countExpensesByCategory(uncategorizedId),
    2,
  );
  check(
    'delete: траты других категорий не тронуты',
    countExpensesByCategory(products.id!),
    1,
  );
  check(
    'delete: траты не потеряны',
    db.rawSelect('SELECT COUNT(*) AS n FROM expenses;').first['n'] as int,
    3,
  );

  dao.delete(taxiId);
  check('delete: категория без трат удалена', dao.getById(taxiId), null);
  check('delete: список вернулся к сиду', dao.getAll().length, seededCount);
  check('delete: остались только стандартные', dao.getAll().every((c) => c.isDefault), true);

  db.close();

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
