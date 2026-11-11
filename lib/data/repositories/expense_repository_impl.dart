// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Реализация ExpenseRepository поверх ExpenseDao.

import 'package:tracker_1/data/dao/expense_dao.dart';
import 'package:tracker_1/data/database/database_service.dart';
import 'package:tracker_1/domain/models/models.dart';
import 'package:tracker_1/domain/repositories/repositories.dart';

/// SQLite-реализация контракта трат.
class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl(DatabaseService db) : _dao = ExpenseDao(db);

  final ExpenseDao _dao;

  @override
  int insert(Expense expense) => _dao.insert(expense);

  @override
  void update(Expense expense) => _dao.update(expense);

  @override
  ExpenseWithCategory? getById(int id) => _dao.getById(id);

  @override
  void delete(int id) => _dao.delete(id);

  @override
  List<ExpenseWithCategory> query({
    String? fromDateIso,
    String? toDateIso,
    int? categoryId,
    PaymentMethod? paymentMethod,
    String? searchText,
  }) => _dao.query(
    fromDateIso: fromDateIso,
    toDateIso: toDateIso,
    categoryId: categoryId,
    paymentMethod: paymentMethod,
    searchText: searchText,
  );

  @override
  Set<int> receiptExpenseIds() => _dao.receiptExpenseIds();
}
