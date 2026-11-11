// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Стартовая точка приложения «Трекер расходов» для ОС Авроры.
//
// Корень - AuroraApp из пакета aurora_controls: нативная тема и
// окружение ОС Аврора вместо Material-скина. Обёртка ProviderScope
// включает Riverpod - состояние приложения живёт через него.
//
// БД в main() не открывается (TODO М2.6 закрыт в М4.3): соединение
// создаётся лениво провайдером databaseProvider из lib/state/providers.dart
// при первом обращении к данным и закрывается вместе с контейнером.
//
// Слои проекта:
//
//   lib/presentation/  - экраны и виджеты (Aurora Controls)
//   lib/state/         - Riverpod-провайдеры и нотифаеры
//   lib/domain/        - модели, интерфейсы, сервисы (чистый Dart)
//   lib/data/          - SQLite (sqlite3 FFI), DAO, репозитории, CSV-слой
//   lib/core/          - утилиты: деньги, даты, форматтеры

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/screens/categories/categories_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/expenses/expenses_screen.dart';
import 'presentation/screens/import_csv/import_csv_screen.dart';
import 'presentation/screens/trips/trips_screen.dart';

import 'core/pin_service.dart';
import 'presentation/screens/pin/pin_screen.dart';
import 'state/providers.dart' show databaseProvider;

void main() {
  // ScaffoldMessenger - хост для SnackBar. MaterialApp ставит его сам,
  // но AuroraApp построен на WidgetsApp и не ставит: добавляем вручную
  // один раз на уровне приложения, чтобы SnackBar работал на всех экранах.
  runApp(const ProviderScope(child: ScaffoldMessenger(child: ExpenseTrackerApp())));
}

/// Корневой виджет приложения.
///
/// AuroraApp - аврора-аналог MaterialApp: даёт нативный вид,
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
    // ТЗ финала: пин обязателен при любом варианте запуска.
    // PinScreen сам решает, какой режим показать (создание или ввод).
    return AuroraApp(navigatorKey: _navKey, themeMode: ThemeMode.dark, home: const PinScreen());
  }
}

/// Главный экран - корень навигационного стека.
///
/// Паттерн Авроры: на корневом экране нет AuroraAppBar - заголовок
/// оформляется AuroraPageHeader в теле. AuroraAppBar появится на
/// внутренних страницах, куда ведёт AuroraPageRoute.
///
/// Финал: кнопка сброса пина и данных - инлайн-подтверждение вторым
/// нажатием (showDialog в AuroraApp недоступен, см. expense_form_screen).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static final Map<String, WidgetBuilder> _sections = {
    'Траты': (_) => const ExpensesScreen(),
    'Дашборд': (_) => const DashboardScreen(),
    'Категории': (_) => const CategoriesScreen(),
    'Командировки': (_) => const TripsScreen(),
    'Импорт CSV': (_) => const ImportCsvScreen(),
  };

  bool _confirmReset = false;

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
                const SizedBox(height: 24),
                // ТЗ финала: возможность сбросить пин с очисткой данных.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _onResetPressed,
                      child: Text(_confirmReset ? 'Точно сбросить? Нажмите ещё раз' : 'Сбросить пин и данные'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onResetPressed() {
    if (!_confirmReset) {
      setState(() => _confirmReset = true);
      return;
    }
    // 1. Закрываем БД (invalidate -> onDispose -> db.close()),
    //    иначе файл expenses.db не удалится.
    ref.invalidate(databaseProvider);
    // 2. Удаляем весь каталог данных (БД, чеки, pin.json).
    PinService.create().resetAll();
    // 3. На экран создания нового пина, стек чист.
    Navigator.of(context).pushAndRemoveUntil(
      AuroraPageRoute<void>(builder: (_) => const PinScreen()),
      (_) => false,
    );
  }
}
