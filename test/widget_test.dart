// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Smoke-тест: AuroraApp строится и показывает главный экран.
// Платформенные каналы Авроры в тестовой среде недоступны,
// поэтому проверяем содержимое экрана, а не обёртку.

import 'package:expense_tracker/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AuroraApp строится и показывает главный экран', (tester) async {
    await tester.pumpWidget(const ExpenseTrackerApp());

    // Заголовок корневой страницы — AuroraPageHeader.
    expect(find.text('Трекер расходов'), findsOneWidget);

    // Все пять разделов ТЗ доступны с корня.
    expect(find.text('Траты'), findsOneWidget);
    expect(find.text('Дашборд'), findsOneWidget);
    expect(find.text('Категории'), findsOneWidget);
    expect(find.text('Командировки'), findsOneWidget);
    expect(find.text('Импорт CSV'), findsOneWidget);
  });
}
