// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Сервис бэкапа данных (финал, ТЗ «Бэкап данных», 3 ед.).
//
// Формат архива — ZIP, данные в читаемом виде (JSON с отступами):
//
//   meta.json        — приложение, организация, версия схемы и формата, дата
//   categories.json  — категории (с исходными id)
//   trips.json       — командировки
//   expenses.json    — траты (с исходными id — связи category_id/trip_id живут)
//   receipts.json    — чеки (с исходными id и expense_id)
//   photos/<file_path> — файлы фотографий чеков (file_path из таблицы receipts)
//
// Дамп самой БД (expenses.db) в архив не кладём: ТЗ требует «читаемый
// формат», бинарный файл SQLite ему не соответствует.
//
// Корень данных берётся из каталога, где лежит файл БД (db.path):
// фото чеков по проекту лежат рядом с БД, в БД — относительные пути.
// Поэтому сервису не нужен отдельный конфиг, и хост-проверка поднимает
// бэкап во временной папке без каких-либо правок.
//
// Пин-код в бэкап не включается: это защита приложения, а не данные
// пользователя (сброс пина с очисткой данных — отдельная функция ТЗ,
// восстановление старого пина противоречило бы её смыслу).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:tracker_1/data/database/database_service.dart';

/// Экспорт и импорт данных приложения в ZIP-бэкап.
class BackupService {
  /// Версия формата бэкапа. При несовместимом изменении формата
  /// инкрементировать: бэкапы «из будущего» при импорте отвергаются
  /// с понятным текстом, а не молча портят данные.
  static const int formatVersion = 1;

  /// Таблицы в порядке зависимостей: сначала те, на которые ссылаются
  /// внешние ключи (expenses -> categories/trips, receipts -> expenses).
  static const List<String> _tables = ['categories', 'trips', 'expenses', 'receipts'];

  /// Создаёт ZIP-бэкап в [zipPath]. Ошибки (недоступный путь, занятый
  /// файл) не глушатся — экран показывает их текстом (требование ТЗ
  /// про визуальные ошибки при создании/экспорте).
  static Future<void> create(DatabaseService db, String zipPath) async {
    if (db.path == ':memory:') {
      throw StateError('Бэкап in-memory БД не поддерживается');
    }

    final encoder = const JsonEncoder.withIndent('  ');
    final archive = Archive();

    // Служебный файл первым — по нему импорт узнаёт «свой» архив.
    final metaBytes = utf8.encode(
      encoder.convert({
        'app': DatabaseService.appName,
        'org': DatabaseService.orgName,
        'format': formatVersion,
        'schema_version': DatabaseService.schemaVersion,
        'created': DateTime.now().toIso8601String(),
      }),
    );
    archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

    // Данные: SELECT * каждой таблицы. Значения в схеме — int/String/null,
    // это JSON-безопасно; исходные id сохраняют все связи при импорте.
    for (final table in _tables) {
      final bytes = utf8.encode(encoder.convert(db.rawSelect('SELECT * FROM $table;')));
      archive.addFile(ArchiveFile('$table.json', bytes.length, bytes));
    }

    // Фотографии чеков: каждый file_path -> photos/<file_path>.
    // Запись без файла не роняет бэкап: строка останется, путь сохранён.
    final dataDir = File(db.path).parent.path;
    for (final row in db.rawSelect('SELECT file_path FROM receipts;')) {
      final rel = row['file_path'] as String;
      final file = File('$dataDir/$rel');
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile('photos/$rel', bytes.length, bytes));
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('Не удалось упаковать архив бэкапа');
    }
    final out = File(zipPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(zipBytes, flush: true);
  }

  /// Восстановление: полная замена данных приложения данными из архива.
  /// Возвращает число записей по таблицам — для статуса на экране.
  ///
  /// Ошибки — исключения с человекочитаемым текстом (экран показывает
  /// их как есть — визуальные ошибки ТЗ):
  ///   * файла нет / это не ZIP / нет meta.json — «не бэкап приложения»;
  ///   * бэкап другого приложения или из более новой версии — не импортируем;
  ///   * сбой внутри транзакции — БД откатывается к прежнему состоянию.
  static Future<Map<String, int>> restore(DatabaseService db, String zipPath) async {
    final file = File(zipPath);
    if (!file.existsSync()) {
      throw StateError('Файл бэкапа не найден: $zipPath');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    } catch (_) {
      throw const FormatException('Файл не читается как ZIP-архив — архив повреждён?');
    }

    // 1. meta.json: свой ли архив и известного ли формата.
    final metaFile = archive.findFile('meta.json');
    if (metaFile == null) {
      throw const FormatException('В архиве нет meta.json — это не бэкап этого приложения');
    }
    final meta = jsonDecode(utf8.decode(metaFile.content as List<int>));
    if (meta is! Map || meta['app'] != DatabaseService.appName) {
      throw FormatException('Бэкап другого приложения: ${meta['app']}');
    }
    final format = meta['format'];
    if (format is int && format > formatVersion) {
      throw FormatException('Бэкап создан более новой версией формата ($format > $formatVersion)');
    }
    final schema = meta['schema_version'];
    if (schema is int && schema > DatabaseService.schemaVersion) {
      throw FormatException('Бэкап из более новой версии приложения (схема $schema)');
    }

    // 2. Таблицы из архива.
    final data = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final f = archive.findFile('$table.json');
      if (f == null) {
        throw FormatException('В архиве нет $table.json — архив неполный');
      }
      final decoded = jsonDecode(utf8.decode(f.content as List<int>));
      if (decoded is! List) {
        throw FormatException('$table.json — ожидается массив записей');
      }
      data[table] = [
        for (final row in decoded)
          row is Map
              ? Map<String, Object?>.from(row)
              : throw FormatException('$table.json: запись не объект'),
      ];
    }

    // 3. Загрузка в БД одной транзакцией: либо всё, либо ничего.
    //    foreign_keys выключаем ДО BEGIN (внутри транзакции pragma
    //    игнорируется): порядок строк в JSON не обязан соблюдать FK.
    if (db.path == ':memory:') {
      throw StateError('Восстановление in-memory БД не поддерживается');
    }
    db.rawExecute('PRAGMA foreign_keys = OFF;');
    try {
      db.rawExecute('BEGIN;');
      // Удаляем в обратном порядке — сначала ссылающиеся таблицы.
      for (final table in _tables.reversed) {
        db.rawExecute('DELETE FROM $table;');
      }
      for (final table in _tables) {
        for (final row in data[table]!) {
          final cols = row.keys.toList();
          final marks = List.filled(cols.length, '?').join(', ');
          db.rawExecute('INSERT INTO $table (${cols.join(', ')}) VALUES ($marks);', [
            for (final col in cols) row[col],
          ]);
        }
      }
      db.rawExecute('COMMIT;');
    } catch (_) {
      try {
        db.rawExecute('ROLLBACK;');
      } catch (_) {}
      rethrow;
    } finally {
      db.rawExecute('PRAGMA foreign_keys = ON;');
    }

    // 4. Фотографии: photos/<rel> -> <каталог данных>/<rel>.
    //    Защита от путей вида '../../...' в чужом архиве.
    final dataDir = File(db.path).parent.path;
    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.startsWith('photos/')) continue;
      final rel = entry.name.substring('photos/'.length);
      if (rel.isEmpty || rel.startsWith('/') || rel.contains('..')) {
        throw FormatException('Недопустимый путь фото в архиве: ${entry.name}');
      }
      final out = File('$dataDir/$rel');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>, flush: true);
    }

    return {for (final table in _tables) table: data[table]!.length};
  }
}
