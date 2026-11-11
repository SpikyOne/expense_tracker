// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Генератор MD-отчёта по фильтру (финал, задача "MD отчёт").
//
// Чистый Dart, без Flutter- и аврора-импортов: гоняется на хосте в
// tool/check_report.dart и reused экраном отчёта.
//
// Состав отчёта по ТЗ финала:
//   * название (настраиваемое — приходит с экрана);
//   * дата генерации;
//   * набор фильтров (период, категория, способ оплаты, поиск);
//   * список трат: сумма, комментарий, категория, получатель, дата,
//     наличие чека (по таблице receipts — id'шники из
//     ExpenseRepository.receiptExpenseIds);
//   * аналитика: сумма, средняя, медианная, самая большая трата,
//     самый частый и самый богатый получатель.
//
// Форматы ТЗ: даты ГГГГ.ММ.ДД:ЧЧ.ММ; валюта — 1 знак после запятой.
// Точные вычисления (сумма, медиана) ведутся в копейках (int),
// округление до 1 знака — только на выводе.

import '../models/models.dart';

/// Фильтр, по которому собран отчёт, — снимок ExpenseFilter экрана
/// трат. Описан здесь без ссылки на state/: домен не зависит от слоя
/// состояния, id категории уже раскрыт в название наверху.
class ReportFilterInfo {
  const ReportFilterInfo({
    this.fromDateIso,
    this.toDateIso,
    this.categoryName,
    this.paymentMethodTitle,
    this.searchText,
  });

  /// Левая граница периода включительно ('2026-10-01') или null.
  final String? fromDateIso;

  /// Правая граница периода включительно ('2026-10-31') или null.
  final String? toDateIso;

  /// Название категории или null — "все категории".
  final String? categoryName;

  /// Человеческое название способа оплаты или null — "все способы".
  final String? paymentMethodTitle;

  /// Подстрока поиска или null.
  final String? searchText;
}

/// Генератор текста MD-отчёта.
class ReportService {
  ReportService._();

