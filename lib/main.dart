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

import 'presentation/screens/categories/categories_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/expenses/expenses_screen.dart';
import 'presentation/screens/import_csv/import_csv_screen.dart';
import 'presentation/screens/trips/trips_screen.dart';

import 'dart:ffi';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';

void configureSqliteForAurora() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so.0');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so');
    }
  });
}

void main() {
  configureSqliteForAurora();
  try {
    final db = sqlite3.openInMemory();
    final v = db.select('SELECT sqlite_version() AS v').first['v'];
    debugPrint('SQLite OK, версия: $v');
    db.dispose();
  } catch (e) {
    debugPrint('SQLite FAIL: $e');
  }

  runApp(const ProviderScope(child: ExpenseTrackerApp()));
}

/// Корневой виджет приложения.
///
/// AuroraApp — аврора-аналог MaterialApp: даёт нативный вид,
/// поддержку атмосфер ОС и аврора-модель навигации.
class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  // Ключ навигатора нужен AuroraApp, чтобы показывать индикатор «Назад»
  // у нижнего края экрана на внутренних страницах.
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AuroraApp(navigatorKey: _navKey, themeMode: ThemeMode.dark, home: const HomePage());
  }
}

/// Главный экран — корень навигационного стека.
///
/// Паттерн Авроры: на корневом экране нет AuroraAppBar — заголовок
/// оформляется AuroraPageHeader в теле. AuroraAppBar появится на
/// внутренних страницах, куда ведёт AuroraPageRoute.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final Map<String, WidgetBuilder> _sections = {
    'Траты': (_) => const ExpensesScreen(),
    'Дашборд': (_) => const DashboardScreen(),
    'Категории': (_) => const CategoriesScreen(),
    'Командировки': (_) => const TripsScreen(),
    'Импорт CSV': (_) => const ImportCsvScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                const AuroraPageHeader('Трекер расходов'),
                for (final entry in _sections.entries)
                  ListTile(
                    title: Text(entry.key, style: theme.textThemeData.regularMedium),
                    onTap: () => Navigator.of(context).push(AuroraPageRoute<void>(builder: entry.value)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
