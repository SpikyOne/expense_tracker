// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Контракт репозитория командировок.
// Удаление поездки НЕ трогает траты: они отвязываются (trip_id -> NULL).

import 'package:expense_tracker/domain/models/models.dart';

/// Контракт доступа к командировкам.
abstract class TripRepository {
  /// Вставляет командировку, возвращает её id.
  int insert(Trip trip);

  /// Перезаписывает командировку целиком (кроме id).
  void update(Trip trip);

  /// Командировка по id или null, если такой нет.
  Trip? getById(int id);

  /// Все командировки: позже начинающиеся раньше.
  List<Trip> query();

  /// Сколько трат сейчас привязано к поездке.
  int expensesCount(int tripId);

  /// Удаляет командировку; траты остаются и отвязываются (SET NULL).
  void delete(int id);
}
