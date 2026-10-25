// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Форма добавления траты.
//
// Поля: сумма (копейки через parseMoneyInput), дата (ISO ГГГГ-ММ-ДД),
// категория и способ оплаты (чипы — без MaterialLocalizations, которых
// AuroraApp не даёт), получатель, комментарий, признак служебной.
// Поле "командировка" появится позднее, пока tripId = null.
//
// Контракт мутации: insert через репозиторий -> ref.invalidate(expensesProvider)
// -> список на экране трат перечитается сам. Форма не знает про SQLite.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../domain/models/models.dart';
import '../../../state/providers.dart';

/// Экран формы «Новая трата».
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  /// Дата обязана быть строго ГГГГ-ММ-ДД: для ISO-дат строковая
  /// сортировка в SQLite совпадает с календарной.
  static final RegExp _dateRegExp = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _payeeController = TextEditingController();
  final _commentController = TextEditingController();

  int? _categoryId;
  PaymentMethod _paymentMethod = PaymentMethod.card;
  bool _isBusiness = false;

  /// "2026-10-24" из DateTime — без intl, руками.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _dateController.text = _isoDate(DateTime.now());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dateController.dispose();
    _payeeController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // ---------- валидаторы ----------

  String? _validateAmount(String? value) =>
      parseMoneyInput(value ?? '') == null ? 'Введите сумму, например 199,99' : null;

  String? _validateDate(String? value) {
    final text = (value ?? '').trim();
    if (!_dateRegExp.hasMatch(text) || DateTime.tryParse(text) == null) {
      return 'Формат ГГГГ-ММ-ДД, например 2026-10-24';
    }
    return null;
  }

  // ---------- сохранение ----------

  void _save(List<Category> categories) {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final amountKopecks = parseMoneyInput(_amountController.text);
    final categoryId = _categoryId ?? (categories.isEmpty ? null : categories.first.id);
    if (amountKopecks == null || categoryId == null) {
      return; // сумму не пропустит валидатор; без категорий сохранять нечего
    }

    try {
      final expense = Expense(
        amountKopecks: amountKopecks,
        dateIso: _dateController.text.trim(),
        categoryId: categoryId,
        payee: _payeeController.text.trim(),
        paymentMethod: _paymentMethod,
        comment: _commentController.text.trim(),
        isBusiness: _isBusiness,
      );
      ref.read(expenseRepositoryProvider).insert(expense);
      // Контракт мутации: экран трат перечитает список сам.
      ref.invalidate(expensesProvider);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить трату: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Новая трата'),
        body: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Не удалось загрузить категории: $error')),
          data: (categories) => Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Сумма, ₽', hintText: '199,99'),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dateController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Дата (ГГГГ-ММ-ДД)'),
                  validator: _validateDate,
                ),
                const SizedBox(height: 16),
                Text('Категория', style: theme.textThemeData.regularMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in categories)
                      ChoiceChip(
                        label: Text(category.name),
                        selected: _categoryId == null
                            ? identical(category, categories.first)
                            : category.id == _categoryId,
                        onSelected: (_) => setState(() => _categoryId = category.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Способ оплаты', style: theme.textThemeData.regularMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final method in PaymentMethod.values)
                      ChoiceChip(
                        label: Text(method.title),
                        selected: _paymentMethod == method,
                        onSelected: (_) => setState(() => _paymentMethod = method),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _payeeController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Получатель платежа',
                    hintText: 'ООО Ромашка',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _commentController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Комментарий', hintText: 'Необязательно'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Служебная трата', style: theme.textThemeData.regularMedium),
                  value: _isBusiness,
                  onChanged: (value) => setState(() => _isBusiness = value),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _save(categories),
                  icon: const Icon(Icons.check),
                  label: const Text('Сохранить трату'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
