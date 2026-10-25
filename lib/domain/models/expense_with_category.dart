// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Пара "трата + её категория" — результат JOIN expenses/categories.
//
// Живёт в домене, а не в data: контракты репозиториев обязаны отдавать
// только доменные типы, чтобы презентация не зависела от слоя хранения.

import 'category.dart';
import 'expense.dart';

/// Трата вместе с её категорией.
class ExpenseWithCategory {
  const ExpenseWithCategory({required this.expense, required this.category});

  final Expense expense;
  final Category category;

  @override
  String toString() => 'ExpenseWithCategory($expense, $category)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseWithCategory && other.expense == expense && other.category == category;

  @override
  int get hashCode => Object.hash(expense, category);
}
