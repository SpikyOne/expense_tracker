// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.

/// Форматирование дат и времени по-русски, без зависимости от intl:
/// нам нужны лишь несколько устойчивых форматов, а ОС Аврора и так
/// тянет немало. Ключи monthKey/dayKey пригодятся для группировки
/// трат в списках и дашборде - они стабильно сортируются.
library;

const List<String> _monthsGenitive = <String>[
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const List<String> _monthsShort = <String>[
  'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

const List<String> _monthsNominative = <String>[
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

String _pad2(int value) => value.toString().padLeft(2, '0');

/// "25 октября 2026" - экран траты.
String formatDateFull(DateTime d) =>
    '${d.day} ${_monthsGenitive[d.month - 1]} ${d.year}';

/// "25 окт 2026" - плотные списки.
String formatDateShort(DateTime d) =>
    '${_pad2(d.day)} ${_monthsShort[d.month - 1]} ${d.year}';

/// "Октябрь 2026" - заголовок группы/месяца в дашборде.
String formatMonthHeader(DateTime d) =>
    '${_monthsNominative[d.month - 1]} ${d.year}';

/// "14:05".
String formatTime(DateTime d) => '${_pad2(d.hour)}:${_pad2(d.minute)}';

/// "25 октября 2026, 14:05".
String formatDateTimeFull(DateTime d) => '${formatDateFull(d)}, ${formatTime(d)}';

/// "2026-10" - ключ группировки трат по месяцам.
String monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}';

/// "2026-10-25" - ключ группировки по дням.
String dayKey(DateTime d) => '${monthKey(d)}-${_pad2(d.day)}';
