// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран "Траты": список + панель фильтров (М6.1).
//
// Данные: filteredExpensesProvider — FutureProvider поверх репозитория,
// читает expenseFilterProvider. Панель фильтров инлайновая, под аппбаром:
// AuroraApp не даёт MaterialLocalizations, поэтому никаких
// showModalBottomSheet/showDatePicker — период вводится текстом
// ГГГГ-ММ-ДД, как в форме траты.
//
// Панель живёт ВНЕ .when списка: переключение чипов перезагружает
// FutureProvider, и панель не должна мигать вместе со списком.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../domain/models/models.dart';
import '../../../state/providers.dart';
import 'expense_form_screen.dart';

/// Список трат с фильтрами: получатель, категория, дата, оплата, сумма.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  bool _filtersExpanded = false;

  void _resetFilters() {
    ref.read(expenseFilterProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    final filter = ref.watch(expenseFilterProvider);
    final expensesAsync = ref.watch(filteredExpensesProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Траты'),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            AuroraPageRoute<void>(builder: (_) => const ExpenseFormScreen()),
          ),
          child: const Icon(Icons.add),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Переключатель панели: вне .when — не мигает при перезагрузках.
            ListTile(
              dense: true,
              leading: const Icon(Icons.tune),
              onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
              title: Text(
                filter.activeCount > 0 ? 'Фильтры (${filter.activeCount})' : 'Фильтры',
                style: theme.textThemeData.regularMedium,
              ),
              trailing: Icon(_filtersExpanded ? Icons.expand_less : Icons.expand_more),
            ),
            if (_filtersExpanded) const _FilterPanel(),
            Expanded(
              child: expensesAsync.when(
                // Чипы перезагружают список: держим прежние данные,
                // чтобы список не мигал спиннером на каждый тап.
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Не удалось загрузить траты', style: theme.textThemeData.regularMedium),
                      const SizedBox(height: 8),
                      Text('$error'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => ref.invalidate(filteredExpensesProvider),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
                data: (expenses) {
                  if (expenses.isEmpty) {
                    if (filter.isActive) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ничего не найдено по фильтрам.',
                              style: theme.textThemeData.regularMedium,
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _resetFilters,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Сбросить фильтры'),
                            ),
                          ],
                        ),
                      );
                    }
                    return Center(
                      child: Text(
                        'Пока нет трат.\nНажмите «+», чтобы добавить первую.',
                        textAlign: TextAlign.center,
                        style: theme.textThemeData.regularMedium,
                      ),
                    );
                  }
                  final total =
                      expenses.fold<int>(0, (sum, item) => sum + item.expense.amountKopecks);
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Трат: ${expenses.length} • Итого: ${formatMoney(total)}',
                          style: theme.textThemeData.regularMedium,
                        ),
                      ),
                      for (final item in expenses) _ExpenseTile(item: item),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка списка: заголовок - получатель или категория,
/// подзаголовок — дата, категория, способ оплаты, признак служебной.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.item});

  final ExpenseWithCategory item;

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    final expense = item.expense;
    final subtitleParts = <String>[
      formatDateShort(expense.date),
      if (expense.payee.isNotEmpty) item.category.name,
      expense.paymentMethod.title,
      if (expense.isBusiness) 'служебная',
    ];
    return ListTile(
      onTap: () => Navigator.of(context).push(
        AuroraPageRoute<void>(
          builder: (_) => ExpenseFormScreen(expenseId: expense.id),
        ),
      ),
      title: Text(
        expense.payee.isEmpty ? item.category.name : expense.payee,
        style: theme.textThemeData.regularMedium,
      ),
      subtitle: Text(subtitleParts.join(' • ')),
      trailing: Text(formatMoney(expense.amountKopecks), style: theme.textThemeData.regularMedium),
    );
  }
}

/// Панель фильтров: период, категория, способ оплаты + сброс.
///
/// Отдельный ConsumerStatefulWidget и живёт в дереве только когда
/// раскрыт: контроллеры дат создаются заново при каждом открытии —
/// синхронизация с провайдером получается бесплатно.
class _FilterPanel extends ConsumerStatefulWidget {
  const _FilterPanel();

  @override
  ConsumerState<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends ConsumerState<_FilterPanel> {
  /// Формат даты тот же, что в форме траты: строго ГГГГ-ММ-ДД.
  static final RegExp _dateRegExp = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(expenseFilterProvider);
    _fromController = TextEditingController(text: filter.fromDateIso ?? '');
    _toController = TextEditingController(text: filter.toDateIso ?? '');
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  String? _validateDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null; // пустое поле — граница периода просто не задана
    }
    if (!_dateRegExp.hasMatch(text) || DateTime.tryParse(text) == null) {
      return 'Формат ГГГГ-ММ-ДД, например 2026-10-24';
    }
    return null;
  }

  /// Дата применяется к фильтру сразу, как только введена полностью
  /// и валидна; частично набранная — игнорируется (провайдер хранит
  /// последнюю валидную границу, ошибка видна под полем). Стерёл дату —
  /// граница снята сразу.
  void _onDateChanged({required bool isFrom, required String value}) {
    final text = value.trim();
    final notifier = ref.read(expenseFilterProvider.notifier);
    if (text.isEmpty) {
      if (isFrom) {
        notifier.setFrom(null);
      } else {
        notifier.setTo(null);
      }
      return;
    }
    if (_dateRegExp.hasMatch(text) && DateTime.tryParse(text) != null) {
      if (isFrom) {
        notifier.setFrom(text);
      } else {
        notifier.setTo(text);
      }
    }
  }

  void _reset() {
    ref.read(expenseFilterProvider.notifier).reset();
    _fromController.clear();
    _toController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    final filter = ref.watch(expenseFilterProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _fromController,
                  keyboardType: TextInputType.datetime,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(labelText: 'Период от', hintText: '2026-10-01'),
                  validator: _validateDate,
                  onChanged: (value) => _onDateChanged(isFrom: true, value: value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _toController,
                  keyboardType: TextInputType.datetime,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(labelText: 'Период до', hintText: '2026-10-31'),
                  validator: _validateDate,
                  onChanged: (value) => _onDateChanged(isFrom: false, value: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Категория', style: theme.textThemeData.regularMedium),
          const SizedBox(height: 8),
          categoriesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => const Text('Категории недоступны'),
            data: (categories) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Все'),
                  selected: filter.categoryId == null,
                  onSelected: (_) => ref.read(expenseFilterProvider.notifier).setCategory(null),
                ),
                for (final category in categories)
                  ChoiceChip(
                    label: Text(category.name),
                    selected: filter.categoryId == category.id,
                    onSelected: (_) =>
                        ref.read(expenseFilterProvider.notifier).setCategory(category.id!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Способ оплаты', style: theme.textThemeData.regularMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Все'),
                selected: filter.paymentMethod == null,
                onSelected: (_) => ref.read(expenseFilterProvider.notifier).setPayment(null),
              ),
              for (final method in PaymentMethod.values)
                ChoiceChip(
                  label: Text(method.title),
                  selected: filter.paymentMethod == method,
                  onSelected: (_) => ref.read(expenseFilterProvider.notifier).setPayment(method),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: filter.isActive ? _reset : null,
              icon: const Icon(Icons.clear_all),
              label: const Text('Сбросить'),
            ),
          ),
        ],
      ),
    );
  }
}
