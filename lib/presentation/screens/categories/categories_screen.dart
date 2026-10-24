// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';

/// Экран "Категории" - заглушка каркаса. Наполнение — в следующих этапах.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Категории'),
        body: Center(
          child: Text(
            'Управление категориями появится здесь в следующих этапах.',
            style: theme.textThemeData.regularMedium,
          ),
        ),
      ),
    );
  }
}
