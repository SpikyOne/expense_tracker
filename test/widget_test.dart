// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Smoke-тест: AuroraApp строится и показывает главный экран.
// Платформенные каналы Авроры в тестовой среде недоступны,
// поэтому проверяем содержимое экрана, а не обёртку.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:expense_tracker/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AuroraApp строится и показывает главный экран', (tester) async {
    await tester.pumpWidget(const ExpenseTrackerApp());

    expect(find.byType(AuroraAppBar), findsOneWidget);
    expect(find.textContaining('Каркас на AuroraApp'), findsOneWidget);
  });
}
