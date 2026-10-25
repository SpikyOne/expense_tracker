// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.

// Хост-проверки core: деньги и даты.
// Запуск: dart-aurora run tool/check_core.dart

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/core/formatters.dart';
import 'package:expense_tracker/core/money.dart';

var failed = 0;

void check(String name, Object? actual, Object? expected) {
  final ok = actual == expected;
  print('${ok ? 'OK  ' : 'FAIL'} $name');
  if (!ok) {
    print('     ожидалось: $expected');
    print('     получено:  $actual');
    failed++;
  }
}

void main() {
  print('--- money: форматирование ---');
  check('formatMoney: обычная сумма', formatMoney(123456), '1\u00A0234,56\u00A0₽');
  check('formatMoney: ноль', formatMoney(0), '0,00\u00A0₽');
  check('formatMoney: пять копеек', formatMoney(5), '0,05\u00A0₽');
  check('formatMoney: отрицательная', formatMoney(-500), '-5,00\u00A0₽');
  check('formatMoney: миллион', formatMoney(100000000), '1\u00A0000\u00A0000,00\u00A0₽');
  check('formatMoney: showSign', formatMoney(2500, showSign: true), '+25,00\u00A0₽');

  print('--- money: разбор ввода ---');
  check('parseMoneyInput: целые рубли', parseMoneyInput('1234'), 123400);
  check('parseMoneyInput: запятая', parseMoneyInput('1234,56'), 123456);
  check('parseMoneyInput: точка', parseMoneyInput('1234.56'), 123456);
  check('parseMoneyInput: пробелы-разряды', parseMoneyInput('1 234,56'), 123456);
  check('parseMoneyInput: одна цифра после запятой', parseMoneyInput('0,5'), 50);
  check('parseMoneyInput: округление вниз', parseMoneyInput('10,004'), 1000);
  check('parseMoneyInput: округление вверх', parseMoneyInput('10,005'), 1001);
  check('parseMoneyInput: отрицательная', parseMoneyInput('-100,50'), -10050);
  check('parseMoneyInput: пустая строка', parseMoneyInput(''), null);
  check('parseMoneyInput: мусор', parseMoneyInput('abc'), null);
  check('parseMoneyInput: два разделителя', parseMoneyInput('1,234.56'), null);

  print('--- money: круговой обмен ---');
  for (final raw in const ['0,01', '19,99', '12345,67', '999999,99']) {
    final kopecks = parseMoneyInput(raw) ?? 0;
    check(
      'roundtrip: $raw → ${formatMoney(kopecks)}',
      parseMoneyInput(formatMoney(kopecks)),
      kopecks,
    );
  }

  print('--- dates ---');
  final d = DateTime(2026, 10, 25, 14, 5);
  check('formatDateFull', formatDateFull(d), '25 октября 2026');
  check('formatDateShort', formatDateShort(d), '25 окт 2026');
  check('formatMonthHeader', formatMonthHeader(d), 'Октябрь 2026');
  check('formatTime', formatTime(d), '14:05');
  check('formatDateTimeFull', formatDateTimeFull(d), '25 октября 2026, 14:05');
  check('monthKey', monthKey(d), '2026-10');
  check('dayKey', dayKey(d), '2026-10-25');
  check('formatDateFull: однозначный день', formatDateFull(DateTime(2026, 1, 5)), '5 января 2026');
  check('monthKey: паддинг месяца', monthKey(DateTime(2026, 3, 1)), '2026-03');

  if (failed > 0) {
    print('ЕСТЬ ПРОВАЛЫ: $failed');
    exit(1);
  }
  print('ВСЁ ОК');
}
