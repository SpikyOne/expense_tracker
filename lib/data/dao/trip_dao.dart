// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// DAO командировок: вставка, правка, удаление, выборка.
//
// Ключевое правило: траты удаляемой поездки НЕ удаляются — SQLite сам
// ставит их trip_id в NULL (FK ON DELETE SET NULL в схеме, foreign_keys
// включён в DatabaseService). DAO ничего дополнительно делать не должен,
// и именно это поведение ловит check_trip_dao.
//
// Валидация периода (end_date >= start_date) живёт в CHECK-ограничении
// схемы — DAO её не дублирует.

import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';

/// Операции с таблицей trips.
class TripDao {
  TripDao(this._db);

  final DatabaseService _db;

  /// Вставляет командировку, возвращает её id.
  int insert(Trip trip) {
    _db.rawExecute(
      'INSERT INTO trips (title, start_date, end_date) VALUES (?, ?, ?);',
      [trip.title, trip.startDateIso, trip.endDateIso],
    );
    return _db.rawSelect('SELECT last_insert_rowid() AS id;').first['id'] as int;
  }

  /// Перезаписывает командировку целиком (кроме id).
  void update(Trip trip) {
    final id = trip.id;
    if (id == null) {
      throw ArgumentError('У командировки для update не заполнен id');
    }
    if (getById(id) == null) {
      throw StateError('Командировка id=$id не найдена — обновление невозможно');
    }
    _db.rawExecute(
      'UPDATE trips SET title = ?, start_date = ?, end_date = ? WHERE id = ?;',
      [trip.title, trip.startDateIso, trip.endDateIso, id],
    );
  }

  /// Командировка по id или null, если такой нет.
  Trip? getById(int id) {
    final rows = _db.rawSelect('SELECT * FROM trips WHERE id = ?;', [id]);
    return rows.isEmpty ? null : Trip.fromMap(rows.first);
  }

  /// Все командировки: позже начинающиеся раньше; при равной дате —
  /// позже вставленные раньше.
  List<Trip> query() {
    final rows = _db.rawSelect('SELECT * FROM trips ORDER BY start_date DESC, id DESC;');
    return [for (final row in rows) Trip.fromMap(row)];
  }

  /// Сколько трат сейчас привязано к поездке - для списка командировок
  /// и подтверждения удаления (появится в М8).
  int expensesCount(int tripId) {
    final rows = _db.rawSelect('SELECT COUNT(*) AS n FROM expenses WHERE trip_id = ?;', [tripId]);
    return rows.first['n'] as int;
  }

  /// Удаляет командировку. Привязанные траты остаются, у них trip_id
  /// становится NULL — за это отвечает ON DELETE SET NULL в схеме.
  void delete(int id) {
    if (getById(id) == null) {
      throw StateError('Командировка id=$id не найдена — удаление невозможно');
    }
    _db.rawExecute('DELETE FROM trips WHERE id = ?;', [id]);
  }
}
