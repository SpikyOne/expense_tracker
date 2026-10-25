// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Контракт репозитория трат.
//
// Отдаёт пары "трата + категория": списку трат категория нужна всегда,
// требовать второй запрос — лишнее. Про SQLite контракт не знает ничего:
// фильтры выражены доменными понятиями из ТЗ.

import 'package:expense_tracker/domain/models/models.dart';

/// Контракт доступа к тратам.
abstract class ExpenseRepository {
  /// Вставляет трату, возвращает её id. search_text заполняется автоматически.
  int insert(Expense expense);

  /// Перезаписывает трату целиком (кроме id).
  void update(Expense expense);

  /// Трата с категорией по id или null, если такой нет.
  ExpenseWithCategory? getById(int id);

  /// Удаляет трату; её чеки удаляются каскадом.
  void delete(int id);

  /// Выборка трат с категориями: новые раньше; при равной дате —
  /// позже вставленные раньше. Фильтры (не заданные пропускаются):
  ///   * [fromDateIso] / [toDateIso] — период включительно ('2026-10-24');
  ///   * [categoryId], [paymentMethod] — точные совпадения;
  ///   * [searchText] — поиск по получателю и комментарию
  ///     (ё→е, регистр и пунктуация не мешают).
  List<ExpenseWithCategory> query({
    String? fromDateIso,
    String? toDateIso,
    int? categoryId,
    PaymentMethod? paymentMethod,
    String? searchText,
  });
}
