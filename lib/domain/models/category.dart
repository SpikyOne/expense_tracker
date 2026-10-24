// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Модель категории трат - чистый Dart, без Flutter-импортов.
//
// Категории делятся на стандартные (8 штук из ТЗ — защищены от удаления
// и переименования) и пользовательские. Хранение — таблица categories:
//
//   id          INTEGER PRIMARY KEY AUTOINCREMENT
//   name        TEXT NOT NULL UNIQUE
//   is_default  INTEGER NOT NULL DEFAULT 0 (1 — стандартная)

/// Категория трат: «Продукты», «Транспорт» и т.д.
class Category {
  /// Имена колонок таблицы categories — единый источник правды:
  /// toMap/fromMap здесь и CREATE TABLE в слое data используют их.
  static const colId = 'id';
  static const colName = 'name';
  static const colIsDefault = 'is_default';

  /// id в БД; null — категория ещё не сохранена.
  final int? id;

  /// Название, показываемое пользователю («Продукты»).
  final String name;

  /// Стандартная категория из ТЗ — удалять и переименовывать нельзя.
  final bool isDefault;

  const Category({this.id, required this.name, this.isDefault = false});

  /// Та же категория с изменёнными полями — для правок и сидов.
  Category copyWith({int? id, String? name, bool? isDefault}) =>
      Category(id: id ?? this.id, name: name ?? this.name, isDefault: isDefault ?? this.isDefault);

  /// Строка для INSERT/UPDATE в SQLite.
  /// id не пишем, когда null — SQLite сам подставит AUTOINCREMENT.
  Map<String, Object?> toMap() => {if (id != null) colId: id, colName: name, colIsDefault: isDefault ? 1 : 0};

  /// Строка из SELECT; INTEGER -> bool возвращаем вручную.
  factory Category.fromMap(Map<String, Object?> map) =>
      Category(id: map[colId] as int?, name: map[colName] as String, isDefault: (map[colIsDefault] as int? ?? 0) != 0);

  @override
  String toString() => 'Category(id: $id, name: $name, isDefault: $isDefault)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category && other.id == id && other.name == name && other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(id, name, isDefault);
}
