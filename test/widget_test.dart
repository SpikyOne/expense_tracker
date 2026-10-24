// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Smoke-тест каркаса: приложение собирается в дерево виджетов
// и отображает главный экран.

import 'package:expense_tracker/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Каркас строится и показывает главный экран', (tester) async {
    await tester.pumpWidget(const ExpenseTrackerApp());

    expect(find.text('Трекер расходов'), findsWidgets);
    expect(find.textContaining('Каркас проекта'), findsOneWidget);
  });
}
