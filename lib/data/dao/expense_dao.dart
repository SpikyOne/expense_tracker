// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// DAO трат: вставка, правка, удаление, выборка с JOIN на категорию.
//
// Ключевое правило: денормализованную колонку search_text заполняет
// ТОЛЬКО этот DAO — при каждой вставке и правке строку считает
// Expense.buildSearchText (lower, ё→е, пунктуация → пробел). Голый SQL
// мимо DAO оставит колонку пустой — именно это ловил check_database
// в М3.1.

import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';

/// Операции с таблицей expenses.
class ExpenseDao {
  ExpenseDao(this._db);

  final DatabaseService _db;

  /// Колонки траты + колонки категории с алиасами c_ — чтобы имена
  /// в строке результата не пересекались (id есть в обеих таблицах).
  static const _selectSql =
      'e.id, e.amount_kopecks, e.date_iso, e.category_id, e.payee, '
      'e.payment_method, e.comment, e.is_business, e.trip_id, '
      'c.id AS c_id, c.name AS c_name, c.is_default AS c_is_default';

  /// Разбор строки JOIN-выборки в пару «трата + категория».
  /// Expense.fromMap читает свои колонки, лишние (c_*) игнорирует.
  static ExpenseWithCategory _fromRow(Map<String, Object?> row) =>
      ExpenseWithCategory(
        expense: Expense.fromMap(row),
        category: Category(
          id: row['c_id'] as int?,
          name: row['c_name'] as String,
          isDefault: (row['c_is_default'] as int? ?? 0) != 0,
        ),
      );

  /// Вставляет трату, возвращает её id.
  /// search_text заполняется автоматически из payee и comment.
  int insert(Expense expense) {
    _db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payee, '
      'payment_method, comment, is_business, trip_id, search_text) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        expense.amountKopecks,
        expense.dateIso,
        expense.categoryId,
        expense.payee,
        expense.paymentMethod.storageKey,
        expense.comment,
        expense.isBusiness ? 1 : 0,
        expense.tripId,
        Expense.buildSearchText(expense.payee, expense.comment),
      ],
    );
    return _db
        .rawSelect('SELECT last_insert_rowid() AS id;')
        .first['id'] as int;
  }

  /// Перезаписывает трату целиком (кроме id).
  /// search_text пересчитывается — правка комментария/получателя
  /// сразу видна поиску.
  void update(Expense expense) {
    final id = expense.id;
    if (id == null) {
      throw ArgumentError('У траты для update не заполнен id');
    }
    if (getById(id) == null) {
      throw StateError('Трата id=$id не найдена — обновление невозможно');
    }
    _db.rawExecute(
      'UPDATE expenses SET amount_kopecks = ?, date_iso = ?, category_id = ?, '
      'payee = ?, payment_method = ?, comment = ?, is_business = ?, '
      'trip_id = ?, search_text = ? WHERE id = ?;',
      [
        expense.amountKopecks,
        expense.dateIso,
        expense.categoryId,
        expense.payee,
        expense.paymentMethod.storageKey,
        expense.comment,
        expense.isBusiness ? 1 : 0,
        expense.tripId,
        Expense.buildSearchText(expense.payee, expense.comment),
        id,
      ],
    );
  }

  /// Трата с категорией по id или null, если такой нет.
  ExpenseWithCategory? getById(int id) {
    final rows = _db.rawSelect(
      'SELECT $_selectSql FROM expenses e '
      'JOIN categories c ON c.id = e.category_id '
      'WHERE e.id = ?;',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Удаляет трату; её чеки удаляет SQLite каскадом (ON DELETE CASCADE).
  void delete(int id) {
    if (getById(id) == null) {
      throw StateError('Трата id=$id не найдена — удаление невозможно');
    }
    _db.rawExecute('DELETE FROM expenses WHERE id = ?;', [id]);
  }

  /// Выборка трат с категориями: новые раньше; при равной дате —
  /// позже вставленные раньше.
  ///
  /// Фильтры (не заданные пропускаются):
  ///   * [fromDateIso] / [toDateIso] — границы периода включительно,
  ///     формат как в Expense.dateIso ('2026-10-24'); для ISO-дат
  ///     строковое сравнение совпадает со сравнением дат;
  ///   * [categoryId], [paymentMethod] — точные совпадения;
  ///   * [searchText] — нормализуется через Expense.buildSearchText
  ///     и ищется как подстрока в search_text (получатель и комментарий);
  ///     запрос из одних знаков препинания после нормализации пуст —
  ///     фильтр тогда пропускается.
  List<ExpenseWithCategory> query({
    String? fromDateIso,
    String? toDateIso,
    int? categoryId,
    PaymentMethod? paymentMethod,
    String? searchText,
  }) {
    final conditions = <String>[];
    final params = <Object?>[];

    if (fromDateIso != null) {
      conditions.add('e.date_iso >= ?');
      params.add(fromDateIso);
    }
    if (toDateIso != null) {
      conditions.add('e.date_iso <= ?');
      params.add(toDateIso);
    }
    if (categoryId != null) {
      conditions.add('e.category_id = ?');
      params.add(categoryId);
    }
    if (paymentMethod != null) {
      conditions.add('e.payment_method = ?');
      params.add(paymentMethod.storageKey);
    }
    if (searchText != null) {
      final normalized = Expense.buildSearchText(searchText, '');
      if (normalized.isNotEmpty) {
        conditions.add('e.search_text LIKE ?');
        params.add('%$normalized%');
      }
    }

    final whereSql = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')} ';
    final rows = _db.rawSelect(
      'SELECT $_selectSql FROM expenses e '
      'JOIN categories c ON c.id = e.category_id '
      '$whereSql'
      'ORDER BY e.date_iso DESC, e.id DESC;',
      params,
    );
    return [for (final row in rows) _fromRow(row)];
  }
}
