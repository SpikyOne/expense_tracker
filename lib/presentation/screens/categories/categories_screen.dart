// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран "Категории" - живой список из categoriesProvider.
//
// Стандартные категории (isDefault) показываются с пометкой и без
// действий: защита лежит в DAO (М3.2), UI просто не предлагает правок.
// Свои категории пока тоже без действий — переименование и удаление
// появятся в М7.2.
//
// Контракт мутации: форма добавления делает insert +
// ref.invalidate(categoriesProvider) — экран перечитает список сам.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/models.dart';
import '../../../state/providers.dart';
import 'category_form_screen.dart';

/// Список категорий: стандартные с пометкой, затем свои.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AuroraTheme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Категории'),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            AuroraPageRoute<void>(builder: (_) => const CategoryFormScreen()),
          ),
          child: const Icon(Icons.add),
        ),
        body: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Не удалось загрузить категории',
                    style: theme.textThemeData.regularMedium),
                const SizedBox(height: 8),
                Text('$error'),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(categoriesProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
          data: (categories) {
            final userCount = categories.where((c) => !c.isDefault).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Всего: ${categories.length}'
                    ' • стандартных: ${categories.length - userCount}'
                    ' • своих: $userCount',
                    style: theme.textThemeData.regularMedium,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) =>
                        _CategoryTile(category: categories[index]),
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

/// Строка списка: название + пометка «стандартная» у защищённых.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return ListTile(
      title: Text(category.name, style: theme.textThemeData.regularMedium),
      trailing: category.isDefault
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('стандартная', style: theme.textThemeData.regularMedium),
            )
          : null,
    );
  }
}
