// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';

/// Экран "Импорт CSV" - заглушка каркаса. Наполнение — в следующих этапах.
class ImportCsvScreen extends StatelessWidget {
  const ImportCsvScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Импорт CSV'),
        body: Center(
          child: Text(
            'Загрузка расходов из CSV появится здесь в следующих этапах.',
            style: theme.textThemeData.regularMedium,
          ),
        ),
      ),
    );
  }
}
