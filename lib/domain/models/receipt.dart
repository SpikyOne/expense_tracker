// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Модель чека - заготовка.
//
// Чек — фото траты (камера/галерея по ТЗ). В БД храним только путь
// ОТНОСИТЕЛЬНО каталога данных приложения: файлы лежат рядом с БД,
// и абсолютные пути не протухают при переносе.
//
// Хранение — таблица receipts (схема v2):
//
//   id         INTEGER PRIMARY KEY AUTOINCREMENT
//   expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE
//   file_path  TEXT NOT NULL
//   created_at TEXT NOT NULL

/// Чек: фото, подтверждающее трату.
class Receipt {
  /// Имена колонок таблицы receipts — единый источник правды.
  static const colId = 'id';
  static const colExpenseId = 'expense_id';
  static const colFilePath = 'file_path';
  static const colCreatedAt = 'created_at';

  /// id в БД; null — чек ещё не сохранён.
  final int? id;

  /// Ссылка на expenses.id, к которому прикреплён чек.
  final int expenseId;

  /// Путь к файлу относительно каталога данных ('receipts/2026/10/check.jpg').
  final String filePath;

  /// Момент создания записи, ISO-8601 ('2026-10-26T10:00:00').
  final String createdAt;

  const Receipt({
    this.id,
    required this.expenseId,
    required this.filePath,
    required this.createdAt,
  });

  /// Строка для INSERT. id при null не пишем — SQLite подставит AUTOINCREMENT.
  Map<String, Object?> toMap() => {
    if (id != null) colId: id,
    colExpenseId: expenseId,
    colFilePath: filePath,
    colCreatedAt: createdAt,
  };

  /// Строка из SELECT.
  factory Receipt.fromMap(Map<String, Object?> map) => Receipt(
    id: map[colId] as int?,
    expenseId: map[colExpenseId] as int,
    filePath: map[colFilePath] as String,
    createdAt: map[colCreatedAt] as String,
  );

  @override
  String toString() => 'Receipt(id: $id, expense: $expenseId, $filePath)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Receipt &&
          other.id == id &&
          other.expenseId == expenseId &&
          other.filePath == filePath &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, expenseId, filePath, createdAt);
}
