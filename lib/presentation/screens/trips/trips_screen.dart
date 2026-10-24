// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';

/// Экран "Командировки" - заглушка каркаса. Наполнение — в следующих этапах.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Командировки'),
        body: Center(
          child: Text('Служебные поездки появятся здесь в следующих этапах.', style: theme.textThemeData.regularMedium),
        ),
      ),
    );
  }
}
