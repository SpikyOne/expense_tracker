// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран "Траты" - первый живой экран.
//
// Данные приходят из expensesProvider (FutureProvider поверх репозитория):
// экран не знает про SQLite и DAO, работает только с доменными типами.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/money.dart';
import '../../../domain/models/models.dart';
import '../../../state/providers.dart';
import 'expense_form_screen.dart';

/// Список трат: получатель, категория, дата, способ оплаты, сумма.
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AuroraTheme.of(context);
    final expensesAsync = ref.watch(expensesProvider);

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
        body: expensesAsync.when(
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
                  onPressed: () => ref.invalidate(expensesProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
          data: (expenses) {
            if (expenses.isEmpty) {
              return Center(
                child: Text(
                  'Пока нет трат.\nНажмите «+», чтобы добавить первую.',
                  textAlign: TextAlign.center,
                  style: theme.textThemeData.regularMedium,
                ),
              );
            }
            final total = expenses.fold<int>(0, (sum, item) => sum + item.expense.amountKopecks);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Трат: ${expenses.length} • Итого: ${formatMoney(total)}',
                    style: theme.textThemeData.regularMedium,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: expenses.length,
                    itemBuilder: (context, index) => _ExpenseTile(item: expenses[index]),
                  ),
                ),
              ],
            );
          },
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
