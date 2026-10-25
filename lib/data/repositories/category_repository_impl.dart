// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Реализация CategoryRepository поверх CategoryDao.
//
// Тонкий фасад: владелец SQL - DAO (М3.2), репозиторий лишь предъявляет
// его домену под контрактом из domain/repositories.

import 'package:expense_tracker/data/dao/category_dao.dart';
import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:expense_tracker/domain/repositories/repositories.dart';

/// SQLite-реализация контракта категорий.
class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(DatabaseService db) : _dao = CategoryDao(db);

  final CategoryDao _dao;

  @override
  List<Category> getAll() => _dao.getAll();

  @override
  Category? getById(int id) => _dao.getById(id);

  @override
  int insert(String name) => _dao.insert(name);

  @override
  void rename(int id, String name) => _dao.rename(id, name);

  @override
  void delete(int id) => _dao.delete(id);
}
