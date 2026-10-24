// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка DatabaseService на хосте, без эмулятора (flutter test в форке
// не работает). Запуск: dart-aurora run tool/check_database.dart

// Скрипты tool/ осознанно печатают отчёт в консоль — отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

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

/// Проверка, что вставку отклонили по ожидаемой причине: текст ошибки
/// SQLite содержит [needle]. Иначе тест мог пройти «не за ту» ошибку
/// (например, NOT NULL вместо FOREIGN KEY).
void checkContains(String name, String? actualError, String needle) {
  if (actualError != null && actualError.contains(needle)) {
    _passed++;
    print('OK   $name');
  } else {
    _failed++;
    print(
      'FAIL $name — в ошибке ожидалось "$needle", '
      'получено: ${actualError ?? 'вставка не была отклонена'}',
    );
  }
}

/// Имена колонок таблицы — через PRAGMA table_info.
List<String> columnNames(DatabaseService db, String table) =>
    [for (final row in db.rawSelect('PRAGMA table_info($table);')) row['name'] as String];

/// Имена всех таблиц БД — через sqlite_master.
Set<String> tableNames(DatabaseService db) => {
      for (final row in db.rawSelect("SELECT name FROM sqlite_master WHERE type = 'table';"))
        row['name'] as String,
    };

/// Количество строк по запросу вида «SELECT COUNT(*) AS n ...».
int count(DatabaseService db, String sql) => db.rawSelect(sql).first['n'] as int;

/// DDL схемы v1 — ровно такой, какой был до М3.1 (без receipts и
/// search_text). Сознательный дубликат: тест миграции должен поднять
/// файл СТАРОГО вида, а не строить его текущим кодом. Этот дубликат
/// фиксирует историческую схему и больше не меняется.
void _createLegacyV1(Database db) {
  db.execute('''
    CREATE TABLE categories (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT NOT NULL UNIQUE,
      is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
    );
    CREATE TABLE trips (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      title      TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date   TEXT NOT NULL,
      CHECK (end_date >= start_date)
    );
    CREATE TABLE expenses (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      amount_kopecks INTEGER NOT NULL CHECK (amount_kopecks >= 0),
      date_iso       TEXT NOT NULL,
      category_id    INTEGER NOT NULL REFERENCES categories(id),
      payee          TEXT NOT NULL DEFAULT '',
      payment_method TEXT NOT NULL DEFAULT 'card'
                     CHECK (payment_method IN ('card', 'cash', 'qr_code', 'other')),
      comment        TEXT NOT NULL DEFAULT '',
      is_business    INTEGER NOT NULL DEFAULT 0 CHECK (is_business IN (0, 1)),
      trip_id        INTEGER REFERENCES trips(id) ON DELETE SET NULL
    );
    CREATE INDEX idx_expenses_date ON expenses (date_iso);
    CREATE INDEX idx_expenses_category ON expenses (category_id);
    CREATE INDEX idx_expenses_trip ON expenses (trip_id);
  ''');
  db.execute("INSERT INTO categories (name, is_default) VALUES ('Продукты', 1);");
  db.execute('''
    INSERT INTO expenses (amount_kopecks, date_iso, category_id, payee, comment, payment_method)
    VALUES (15000, '2026-10-20', 1, 'ООО «Ромашка»', 'Кофе с Ёлкой', 'card');
  ''');
  db.execute('PRAGMA user_version = 1;');
}

