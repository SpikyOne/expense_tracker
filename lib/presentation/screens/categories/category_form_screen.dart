// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Форма категории, два режима (как форма траты через expenseId):
//   * category == null  — добавление (insert);
//   * category != null  — переименование (rename) + удаление с
//     инлайн-подтверждением (showDialog недоступен: AuroraApp не даёт
//     MaterialLocalizations).
//
// Правила имени: непусто после обрезки пробелов; без дублей — проверка
// по списку categoriesProvider без учёта регистра, сама категория
// исключается (иначе «Кафе» не сохранится со своим же именем). Точный
// дубликат дополнительно ловит UNIQUE в БД.
//
// Контракт мутации: rename/delete меняют имя/привязку категории, а JOIN
// трат несёт это имя — поэтому инвалидируем categoriesProvider вместе
// с expensesProvider и filteredExpensesProvider.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/models.dart';
import '../../../state/providers.dart';

/// Экран формы «Новая категория» / «Переименовать категорию».
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.category});

  /// Не null — режим переименования этой категории.
  final Category? category;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  /// Шаг 1 инлайн-подтверждения удаления (шаг 2 — кнопка «Удалить»).
  bool _confirmDelete = false;

  bool get _isRename => widget.category != null;

  @override
  void initState() {
    super.initState();
    // Prefill в режиме переименования — по образцу формы траты.
    _nameController.text = widget.category?.name ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------- валидация ----------

  String? _validateName(String? value, List<Category> existing) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Введите название';
    }
    final lower = text.toLowerCase();
    // Свою категорию исключаем: переименование в своё же имя законно.
    final excludeId = widget.category?.id;
    final duplicate = existing
        .any((c) => c.id != excludeId && c.name.toLowerCase() == lower);
    if (duplicate) {
      return 'Такая категория уже есть';
    }
    return null;
  }

  // ---------- мутации ----------

  /// Общий хвост insert/rename/delete: обновляем все зависимые списки
  /// и возвращаемся назад.
  void _finishAndPop() {
    ref.invalidate(categoriesProvider);
    // JOIN трат несёт имя категории — списки трат тоже устарели.
    ref.invalidate(expensesProvider);
    ref.invalidate(filteredExpensesProvider);
    Navigator.of(context).pop();
  }

  void _save(List<Category> existing) {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    // Гасим клавиатуру до вставки: поп анимируется без её схлопывания.
    FocusScope.of(context).unfocus();
    final category = widget.category;
    try {
      final repository = ref.read(categoryRepositoryProvider);
      if (category == null) {
        repository.insert(_nameController.text);
      } else {
        // Категория пришла из БД — id гарантированно не null.
        repository.rename(category.id!, _nameController.text);
      }
      _finishAndPop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить категорию: $e')),
      );
    }
  }

  void _delete() {
    final id = widget.category?.id;
    if (id == null) {
      return;
    }
    try {
      // DAO сам переносит траты категории в «Без категории».
      ref.read(categoryRepositoryProvider).delete(id);
      _finishAndPop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить категорию: $e')),
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
        appBar: AuroraAppBar(
          headerText: _isRename ? 'Переименовать категорию' : 'Новая категория',
        ),
        body: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Не удалось загрузить категории: $error')),
          data: (categories) => Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Название',
                    hintText: _isRename ? null : 'Например, Спортзал',
                  ),
                  validator: (value) => _validateName(value, categories),
                  // У TextFormField именно onFieldSubmitted (урок М6.2).
                  onFieldSubmitted: (_) => _save(categories),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _save(categories),
                  icon: const Icon(Icons.check),
                  label: Text(_isRename ? 'Сохранить' : 'Добавить категорию'),
                ),

                // Удаление — только в режиме переименования. Стандартные
                // сюда не попадают: у их строк в списке onTap нет.
                if (_isRename) ...[
                  const SizedBox(height: 24),
                  if (!_confirmDelete)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        onPressed: () => setState(() => _confirmDelete = true),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Удалить категорию'),
                      ),
                    )
                  else ...[
                    Text(
                      'Удалить «${widget.category!.name}»? '
                      'Её траты переедут в «Без категории».',
                      style: theme.textThemeData.regularMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          onPressed: _delete,
                          child: const Text('Удалить'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () =>
                              setState(() => _confirmDelete = false),
                          child: const Text('Отмена'),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
