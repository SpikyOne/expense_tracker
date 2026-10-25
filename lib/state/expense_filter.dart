// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Фильтр списка трат (М6.1) - чистый Dart, без Flutter-импортов.
//
// Значения совпадают по смыслу с параметрами ExpenseRepository.query:
// провайдер-фильтр пробрасывает их туда 1:1. null = фильтр не задан.
// Поиск (searchText) готов заранее — его UI появится в М6.2.

import 'package:expense_tracker/domain/models/models.dart';

/// Параметры выборки трат для экрана "Траты".
class ExpenseFilter {
  const ExpenseFilter({
    this.fromDateIso,
    this.toDateIso,
    this.categoryId,
    this.paymentMethod,
    this.searchText,
  });

  /// Левая граница периода включительно ('2026-10-01') или null.
  final String? fromDateIso;

  /// Правая граница периода включительно ('2026-10-31') или null.
  final String? toDateIso;

  /// categories.id или null — «все категории».
  final int? categoryId;

  /// Способ оплаты или null — «все способы».
  final PaymentMethod? paymentMethod;

  /// Подстрока поиска по получателю и комментарию (М6.2) или null.
  final String? searchText;

  /// Задан ли хотя бы один фильтр.
  bool get isActive =>
      fromDateIso != null ||
      toDateIso != null ||
      categoryId != null ||
      paymentMethod != null ||
      searchText != null;

  /// Задан ли период (обе границы или одна).
  bool get hasPeriod => fromDateIso != null || toDateIso != null;

  /// Сколько ГРУПП фильтров активно — для бейджа на экране: период
  /// считается одной группой независимо от числа заданных границ.
  int get activeCount => [
        hasPeriod,
        categoryId != null,
        paymentMethod != null,
        searchText != null,
      ].where((active) => active).length;

  /// Копия с изменёнными полями. Nullable-поля нельзя «присвоить null»
  /// обычным copyWith — как в Expense.copyWith, для сброса есть явные
  /// флаги clear*: clearFrom ? null : (fromDateIso ?? this.fromDateIso).
  ExpenseFilter copyWith({
    String? fromDateIso,
    String? toDateIso,
    int? categoryId,
    PaymentMethod? paymentMethod,
    String? searchText,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearCategory = false,
    bool clearPayment = false,
    bool clearSearch = false,
  }) =>
      ExpenseFilter(
        fromDateIso: clearFrom ? null : (fromDateIso ?? this.fromDateIso),
        toDateIso: clearTo ? null : (toDateIso ?? this.toDateIso),
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        paymentMethod: clearPayment ? null : (paymentMethod ?? this.paymentMethod),
        searchText: clearSearch ? null : (searchText ?? this.searchText),
      );

  @override
  String toString() => 'ExpenseFilter(from: $fromDateIso, to: $toDateIso, '
      'category: $categoryId, payment: $paymentMethod, search: "$searchText")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseFilter &&
          other.fromDateIso == fromDateIso &&
          other.toDateIso == toDateIso &&
          other.categoryId == categoryId &&
          other.paymentMethod == paymentMethod &&
          other.searchText == searchText;

  @override
  int get hashCode =>
      Object.hash(fromDateIso, toDateIso, categoryId, paymentMethod, searchText);
}
