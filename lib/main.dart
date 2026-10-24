// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Стартовая точка приложения «Трекер расходов» для ОС Аврора.
//
// Корень - AuroraApp из пакета aurora_controls: нативная тема и
// окружение ОС Аврора вместо Material-скина. Обёртка ProviderScope
// включает Riverpod — состояние приложения живёт через него.
//
// Слои проекта:
//
//   lib/presentation/  - экраны и виджеты (Aurora Controls)
//   lib/state/         - Riverpod-провайдеры и нотифаеры
//   lib/domain/        - модели, интерфейсы, сервисы (чистый Dart)
//   lib/data/          - Drift-база, DAO, репозитории, CSV-слой
//   lib/core/          - утилиты: деньги, даты, форматтеры

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: ExpenseTrackerApp()));
}

/// Корневой виджет приложения.
///
/// AuroraApp — аврора-аналог MaterialApp: даёт нативный вид,
/// поддержку атмосфер ОС и аврора-модель навигации.
class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
  // Окно эмулятора отдаёт светлую тему, при этом атмосфера не отрисована
  // (чёрный холст) — светлые цвета темы на нём нечитаемы.
  return AuroraApp(
    themeMode: ThemeMode.dark, // форс AuroraThemeData.reefDark()
    home: const HomePage(),
  );
}
}

/// Главный экран — корень навигационного стека.
///
/// Сюда ляжет список разделов (Траты, Дашборд, Категории,
/// Командировки, Импорт CSV) с переходами через AuroraPageRoute.
///
/// Паттерн Авроры: на корневом экране нет AuroraAppBar — заголовок
/// оформляется AuroraPageHeader в теле. AuroraAppBar появится на
/// внутренних страницах, куда ведёт AuroraPageRoute.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        // Фон рисует атмосфера ОС: канвас остаётся прозрачным.
        backgroundColor: Colors.transparent,
        body: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16),
              AuroraPageHeader('Трекер расходов'),
              Expanded(
                child: Center(
                  child: Text(
                    'Каркас на AuroraApp готов.\n'
                    'Дальше — навигация по разделам.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