void main() {
  // ---------- In-memory: свежая БД ----------
  final db = DatabaseService.inMemory();
  check('версия схемы = 2', db.currentSchemaVersion, 2);

  final cats = db.getCategories();
  check('сид: 8 категорий из ТЗ + «Без категории»', cats.length, 9);
  check('все категории стандартные', cats.every((c) => c.isDefault), true);
  check(
    '«Без категории» есть в сиде',
    cats.map((c) => c.name).contains(DatabaseService.uncategorizedName),
    true,
  );

  // Порядок: 8 стандартных по алфавиту, служебная — последней.
  final namedSorted = [
    for (final name in DatabaseService.defaultCategoryNames)
      if (name != DatabaseService.uncategorizedName) name,
  ]..sort();
  final expectedNames = [...namedSorted, DatabaseService.uncategorizedName];
  check(
    'порядок: стандартные по алфавиту, «Без категории» последней',
    cats.map((c) => c.name).join('|'),
    expectedNames.join('|'),
  );

  // Схема v2: колонка поиска и таблица чеков
  check('expenses: есть search_text', columnNames(db, 'expenses').contains('search_text'), true);
  check('receipts: колонки', columnNames(db, 'receipts').join('|'), 'id|expense_id|file_path|created_at');

  // Поиск: нормализованная строка ищется LIKE-ом по кириллице
  db.rawExecute(
    'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payee, payment_method, comment, search_text) '
    'VALUES (?, ?, ?, ?, ?, ?, ?);',
    [
      19999,
      '2026-10-24',
      db.rawSelect('SELECT MIN(id) AS id FROM categories;').first['id'],
      'ООО «Ромашка»',
      'card',
      'Кофе с Ёлкой',
      Expense.buildSearchText('ООО «Ромашка»', 'Кофе с Ёлкой'),
    ],
  );
  check(
    'поиск: LIKE по нормализованной кириллице находит трату',
    count(db, "SELECT COUNT(*) AS n FROM expenses WHERE search_text LIKE '%елк%';"),
    1,
  );

  // FK: все прочие поля валидны (payment_method задан явно), единственная
  // возможная причина отклонения — несуществующий category_id.
  String? fkError;
  try {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payment_method) '
      'VALUES (?, ?, ?, ?);',
      [19999, '2026-10-24', 999, 'card'],
    );
  } on SqliteException catch (e) {
    fkError = e.message;
  }
  checkContains('FK: трата с несуществующей категорией отклонена', fkError, 'FOREIGN KEY');

  // Чеки: привязка к трате и каскадное удаление
  final expenseId = db.rawSelect('SELECT MAX(id) AS id FROM expenses;').first['id'] as int;
  db.rawExecute(
    'INSERT INTO receipts (expense_id, file_path, created_at) VALUES (?, ?, ?);',
    [expenseId, 'receipts/2026/10/check.jpg', '2026-10-25T10:00:00'],
  );
  check('чек привязан к трате', count(db, 'SELECT COUNT(*) AS n FROM receipts;'), 1);
  db.rawExecute('DELETE FROM expenses WHERE id = ?;', [expenseId]);
  check('каскад: удаление траты удаляет её чеки', count(db, 'SELECT COUNT(*) AS n FROM receipts;'), 0);

  // CHECK: неизвестный способ оплаты — сумма и категория заведомо валидны.
  String? methodError;
  try {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payment_method) '
      'VALUES (?, ?, (SELECT MIN(id) FROM categories), ?);',
      [100, '2026-10-24', 'бартер'],
    );
  } on SqliteException catch (e) {
    methodError = e.message;
  }
  checkContains('CHECK: неизвестный способ оплаты отклонён', methodError, 'CHECK');

  // CHECK: отрицательная сумма — payment_method задан явно, чтобы не поймать
  // NOT NULL вместо CHECK.
  String? amountError;
  try {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payment_method) '
      'VALUES (?, ?, (SELECT MIN(id) FROM categories), ?);',
      [-1, '2026-10-24', 'card'],
    );
  } on SqliteException catch (e) {
    amountError = e.message;
  }
  checkContains('CHECK: отрицательная сумма отклонена', amountError, 'CHECK');
  db.close();

  // ---------- Файл: миграция живой БД v1 -> v2 ----------
  final legacyPath =
      '${Directory.systemTemp.path}/expense_tracker_legacy_${DateTime.now().millisecondsSinceEpoch}.db';
  final legacy = sqlite3.open(legacyPath);
  _createLegacyV1(legacy);
  legacy.dispose();

  final migrated = DatabaseService.open(legacyPath);
  check('миграция v1->v2: версия схемы', migrated.currentSchemaVersion, 2);
  check('миграция: таблица receipts создана', tableNames(migrated).contains('receipts'), true);
  check('миграция: search_text добавлен', columnNames(migrated, 'expenses').contains('search_text'), true);
  check(
    'миграция: бэкфилл search_text (регистр, ё, пунктуация)',
    migrated.rawSelect('SELECT search_text FROM expenses;').first['search_text'],
    'ооо ромашка кофе с елкой',
  );
  check('миграция: старая трата не потеряна', count(migrated, 'SELECT COUNT(*) AS n FROM expenses;'), 1);
  check('миграция: сид добавил недостающие стандартные', count(migrated, 'SELECT COUNT(*) AS n FROM categories;'), 9);
  migrated.close();
  File(legacyPath).deleteSync();

  // ---------- Файл: свежая БД, повторное открытие ----------
  final tmpPath =
      '${Directory.systemTemp.path}/expense_tracker_check_${DateTime.now().millisecondsSinceEpoch}.db';
  var fileDb = DatabaseService.open(tmpPath);
  fileDb.close();
  fileDb = DatabaseService.open(tmpPath);
  check('повторное открытие: сид не дублируется', fileDb.getCategories().length, 9);
  check('повторное открытие: схема v2', fileDb.currentSchemaVersion, 2);
  fileDb.close();
  File(tmpPath).deleteSync();

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
