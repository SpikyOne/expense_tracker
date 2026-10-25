// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Реализация TripRepository поверх TripDao.

import 'package:expense_tracker/data/dao/trip_dao.dart';
import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:expense_tracker/domain/repositories/repositories.dart';

/// SQLite-реализация контракта командировок.
class TripRepositoryImpl implements TripRepository {
  TripRepositoryImpl(DatabaseService db) : _dao = TripDao(db);

  final TripDao _dao;

  @override
  int insert(Trip trip) => _dao.insert(trip);

  @override
  void update(Trip trip) => _dao.update(trip);

  @override
  Trip? getById(int id) => _dao.getById(id);

  @override
  List<Trip> query() => _dao.query();

  @override
  int expensesCount(int tripId) => _dao.expensesCount(tripId);

  @override
  void delete(int id) => _dao.delete(id);
}
