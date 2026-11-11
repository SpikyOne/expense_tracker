// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.

// Хост-проверка генератора MD-отчёта: состав по ТЗ, форматы, аналитика.
// Запуск: dart-aurora run tool/check_report.dart

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:tracker_1/data/dao/expense_dao.dart';
import 'package:tracker_1/data/database/database_service.dart';
import 'package:tracker_1/domain/models/models.dart';
import 'package:tracker_1/domain/services/report_service.dart';

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
  final db = DatabaseService.inMemory();
  final expenseDao = ExpenseDao(db);

  int categoryId(String name) => db.rawSelect('SELECT id FROM categories WHERE name = ?;', [name]).first['id'] as int;
  final cafeId = categoryId('Кафе');
  final productsId = categoryId('Продукты');
  final transportId = categoryId('Транспорт');

  print('--- данные: октябрь 2026 + сентябрьская трата вне периода ---');
  final eCoffee = expenseDao.insert(
    Expense(
      amountKopecks: 19999,
      dateIso: '2026-10-24',
      categoryId: cafeId,
      payee: 'Кофейня Утро',
      paymentMethod: PaymentMethod.card,
      comment: 'кофе с круассаном',
    ),
  );
  expenseDao.insert(
    Expense(
      amountKopecks: 50000,
      dateIso: '2026-10-20',
      categoryId: productsId,
      payee: 'Пятёрочка',
      paymentMethod: PaymentMethod.card,
      comment: 'продукты на неделю',
    ),
  );
  expenseDao.insert(
    Expense(
      amountKopecks: 10050,
      dateIso: '2026-10-20',
      categoryId: productsId,
      payee: 'Пятёрочка',
      paymentMethod: PaymentMethod.card,
    ),
  );
  expenseDao.insert(
    Expense(
      amountKopecks: 250000,
      dateIso: '2026-09-15',
      categoryId: categoryId('Одежда'),
      payee: 'Одежда+оутлет',
      paymentMethod: PaymentMethod.other,
      comment: 'куртка, вне отчётного периода',
    ),
  );
  expenseDao.insert(
    Expense(
      amountKopecks: 3000,
      dateIso: '2026-10-25',
      categoryId: transportId,
      paymentMethod: PaymentMethod.cash,
      comment: 'метро, без получателя',
    ),
  );
  expenseDao.insert(
    Expense(
      amountKopecks: 7000,
      dateIso: '2026-10-26',
      categoryId: cafeId,
      payee: 'Кофейня Утро',
      paymentMethod: PaymentMethod.qrCode,
      comment: 'бизнес-ланч',
    ),
  );

  // Чек есть только у кофейной траты.
  db.rawExecute('INSERT INTO receipts (expense_id, file_path, created_at) VALUES (?, ?, ?);', [
    eCoffee,
    'receipts/2026/10/check.jpg',
    '2026-10-24T10:00:00',
  ]);

  final rows = expenseDao.query(fromDateIso: '2026-10-01', toDateIso: '2026-10-31');
  final receiptIds = db
      .rawSelect('SELECT DISTINCT expense_id FROM receipts;')
      .map((row) => row['expense_id'] as int)
      .toSet();

  final md = ReportService.buildMd(
    title: 'Отчёт за октябрь',
    filterInfo: const ReportFilterInfo(fromDateIso: '2026-10-01', toDateIso: '2026-10-31'),
    rows: rows,
    receiptExpenseIds: receiptIds,
    generatedAt: DateTime(2026, 11, 11, 14, 30),
  );

  print('--- MD-отчёт: состав по ТЗ ---');
  check('выборка: 5 трат октября, сентябрь отсечён', rows.length, 5);
  check('название отчёта', md.contains('# Отчёт за октябрь'), true);
  check('дата генерации ГГГГ.ММ.ДД:ЧЧ.ММ', md.contains('Дата генерации: 2026.11.11:14.30'), true);
  check('фильтр периода в формате ТЗ', md.contains('с 2026.10.01:00.00 по 2026.10.31:00.00'), true);
  check('заголовок списка с количеством', md.contains('## Траты (5)'), true);
  check('колонки таблицы по ТЗ', md.contains('| Сумма | Комментарий | Категория | Получатель | Дата | Чек |'), true);
  check('дата траты в формате ТЗ', md.contains('2026.10.24:00.00'), true);
  check('чек отмечен «есть»', md.contains('| есть |'), true);
  check('чек отмечен «нет» у остальных', md.contains('| нет |'), true);
  check('сентябрьская трата не попала', md.contains('Одежда+оутлет'), false);
  check('пустые значения — тире', md.contains('| — | Продукты | Пятёрочка'), true);

  print('--- аналитика ---');
  // Сумма 19999+50000+10050+3000+7000 = 90049 к. -> 900,5 ₽;
  // средняя 18009.8 к. -> 180,1 ₽; медиана 10050 к. -> 100,5 ₽;
  // максимум 50000 к. -> 500,0 ₽; частый — Кофейня Утро (2);
  // богатый — Пятёрочка (60050 к. -> 600,5 ₽).
  check('сумма трат', md.contains('| Сумма трат | 900,5 ₽ |'), true);
  check('средняя трата', md.contains('| Средняя трата | 180,1 ₽ |'), true);
  check('медианная трата', md.contains('| Медианная трата | 100,5 ₽ |'), true);
  check('самая большая трата', md.contains('| Самая большая трата | 500,0 ₽ — Пятёрочка (2026.10.20:00.00) |'), true);
  check('самый частый получатель', md.contains('| Самый частый получатель | Кофейня Утро — 2 траты |'), true);
  check('самый богатый получатель', md.contains('| Самый богатый получатель | Пятёрочка — 600,5 ₽ |'), true);

  print('--- отчёт без трат и без фильтров ---');
  final emptyMd = ReportService.buildMd(
    title: 'Пустой отчёт',
    filterInfo: const ReportFilterInfo(),
    rows: const [],
    receiptExpenseIds: const {},
  );
  check('фильтры не заданы — пометка', emptyMd.contains('Фильтры не заданы'), true);
  check('ноль трат', emptyMd.contains('## Траты (0)'), true);
  check('аналитика с прочерками', emptyMd.contains('| Сумма трат | — |'), true);

  print('--- форматы ТЗ ---');
  check('валюта: 1 знак после запятой', ReportService.formatRub(12000), '120,0 ₽');
  check('метка времени', ReportService.formatStamp(DateTime(2026, 11, 11, 14, 30)), '2026.11.11:14.30');

  print('--- пример отчёта за октябрь ---');
  print(md);

  print(failed == 0 ? 'ВСЁ ОК: ReportService соответствует ТЗ.' : 'ЕСТЬ ОШИБКИ: провалов $failed.');
  exit(failed == 0 ? 0 : 1);
}