  /// Собирает текст отчёта (строка UTF-8, готовая к записи в .md).
  ///
  /// [rows] — траты, уже отфильтрованные тем же фильтром
  /// (ExpenseDao.query умеет всё: период, категория, оплата, поиск).
  /// [receiptExpenseIds] — id трат с чеками: колонка "Чек" ставит
  /// "есть", если id траты попал в набор.
  /// [generatedAt] — дата генерации; по умолчанию "сейчас".
  static String buildMd({
    required String title,
    required ReportFilterInfo filterInfo,
    required List<ExpenseWithCategory> rows,
    required Set<int> receiptExpenseIds,
    DateTime? generatedAt,
  }) {
    final now = generatedAt ?? DateTime.now();
    final buffer = StringBuffer();
    buffer
      ..writeln('# $title')
      ..writeln()
      ..writeln('Дата генерации: ${formatStamp(now)}')
      ..writeln()
      ..writeln('## Фильтры')
      ..writeln()
      ..writeln(_filterSection(filterInfo))
      ..writeln()
      ..writeln('## Траты (${rows.length})')
      ..writeln();

    if (rows.isEmpty) {
      buffer
        ..writeln('Нет трат по заданным условиям.')
        ..writeln();
    } else {
      buffer
        ..writeln('| Сумма | Комментарий | Категория | Получатель | Дата | Чек |')
        ..writeln('|---:|---|---|---|---|---|');
      for (final row in rows) {
        final e = row.expense;
        buffer.writeln(
          '| ${formatRub(e.amountKopecks)} '
          '| ${_cell(e.comment)} '
          '| ${_cell(row.category.name)} '
          '| ${_cell(e.payee.isEmpty ? '—' : e.payee)} '
          '| ${formatStamp(e.date)} '
          '| ${receiptExpenseIds.contains(e.id) ? 'есть' : 'нет'} |',
        );
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## Аналитика')
      ..writeln()
      ..writeln(_analyticsSection(rows))
      ..writeln()
      ..writeln('Сформировано приложением "Трекер расходов" (tracker_1).');
    return buffer.toString();
  }

  // ---------- Разделы отчёта ----------

  static String _filterSection(ReportFilterInfo f) {
    final lines = <String>[];
    if (f.fromDateIso != null && f.toDateIso != null) {
      lines.add('- Период: с ${_stampFromIso(f.fromDateIso!)} по ${_stampFromIso(f.toDateIso!)}');
    } else if (f.fromDateIso != null) {
      lines.add('- Период: с ${_stampFromIso(f.fromDateIso!)}');
    } else if (f.toDateIso != null) {
      lines.add('- Период: по ${_stampFromIso(f.toDateIso!)}');
    }
    if (f.categoryName != null) lines.add('- Категория: ${f.categoryName}');
    if (f.paymentMethodTitle != null) lines.add('- Способ оплаты: ${f.paymentMethodTitle}');
    if (f.searchText != null) lines.add('- Поиск: "${f.searchText}"');
    if (lines.isEmpty) return '- Фильтры не заданы — включены все траты.';
    return lines.join('\n');
  }

  static String _analyticsSection(List<ExpenseWithCategory> rows) {
    if (rows.isEmpty) {
      return [
        '| Показатель | Значение |',
        '|---|---|',
        '| Сумма трат | — |',
        '| Средняя трата | — |',
        '| Медианная трата | — |',
        '| Самая большая трата | — |',
        '| Самый частый получатель | — |',
        '| Самый богатый получатель | — |',
      ].join('\n');
    }

    // Сумма/медиана считаются в копейках — целые числа, без погрешностей
    // double. Округление до 1 знака (формат ТЗ) — только на выводе.
    final amounts = [for (final r in rows) r.expense.amountKopecks]..sort();
    final sum = amounts.fold<int>(0, (acc, v) => acc + v);
    final average = sum / amounts.length;

    final middle = amounts.length ~/ 2;
    final median = amounts.length.isOdd ? amounts[middle].toDouble() : (amounts[middle - 1] + amounts[middle]) / 2;

    // Самая большая трата: максимум по сумме, при равенстве — первая
    // в выборке (детерминировано).
    final biggest = rows.reduce((a, b) => a.expense.amountKopecks >= b.expense.amountKopecks ? a : b);

    // Счётчики и суммы по непустым получателям. Перебор в порядке
    // строк выборки, максимум — первый достигнутый: результат
    // стабилен при одинаковых значениях.
    final counts = <String, int>{};
    final sums = <String, int>{};
    for (final r in rows) {
      final payee = r.expense.payee;
      if (payee.isEmpty) continue;
      counts[payee] = (counts[payee] ?? 0) + 1;
      sums[payee] = (sums[payee] ?? 0) + r.expense.amountKopecks;
    }
    String? topPayee;
    int? topCount;
    counts.forEach((payee, count) {
      if (topCount == null || count > topCount!) {
        topCount = count;
        topPayee = payee;
      }
    });
    String? richPayee;
    int? richSum;
    sums.forEach((payee, sumByPayee) {
      if (richSum == null || sumByPayee > richSum!) {
        richSum = sumByPayee;
        richPayee = payee;
      }
    });

    return [
      '| Показатель | Значение |',
      '|---|---|',
      '| Сумма трат | ${formatRub(sum)} |',
      '| Средняя трата | ${formatRub(average)} |',
      '| Медианная трата | ${formatRub(median)} |',
      '| Самая большая трата | ${_biggestLabel(biggest)} |',
      '| Самый частый получатель | ${topPayee == null ? '—' : '$topPayee — $topCount ${_trataWord(topCount!)}'} |',
      '| Самый богатый получатель | ${richPayee == null ? '—' : '$richPayee — ${formatRub(richSum!)}'} |',
    ].join('\n');
  }

  /// "500,0 ₽ — Пятёрочка (2026.10.20:00.00)"; без получателя —
  /// название категории.
  static String _biggestLabel(ExpenseWithCategory row) {
    final e = row.expense;
    final who = e.payee.isEmpty ? row.category.name : e.payee;
    return '${formatRub(e.amountKopecks)} — $who (${formatStamp(e.date)})';
  }

  // ---------- Форматы ТЗ ----------

  /// ГГГГ.ММ.ДД:ЧЧ.ММ — формат дат по ТЗ. У трат время не хранится
  /// (Expense.dateIso — только дата), подставляется 00.00.
  static String formatStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '.${_p2(d.month)}'
      '.${_p2(d.day)}'
      ':${_p2(d.hour)}'
      '.${_p2(d.minute)}';

  /// '2026-10-24' -> '2026.10.24:00.00'.
  static String _stampFromIso(String dateIso) => formatStamp(DateTime.parse(dateIso));

  /// Валюта ТЗ: 1 знак после запятой. 12000 к. -> "120,0 ₽".
  /// Принимает num: средняя/медианная трата дробная в копейках;
  /// округление до 1 знака — на выводе.
  static String formatRub(num kopecks) => '${(kopecks / 100).toStringAsFixed(1).replaceAll('.', ',')} ₽';

  // ---------- Утилиты ----------

  /// Ячейка MD-таблицы: перенос строки ломает таблицу, "|" экранируем,
  /// пустое значение — тире.
  static String _cell(String raw) {
    final text = raw.replaceAll('\n', ' ').replaceAll('|', '\\|');
    return text.isEmpty ? '—' : text;
  }

  /// 1 трата / 2 траты / 5 трат.
  static String _trataWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'трата';
    if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return 'траты';
    return 'трат';
  }

  static String _p2(int v) => v.toString().padLeft(2, '0');
}
