// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';

/// Экран "Траты" - заглушка каркаса. Наполнение — в следующих этапах.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Траты'),
        body: Center(
          child: Text('Список трат появится здесь в следующих этапах.', style: theme.textThemeData.regularMedium),
        ),
      ),
    );
  }
}
