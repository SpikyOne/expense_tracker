// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Сервис базы данных: единственная точка входа в SQLite.
//
// Ключевые решения (закреплены на этапе 2):
//   * чистый пакет sqlite3 (FFI) + системная libsqlite3.so.0 из состава
//     ОС Аврора — без Drift и без path_provider;
//   * путь к БД — по XDG-соглашению, чистым Dart;
//   * версия схемы в PRAGMA user_version; миграции — цепочкой
//     _migrateV N() от версии файла к актуальной;
//   * сид 8 стандартных категорий из ТЗ — при первой инициализации.

import 'dart:ffi';
import 'dart:io';

import 'package:expense_tracker/domain/models/models.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// Подменяет загрузку sqlite3 на системную библиотеку Авроры.
/// Идемпотентно: повторный вызов просто перерегистрирует загрузчик.
/// DatabaseService вызывает это сам в фабриках — вручную не нужно.
void configureSqliteForAurora() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so.0');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so');
    }
  });
}

/// Сервис БД: открытие, схема, миграции, сиды, низкоуровневые запросы.
///
/// Живёт в слое data; наружу отдаёт типы домена (Category, Expense).
class DatabaseService {
  /// Идентификатор приложения — часть пути к каталогу данных.
  static const appId = 'ru.grigorev.expense_tracker';

  /// Актуальная версия схемы. При изменении схемы добавляем метод
  /// миграции _migrateV2(), _migrateV3() и инкрементируем это число.
  static const int schemaVersion = 1;

  /// Стандартные категории из ТЗ (8 штук).
  static const List<String> defaultCategoryNames = [
    'Продукты',
    'Кафе',
    'Коммунальные платежи',
    'Транспорт',
    'Одежда',
    'Здоровье',
    'Развлечение',
    'Обучение',
  ];

  final Database _db;

  /// Путь к файлу БД; ':memory:' для in-memory-версии.
  final String path;

  DatabaseService._(this._db, this.path) {
    // Внешние ключи в SQLite выключены по умолчанию, и настройка
    // не сохраняется в файле — включаем на каждом соединении.
    _db.execute('PRAGMA foreign_keys = ON;');
    _migrateIfNeeded();
    _seedDefaultCategories();
  }

  /// Основная БД приложения. Каталог под файл создаётся рекурсивно.
  /// Сам настраивает загрузку sqlite3 — main() и скрипты об этом не думают.
  factory DatabaseService.open([String? path]) {
    configureSqliteForAurora();
    final dbPath = path ?? defaultDatabasePath();
    File(dbPath).parent.createSync(recursive: true);
    return DatabaseService._(sqlite3.open(dbPath), dbPath);
  }

  /// БД в памяти — для проверок в tool/ и будущих DAO-тестов.
  factory DatabaseService.inMemory() {
    configureSqliteForAurora();
    return DatabaseService._(sqlite3.openInMemory(), ':memory:');
  }

  /// Путь к БД по XDG-соглашению: $XDG_DATA_HOME, иначе ~/.local/share.
  static String defaultDatabasePath() {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final home = Platform.environment['HOME'] ?? '/';
    final dataHome = (xdg == null || xdg.isEmpty) ? '$home/.local/share' : xdg;
    return '$dataHome/$appId/expenses.db';
  }

  /// Версия схемы, записанная в файле БД.
  int get currentSchemaVersion => _db.select('PRAGMA user_version;').first.values.first as int;

  /// Все категории: стандартные первыми, внутри групп по алфавиту.
  List<Category> getCategories() {
    final rows = _db.select('SELECT * FROM categories ORDER BY is_default DESC, name;');
    return rows.map(Category.fromMap).toList();
  }

  void close() => _db.dispose();

  /// Прямой доступ к SQLite для проверок в tool/ и служебных нужд.
  /// Прикладной код использует только методы сервиса, не raw-запросы.
  void rawExecute(String sql, [List<Object?> parameters = const []]) => _db.execute(sql, parameters);

  // ---------- Схема и миграции ----------

  void _migrateIfNeeded() {
    final current = currentSchemaVersion;
    if (current > schemaVersion) {
      throw StateError(
        'Файл БД создан более новой версией приложения '
        '(схема $current > $schemaVersion).',
      );
    }
    if (current < 1) _migrateV1();
    // Будущие версии — цепочкой: if (current < 2) _migrateV2();
  }

  void _migrateV1() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL UNIQUE,
        is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
      );
    ''');

    // trips создаём сразу: expenses.trip_id ссылается на неё внешним
    // ключом, а модель Trip появится на этапе «Командировки».
    _db.execute('''
      CREATE TABLE IF NOT EXISTS trips (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date   TEXT NOT NULL,
        CHECK (end_date >= start_date)
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
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
    ''');

    // Индексы под главные запросы: список трат по датам и фильтры.
    _db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses (date_iso);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses (category_id);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_trip ON expenses (trip_id);');

    _db.execute('PRAGMA user_version = 1;');
  }

  void _seedDefaultCategories() {
    final n = _db.select('SELECT COUNT(*) AS n FROM categories;').first['n'] as int;
    if (n > 0) return;
    final stmt = _db.prepare('INSERT INTO categories (name, is_default) VALUES (?, ?);');
    try {
      for (final name in defaultCategoryNames) {
        stmt.execute([name, 1]);
      }
    } finally {
      stmt.dispose();
    }
  }
}
