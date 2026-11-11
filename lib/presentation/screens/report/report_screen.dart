// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран MD-отчёта (финал): предпросмотр, имя файла, директория, сохранение.
//
// Открывается кнопкой "Отчёт (MD)" на экране трат. Фильтр — снимок
// ExpenseFilter на момент открытия: превью не "прыгает", пока
// пользователь редактирует имя. Данные (список, чеки, категории)
// читаются из тех же провайдеров, что и экран трат.
//
// Сохранение: директория вводится текстом — по ТЗ "в выбранную
// директорию пользователем"; по умолчанию Documents Авроры
// (Permissions=UserDirs в desktop-файле). Каждое сохранение —
// в try/catch: ошибка показывается на экране (требование ТЗ про
// визуальные ошибки при работе с файлами).

import 'dart:convert';
import 'dart:io';

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/models.dart';
import '../../../domain/services/report_service.dart';
import '../../../state/expense_filter.dart';
import '../../../state/providers.dart';

/// Предпросмотр и сохранение MD-отчёта по текущему фильтру трат.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.filter});

  /// Снимок фильтра на момент открытия экрана.
  final ExpenseFilter filter;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  /// Дефолт - Documents текущего пользователя. Литералы абсолютных
  /// путей в коде запрещены: валидатор Авроры отвергает пакет
  /// (BadPackageContent, «Hardcoded path»).
  static String get _defaultDirectory => '${Platform.environment['HOME'] ?? '.'}/Documents';

  /// Символы, запрещённые в имени файла на Linux.
  static final RegExp _badFileNameChars = RegExp(r'[/\\:*?"<>|]');

  late final TextEditingController _nameController;
  late final TextEditingController _directoryController;

  String? _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}-${_p2(now.month)}-${_p2(now.day)}'
        '_${_p2(now.hour)}-${_p2(now.minute)}';
    _nameController = TextEditingController(text: 'отчёт_$stamp');
    _directoryController = TextEditingController(text: _defaultDirectory);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _directoryController.dispose();
    super.dispose();
  }

  String _p2(int v) => v.toString().padLeft(2, '0');

  /// Категория фильтра в человекочитаемом виде для раздела "Фильтры".
  String? _categoryName(List<Category> categories) {
    final id = widget.filter.categoryId;
    if (id == null) return null;
    for (final category in categories) {
      if (category.id == id) return category.name;
    }
    return null;
  }

  String _buildMd({
    required String title,
    required List<Category> categories,
    required List<ExpenseWithCategory> rows,
    required Set<int> receiptIds,
  }) => ReportService.buildMd(
    title: title,
    filterInfo: ReportFilterInfo(
      fromDateIso: widget.filter.fromDateIso,
      toDateIso: widget.filter.toDateIso,
      categoryName: _categoryName(categories),
      paymentMethodTitle: widget.filter.paymentMethod?.title,
      searchText: widget.filter.searchText,
    ),
    rows: rows,
    receiptExpenseIds: receiptIds,
  );

  /// Сохранение: валидация полей, сборка отчёта, запись UTF-8.
  /// Любая ошибка — текстом на экране, приложение не падает.
  Future<void> _save() async {
    final rawName = _nameController.text.trim();
    if (rawName.isEmpty) {
      setState(() => _status = 'Введите имя отчёта.');
      return;
    }
    final directory = _directoryController.text.trim();
    if (directory.isEmpty) {
      setState(() => _status = 'Укажите директорию сохранения.');
      return;
    }
    final rows = ref.read(filteredExpensesProvider).value;
    if (rows == null) {
      setState(() => _status = 'Отчёт ещё не собран — дождись загрузки списка.');
      return;
    }
    final receiptIds = ref.read(receiptExpenseIdsProvider).value ?? <int>{};
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final md = _buildMd(title: rawName, categories: categories, rows: rows, receiptIds: receiptIds);

    final safeName = rawName.replaceAll(_badFileNameChars, '_');
    final fileName = safeName.endsWith('.md') ? safeName : '$safeName.md';
    final file = File('$directory/$fileName');

    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await file.parent.create(recursive: true);
      // Кодировка UTF-8 — требование ТЗ; writeAsString пишет utf8 и
      // по умолчанию, указываем явно, чтобы контракт был виден.
      await file.writeAsString(md, encoding: utf8);
      if (!mounted) return;
      setState(() => _status = 'Сохранено: ${file.path}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка сохранения: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);
    final expensesAsync = ref.watch(filteredExpensesProvider);
    final receiptsAsync = ref.watch(receiptExpenseIdsProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Отчёт (MD)'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Имя отчёта (.md добавится автоматически)',
                      hintText: 'отчёт за октябрь',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _directoryController,
                    decoration: InputDecoration(labelText: 'Директория сохранения', hintText: _defaultDirectory),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Сохранить отчёт'),
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 4),
                    Text(_status!, style: theme.textThemeData.regularMedium),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: expensesAsync.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Не удалось собрать отчёт', style: theme.textThemeData.regularMedium),
                      const SizedBox(height: 8),
                      Text('$error'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          ref.invalidate(filteredExpensesProvider);
                          ref.invalidate(receiptExpenseIdsProvider);
                        },
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
                data: (rows) => receiptsAsync.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text('Не удалось загрузить чеки: $error', style: theme.textThemeData.regularMedium),
                  ),
                  data: (receiptIds) => categoriesAsync.when(
                    skipLoadingOnReload: true,
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text('Не удалось загрузить категории: $error', style: theme.textThemeData.regularMedium),
                    ),
                    // Превью обновляется прямо при вводе имени: отчёт
                    // пересобирается от контроллера, а не от rebuild экрана.
                    data: (categories) => ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _nameController,
                      builder: (context, value, _) {
                        final md = _buildMd(
                          title: value.text.trim().isEmpty ? 'Отчёт по тратам' : value.text.trim(),
                          categories: categories,
                          rows: rows,
                          receiptIds: receiptIds,
                        );
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            md,
                            style: theme.textThemeData.regularMedium.copyWith(fontFamily: 'monospace', fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
