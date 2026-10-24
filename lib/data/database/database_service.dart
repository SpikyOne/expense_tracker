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
//   * сид: 8 стандартных категорий из ТЗ + служебная «Без категории» -
//     идемпотентно, INSERT OR IGNORE по имени (доезжает в старые БД);

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
  static const int schemaVersion = 2;

  /// Служебная категория: в неё переносятся траты при удалении
  /// пользовательской. Защищена от удаления как стандартная,
  /// в интерфейсах показывается последней среди стандартных.
  static const String uncategorizedName = 'Без категории';

  /// Стандартные категории из ТЗ (8 штук) + служебная «Без категории».
  /// Порядок = порядок первого сида; «Без категории» — последней.
  static const List<String> defaultCategoryNames = [
    'Продукты',
    'Кафе',
    'Коммунальные платежи',
    'Транспорт',
    'Одежда',
    'Здоровье',
    'Развлечение',
    'Обучение',
    uncategorizedName,
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

  /// Все категории: стандартные первыми, «Без категории» — последней
  /// среди стандартных, затем пользовательские; внутри групп по алфавиту.
  List<Category> getCategories() {
    final rows = _db.select(
      'SELECT * FROM categories ORDER BY is_default DESC, name = ?, name;',
      [uncategorizedName],
    );
    return rows.map(Category.fromMap).toList();
  }

  void close() => _db.dispose();

  /// Прямой доступ к SQLite для проверок в tool/ и служебных нужд.
  /// Прикладной код использует только методы сервиса, не raw-запросы.
  void rawExecute(String sql, [List<Object?> parameters = const []]) => _db.execute(sql, parameters);

  /// Чтение сырых строк — для проверок в tool/ и служебных нужд.
  /// Прикладной код использует только методы сервиса и DAO, не raw-запросы.
  List<Map<String, Object?>> rawSelect(String sql, [List<Object?> parameters = const []]) {
    final result = _db.select(sql, parameters);
    return [
      for (final row in result) Map<String, Object?>.fromIterables(result.columnNames, row.values),
    ];
  }

  // ---------- Схема и миграции ----------

  // Правило миграций: уже «выпущенный» шаг цепочки никогда не
  // редактируется — изменения схемы только новым _migrateVN().
  // Поэтому _migrateV1() остаётся ровно таким, каким был: свежая БД
  // получает финальную схему цепочкой v1 -> v2, старая — одним шагом v2.
  void _migrateIfNeeded() {
    final current = currentSchemaVersion;
    if (current > schemaVersion) {
      throw StateError(
        'Файл БД создан более новой версией приложения '
        '(схема $current > $schemaVersion).',
      );
    }
    if (current < 1) _migrateV1();
    if (current < 2) _migrateV2();
    // Будущие версии — цепочкой: if (current < 3) _migrateV3();
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

  /// v1 -> v2 (М3.1): таблица чеков и поисковая колонка.
  void _migrateV2() {
    // Чеки: у траты может быть несколько фото (камера/галерея — ТЗ).
    // Файлы лежат в каталоге данных приложения, в БД храним путь
    // ОТНОСИТЕЛЬНО этого каталога: БД не привязывается к абсолютным путям.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS receipts (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
        file_path  TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_receipts_expense ON receipts (expense_id);');

    // Поиск по кириллице: lower() в SQLite без ICU берёт только ASCII,
    // поэтому храним готовую нормализованную строку «получатель +
    // комментарий» (контракт — Expense.buildSearchText). Заполняется
    // DAO при каждой вставке/правке траты.
    _db.execute("ALTER TABLE expenses ADD COLUMN search_text TEXT NOT NULL DEFAULT '';");

    // Бэкфилл: траты, созданные до v2 (девелоперская БД).
    final rows = _db.select("SELECT id, payee, comment FROM expenses WHERE search_text = '';");
    final update = _db.prepare('UPDATE expenses SET search_text = ? WHERE id = ?;');
    try {
      for (final row in rows) {
        update.execute([
          Expense.buildSearchText(row['payee'] as String? ?? '', row['comment'] as String? ?? ''),
          row['id'],
        ]);
      }
    } finally {
      update.dispose();
    }

    _db.execute('PRAGMA user_version = 2;');
  }

  /// Идемпотентный сид: каждую стандартную категорию добавляем по имени,
  /// только если её ещё нет (UNIQUE + INSERT OR IGNORE). Так новые
  /// стандартные категории появляются и в уже существующих БД —
  /// не только при первой инициализации.
  void _seedDefaultCategories() {
    final stmt = _db.prepare('INSERT OR IGNORE INTO categories (name, is_default) VALUES (?, 1);');
    try {
      for (final name in defaultCategoryNames) {
        stmt.execute([name]);
      }
    } finally {
      stmt.dispose();
    }
  }

}
