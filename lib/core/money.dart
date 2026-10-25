// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.

/// Форматирование и разбор денежных сумм.
///
/// Во всей программе сумма хранится в копейках (int) - никаких double:
/// double даёт погрешности при сложении трат, а копейки остаются точными.
library;

/// Неразрывный пробел: разделяет разряды и примыкает к «₽»,
/// чтобы сумма не разрывалась при переносе строки в UI.
const String nbsp = '\u00A0';

const String _rubleSign = '₽';

final RegExp _moneyRegExp = RegExp(r'^[+-]?[0-9]+(\.[0-9]+)?$');

/// Форматирует сумму в копейках в строку вида «1 234,56 ₽».
///
/// Отрицательные суммы получают минус: «-1 234,56 ₽».
/// [showSign] добавляет явный «+» к неотрицательным: «+25,00 ₽».
String formatMoney(int kopecks, {bool showSign = false}) {
  final negative = kopecks < 0;
  final rubles = kopecks.abs() ~/ 100;
  final remainder = kopecks.abs() % 100;

  final digits = rubles.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final left = digits.length - 1 - i;
    if (left > 0 && left % 3 == 0) {
      buffer.write(nbsp);
    }
  }

  final sign = negative ? '-' : (showSign ? '+' : '');
  final kopecksPart = remainder.toString().padLeft(2, '0');
  return '$sign$buffer,$kopecksPart$nbsp$_rubleSign';
}

/// Разбирает пользовательский ввод суммы в копейки.
///
/// Принимает: «1234», «1234,56», «1 234.56», «-100,50», «0,5»,
/// а также готовый вывод formatMoney вроде «1 234,56 ₽».
/// Любые пробелы (включая неразрывные и табы) и знак ₽ игнорируются,
/// запятая и точка равнозначны как разделитель (только один).
/// Третья цифра после разделителя округляет: «10,005» → 1001 копейка.
/// Возвращает null, если ввод пустой или не похож на число.
int? parseMoneyInput(String raw) {
  // \s в RegExp Дарта работает как в JavaScript и заодно ловит
  // неразрывный пробел — значит, одна замена чистит всё «оформление».
  var text = raw.replaceAll(RegExp(r'\s'), '').replaceAll(_rubleSign, '');
  if (text.isEmpty) {
    return null;
  }
  text = text.replaceAll(',', '.');
  if (text.startsWith('−')) {
    text = '-${text.substring(1)}';
  }
  final match = _moneyRegExp.firstMatch(text);
  if (match == null) {
    return null;
  }

  final negative = text.startsWith('-');
  if (negative || text.startsWith('+')) {
    text = text.substring(1);
  }
  if (text.length > 15) {
    return null; // защита от переполнения int (максимум ~999 млрд ₽)
  }

  final dotIndex = text.indexOf('.');
  final rubles = dotIndex == -1
      ? int.parse(text)
      : int.parse(text.substring(0, dotIndex));
  var kopecks = rubles * 100;

  if (dotIndex != -1) {
    final fraction = text.substring(dotIndex + 1);
    if (fraction.length == 1) {
      kopecks += int.parse(fraction) * 10;
    } else {
      kopecks += int.parse(fraction.substring(0, 2));
      if (fraction.length > 2 && int.parse(fraction[2]) >= 5) {
        kopecks += 1;
      }
    }
  }

  return negative ? -kopecks : kopecks;
}
