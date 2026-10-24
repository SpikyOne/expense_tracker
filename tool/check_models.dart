// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка доменных моделей чистым Dart, без flutter_test.
// Почему не flutter test: хост-раннер тестов у форка Flutter Авроры
// сломан (не компилирует даже dart:core) — ограничение SDK, не проекта.
// Запуск: dart-aurora run tool/check_models.dart

// ignore_for_file: avoid_print

import 'dart:io' show exit;

import 'package:expense_tracker/domain/models/models.dart';

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

void main() {
  // Category: roundtrip в/из SQLite-строки
  const c = Category(id: 3, name: 'Транспорт', isDefault: true);
  check('Category roundtrip', Category.fromMap(c.toMap()), c);

  const c2 = Category(name: 'Моя категория');
  check('Category без id не пишет id в map', c2.toMap().containsKey('id'), false);

  // Expense: roundtrip
  const e = Expense(
    id: 7,
    amountKopecks: 19999,
    dateIso: '2026-10-24',
    categoryId: 1,
    payee: 'Пятёрочка',
    paymentMethod: PaymentMethod.card,
    comment: 'Продукты на неделю',
  );
  check('Expense roundtrip', Expense.fromMap(e.toMap()), e);

  // Деньги: рубли -> копейки без потери копеек
  check('rublesToKopecks(19.99)', Expense.rublesToKopecks(19.99), 1999);
  check('rublesToKopecks(0.1)', Expense.rublesToKopecks(0.1), 10);
  check('rublesToKopecks(1234.56)', Expense.rublesToKopecks(1234.56), 123456);
  check(
    'amountRubles для отображения',
    const Expense(amountKopecks: 19999, dateIso: '2026-10-24', categoryId: 1).amountRubles,
    199.99,
  );

  // Способы оплаты: ключи БД и русские названия из ТЗ
  check('fromKey(card)', PaymentMethod.fromKey('card'), PaymentMethod.card);
  check('fromKey(qr_code)', PaymentMethod.fromKey('qr_code'), PaymentMethod.qrCode);
  check('fromKey(неизвестно)', PaymentMethod.fromKey('неизвестно'), PaymentMethod.other);
  check('fromTitle(наличные)', PaymentMethod.fromTitle('наличные'), PaymentMethod.cash);
  check('fromTitle(  QR-код  )', PaymentMethod.fromTitle('  QR-код  '), PaymentMethod.qrCode);

  // Поиск: нормализация search_text (схема v2)
  check(
    'buildSearchText: регистр, ё, пунктуация',
    Expense.buildSearchText('ООО «Ромашка»', 'Кофе с Ёлкой!'),
    'ооо ромашка кофе с елкой',
  );
  check('buildSearchText: пустые строки', Expense.buildSearchText('', ''), '');
  check(
    'buildSearchText: запрос нормализуется той же функцией',
    Expense.buildSearchText('ЁЛКА', ''),
    'елка',
  );

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
