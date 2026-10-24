// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка DatabaseService на хосте, без эмулятора (flutter test в форке
// не работает). Запуск: dart-aurora run tool/check_database.dart

// Скрипты tool/ осознанно печатают отчёт в консоль — отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/data/database/database_service.dart';
import 'package:sqlite3/sqlite3.dart';

int _passed = 0;
int _failed = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    _passed++;
    print('OK   $name');
  } else {
    _failed++;
    print('FAIL $name — ожидалось: $expected, получено: $actual');
  }
}

/// Проверка, что вставку отклонили по ожидаемой причине: текст ошибки
/// SQLite содержит [needle]. Иначе тест мог пройти «не за ту» ошибку
/// (например, NOT NULL вместо FOREIGN KEY).
void checkContains(String name, String? actualError, String needle) {
  if (actualError != null && actualError.contains(needle)) {
    _passed++;
    print('OK   $name');
  } else {
    _failed++;
    print(
      'FAIL $name — в ошибке ожидалось "$needle", '
      'получено: ${actualError ?? 'вставка не была отклонена'}',
    );
  }
}

void main() {
  // In-memory: схема и сид
  final db = DatabaseService.inMemory();
  check('версия схемы = 1', db.currentSchemaVersion, 1);

  final cats = db.getCategories();
  check('сид: 8 категорий из ТЗ', cats.length, 8);
  check('все категории стандартные', cats.every((c) => c.isDefault), true);

  // Сортировку сверяем по всему списку, а не только по первому элементу.
  // Ожидание вычисляем, а не хардкодим: compareTo в Dart по кодовым единицам
  // совпадает с BINARY-порядком SQLite для заглавной кириллицы без "ё".
  final expectedNames = [...DatabaseService.defaultCategoryNames]..sort();
  final actualNames = cats.map((c) => c.name).toList();
  check('сортировка: стандартные по алфавиту', actualNames.join('|'), expectedNames.join('|'));

  // FK: все прочие поля валидны (payment_method задан явно), единственная
  // возможная причина отклонения — несуществующий category_id.
  String? fkError;
  try {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payment_method) '
      'VALUES (?, ?, ?, ?);',
      [19999, '2026-10-24', 999, 'card'],
    );
  } on SqliteException catch (e) {
    fkError = e.message;
  }
  checkContains('FK: трата с несуществующей категорией отклонена', fkError, 'FOREIGN KEY');

  // CHECK: неизвестный способ оплаты — сумма и категория заведомо валидны.
  String? methodError;
  try {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payment_method) '
      'VALUES (?, ?, (SELECT MIN(id) FROM categories), ?);',
      [100, '2026-10-24', 'бартер'],
    );
  } on SqliteException catch (e) {
    methodError = e.message;
  }
  checkContains('CHECK: неизвестный способ оплаты отклонён', methodError, 'CHECK');

  // CHECK: отрицательная сумма — payment_method задан явно, чтобы не поймать
  // NOT NULL вместо CHECK.
  String? amountError;
  try {
    db.rawExecute(
      'INSERT INTO expenses (amount_kopecks, date_iso, category_id, payment_method) '
      'VALUES (?, ?, (SELECT MIN(id) FROM categories), ?);',
      [-1, '2026-10-24', 'card'],
    );
  } on SqliteException catch (e) {
    amountError = e.message;
  }
  checkContains('CHECK: отрицательная сумма отклонена', amountError, 'CHECK');
  db.close();

  // Реальный файл: каталог создаётся, повторное открытие не дублирует сид
  final tmpPath =
      '${Directory.systemTemp.path}/expense_tracker_check_${DateTime.now().millisecondsSinceEpoch}.db';
  var fileDb = DatabaseService.open(tmpPath);
  fileDb.close();
  fileDb = DatabaseService.open(tmpPath);
  check('повторное открытие: сид не дублируется', fileDb.getCategories().length, 8);
  check('повторное открытие: схема v1', fileDb.currentSchemaVersion, 1);
  fileDb.close();
  File(tmpPath).deleteSync();

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
