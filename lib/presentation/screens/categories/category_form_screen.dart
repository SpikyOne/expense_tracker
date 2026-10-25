// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Форма добавления своей категории - одно поле.
//
// Правила (М7.1):
//   * непусто после обрезки пробелов (DAO пере-проверит и бросит
//     ArgumentError, но UI не пускает пустые заранее);
//   * без дублей: проверка по списку categoriesProvider без учёта
//     регистра; точный дубликат дополнительно ловит UNIQUE в БД.
//
// Контракт мутации: insert через репозиторий ->
// ref.invalidate(categoriesProvider) -> все потребители категорий
// (экран списка, чипы фильтров, чипы формы траты) перечитаются сами.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/models.dart';
import '../../../state/providers.dart';

/// Экран формы «Новая категория».
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key});

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------- валидация ----------

  /// Непусто и не дубликат (без учёта регистра). Список существующих
  /// передаём при построении формы — валидатор всегда сверяется с
  /// актуальными данными провайдера.
  String? _validateName(String? value, List<Category> existing) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Введите название';
    }
    final lower = text.toLowerCase();
    if (existing.any((c) => c.name.toLowerCase() == lower)) {
      return 'Такая категория уже есть';
    }
    return null;
  }

  // ---------- сохранение ----------

  void _save(List<Category> existing) {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    // Гасим клавиатуру до вставки: поп анимируется без её схлопывания.
    FocusScope.of(context).unfocus();
    try {
      // Валидатор гарантирует непустоту; DAO ещё раз обрежет пробелы.
      ref.read(categoryRepositoryProvider).insert(_nameController.text);
      // Контракт мутации: потребители категорий перечитают список сами.
      ref.invalidate(categoriesProvider);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить категорию: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Новая категория'),
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
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    hintText: 'Например, Спортзал',
                  ),
                  validator: (value) => _validateName(value, categories),
                  // У TextFormField именно onFieldSubmitted (урок М6.2).
                  onFieldSubmitted: (_) => _save(categories),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _save(categories),
                  icon: const Icon(Icons.check),
                  label: const Text('Добавить категорию'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
