// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// DAO категорий: список, вставка, переименование, удаление.
//
// Бизнес-правила живут здесь, а не в SQL (без триггеров их там
// не выразить):
//   * стандартные категории (is_default = 1) защищены — их нельзя
//     переименовывать и удалять;
//   * при удалении пользовательской категории её траты переносятся
//     в служебную «Без категории»: category_id в expenses NOT NULL,
//     поэтому "трат без категории" в базе не бывает.

import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';

/// Операции с таблицей categories.
class CategoryDao {
  CategoryDao(this._db);

  final DatabaseService _db;

  /// Все категории: стандартные по алфавиту ("Без категории" — последней
  /// среди стандартных), затем пользовательские по алфавиту.
  List<Category> getAll() {
    final rows = _db.rawSelect(
      'SELECT id, name, is_default FROM categories '
      'ORDER BY is_default DESC, name = ?, name;',
      [DatabaseService.uncategorizedName],
    );
    return [for (final row in rows) Category.fromMap(row)];
  }

  /// Категория по id или null, если такой нет.
  Category? getById(int id) {
    final rows = _db.rawSelect(
      'SELECT id, name, is_default FROM categories WHERE id = ?;',
      [id],
    );
    return rows.isEmpty ? null : Category.fromMap(rows.first);
  }

  /// Вставляет пользовательскую категорию (is_default = 0), возвращает id.
  ///
  /// Имя обрезается от пробелов; пустое (в том числе из одних пробелов) —
  /// ArgumentError. Дубликат имени, включая совпадение со стандартной
  /// категорией, отклонит UNIQUE-ограничение БД (SqliteException).
  int insert(String name) {
    final trimmed = _validateName(name);
    _db.rawExecute(
      'INSERT INTO categories (name, is_default) VALUES (?, 0);',
      [trimmed],
    );
    return _db
        .rawSelect('SELECT last_insert_rowid() AS id;')
        .first['id'] as int;
  }

  /// Переименовывает пользовательскую категорию.
  ///
  /// Имя проверяется как в [insert]; дубликат имени отклонит UNIQUE.
  /// Стандартная категория — StateError.
  void rename(int id, String name) {
    _requireUserCategory(id, 'переименовать');
    final trimmed = _validateName(name);
    _db.rawExecute(
      'UPDATE categories SET name = ? WHERE id = ?;',
      [trimmed, id],
    );
  }

  /// Удаляет пользовательскую категорию. Траты категории заранее
  /// переносятся в "Без категории", поэтому ни одна трата не теряется.
  /// Стандартная категория (включая "Без категории") — StateError.
  void delete(int id) {
    _requireUserCategory(id, 'удалить');
    final uncategorizedId = _uncategorizedId();
    _db.rawExecute(
      'UPDATE expenses SET category_id = ? WHERE category_id = ?;',
      [uncategorizedId, id],
    );
    _db.rawExecute('DELETE FROM categories WHERE id = ?;', [id]);
  }

  // ---------- Внутреннее ----------

  /// Обрезает имя и запрещает пустое. Дубликаты ловит UNIQUE в БД.
  String _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Имя категории не может быть пустым');
    }
    return trimmed;
  }

  /// Находит категорию по id и убеждается, что её можно изменять.
  /// [action] — глагол для текста ошибки: «переименовать», «удалить».
  void _requireUserCategory(int id, String action) {
    final category = getById(id);
    if (category == null) {
      throw StateError('Категория id=$id не найдена — $action невозможно');
    }
    if (category.isDefault) {
      throw StateError(
        'Стандартную категорию «${category.name}» нельзя $action',
      );
    }
  }

  /// id служебной категории-приёмника. Её создаёт сид, отсутствие -
  /// признак испорченной БД.
  int _uncategorizedId() {
    final rows = _db.rawSelect(
      'SELECT id FROM categories WHERE name = ?;',
      [DatabaseService.uncategorizedName],
    );
    if (rows.isEmpty) {
      throw StateError(
        'Служебная категория «${DatabaseService.uncategorizedName}» не найдена',
      );
    }
    return rows.first['id'] as int;
  }
}
