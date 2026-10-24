// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Стартовая точка приложения «Трекер расходов» для ОС Аврора.
//
// Это МИНИМАЛЬНЫЙ каркас без внешних зависимостей: он гарантированно
// собирается сразу после flutter-aurora create.
// Этот файл заменяется версией на AuroraApp +
// aurora_controls, а по слоям lib/ раскладывается логика проекта:
//
//   lib/presentation/  — экраны и виджеты (Aurora Controls)
//   lib/state/         — Riverpod-провайдеры и нотифаеры
//   lib/domain/        — модели, интерфейсы, сервисы (чистый Dart)
//   lib/data/          — Drift-база, DAO, репозитории, CSV-слой
//   lib/core/          — утилиты: деньги, даты, форматеры

import 'package:flutter/material.dart';

void main() {
  runApp(const ExpenseTrackerApp());
}

/// Корневой виджет приложения.
///
/// На следующем этапе MaterialApp заменяется на AuroraApp из пакета
/// aurora_controls — это даст нативный вид и поддержку атмосфер ОС Аврора.
class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Трекер расходов',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3681A6))),
      home: const HomePage(),
    );
  }
}

/// Временный главный экран: подтверждает, что сборка и запуск работают.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Трекер расходов')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Каркас проекта развёрнут.\n'
            'Дальше — этап 1 дорожной карты:\n'
            'git-репозиторий, AuroraApp, навигация.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
      ),
    );
  }
}
