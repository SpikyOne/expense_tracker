// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Форма добавления И правки траты (М5.3).
//
// Два режима одного экрана:
//   * expenseId == null — «Новая трата»: пустая форма, дата = сегодня,
//     сохранение через insert;
//   * expenseId != null — «Правка траты»: поля предзаполняются через
//     ExpenseRepository.getById, сохранение через update (copyWith
//     переносит id и tripId — привязка к командировке не потеряется),
//     доступно удаление с инлайн-подтверждением.
//
// Почему подтверждение не showDialog: AuroraApp построен на WidgetsApp
// и не даёт MaterialLocalizations, а showDialog требует их для
// barrierLabel — упадёт в рантайме. Подтверждение инлайновое.
//
// Контракт мутаций: insert/update/delete через репозиторий ->
// ref.invalidate(expensesProvider + filteredExpensesProvider) ->
// экраны перечитают списки сами. Форма не знает про SQLite.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../domain/models/models.dart';
import '../../../state/providers.dart';

/// Экран формы «Новая трата» / «Правка траты».
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.expenseId});

  /// id траты для правки; null — режим добавления.
  final int? expenseId;

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

  /// Исходная трата в режиме правки; null — режим добавления.
  Expense? _original;

  /// getById не нашёл трату (уже удалена) — рисуем заглушку.
  bool _notFound = false;

  /// true — вместо кнопки «Удалить» показываем подтверждение.
  bool _confirmDelete = false;

  /// "2026-10-24" из DateTime — без intl, руками.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Копейки -> «199,99» для поля ввода (обратный parseMoneyInput).
  static String _kopecksToInput(int kopecks) {
    final rubles = kopecks ~/ 100;
    final remainder = kopecks % 100;
    return '$rubles,${remainder.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final id = widget.expenseId;
    if (id == null) {
      // Режим добавления: дата по умолчанию — сегодня.
      _dateController.text = _isoDate(DateTime.now());
      return;
    }
    // Режим правки: getById синхронный (одна строка по ключу), поэтому
    // предзаполняем форму прямо в initState — без спиннера и family-провайдера.
    final item = ref.read(expenseRepositoryProvider).getById(id);
    if (item == null) {
      _notFound = true;
      return;
    }
    final expense = item.expense;
    _original = expense;
    _amountController.text = _kopecksToInput(expense.amountKopecks);
    _dateController.text = expense.dateIso;
    _payeeController.text = expense.payee;
    _commentController.text = expense.comment;
    _categoryId = expense.categoryId;
    _paymentMethod = expense.paymentMethod;
    _isBusiness = expense.isBusiness;
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
    // В правке _categoryId уже заполнен из БД; фолбэк нужен только добавлению.
    final categoryId = _categoryId ??
        (_original?.categoryId ?? (categories.isEmpty ? null : categories.first.id));
    if (amountKopecks == null || categoryId == null) {
      return; // сумму не пропустит валидатор; без категорий сохранять нечего
    }

    try {
      final original = _original;
      if (original == null) {
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
      } else {
        // copyWith переносит id и tripId: правка не отвяжет трату
        // от командировки (М8) и не перепишет запись с нуля.
        final expense = original.copyWith(
          amountKopecks: amountKopecks,
          dateIso: _dateController.text.trim(),
          categoryId: categoryId,
          payee: _payeeController.text.trim(),
          paymentMethod: _paymentMethod,
          comment: _commentController.text.trim(),
          isBusiness: _isBusiness,
        );
        ref.read(expenseRepositoryProvider).update(expense);
      }
      // Контракт мутации: экран трат перечитает список сам.
      ref.invalidate(expensesProvider);
      // Фильтрованный список экрана трат перечитается тоже.
      ref.invalidate(filteredExpensesProvider);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить трату: $e')),
      );
    }
  }

  // ---------- удаление ----------

  void _delete() {
    final id = _original?.id;
    if (id == null) {
      return;
    }
    try {
      ref.read(expenseRepositoryProvider).delete(id);
      // Список перечитается; чеки SQLite чистит каскадом.
      ref.invalidate(expensesProvider);
      // Фильтрованный список экрана трат перечитается тоже.
      ref.invalidate(filteredExpensesProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _confirmDelete = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить трату: $e')),
      );
    }
  }

  /// Кнопка удаления + инлайн-подтверждение (вместо showDialog —
  /// AuroraApp не даёт MaterialLocalizations, диалог упал бы).
  List<Widget> _deleteSection() {
    final errorColor = Theme.of(context).colorScheme.error;
    return [
      const SizedBox(height: 8),
      if (!_confirmDelete)
        TextButton.icon(
          onPressed: () => setState(() => _confirmDelete = true),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Удалить трату'),
          style: TextButton.styleFrom(foregroundColor: errorColor),
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Удалить эту трату? Вместе с ней удалятся её чеки.'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _confirmDelete = false),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                  style: FilledButton.styleFrom(
                    backgroundColor: errorColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);

    // Трата исчезла между тапом и открытием формы (или удалена извне).
    if (_notFound) {
      return SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const AuroraAppBar(headerText: 'Трата'),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Трата не найдена — возможно, она уже удалена.',
                  style: theme.textThemeData.regularMedium,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Назад'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isEditing = _original != null;
    final categoriesAsync = ref.watch(categoriesProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AuroraAppBar(headerText: isEditing ? 'Правка траты' : 'Новая трата'),
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
                  autofocus: !isEditing,
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
                  label: Text(isEditing ? 'Сохранить изменения' : 'Сохранить трату'),
                ),
                if (isEditing) ..._deleteSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
