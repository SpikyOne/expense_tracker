// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Сервис пин-кода: хранение, проверка, сброс.
//
// Пин хранится как SHA-256 с солью в отдельном файле pin.json рядом
// с БД - НЕ в самой БД, чтобы проверка шла до любого обращения к данным.
// Сброс = удаление всего каталога данных приложения (БД, чеки, пин).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tracker_1/data/database/database_service.dart';

/// Защита приложения пин-кодом (финал, ТЗ).
class PinService {
  static const _pinFileName = 'pin.json';
  static const _salt = 'tracker_1_pin_2026_salt';

  final File _file;

  PinService._(this._file);

  /// Каталог данных приложения - тот же корень, что у expenses.db
  /// (см. DatabaseService.defaultDatabasePath).
  static String appDataDir() {
    final home = Platform.environment['HOME'] ?? '/';
    return '$home/.local/share/${DatabaseService.orgName}/${DatabaseService.appName}';
  }

  factory PinService.create() {
    final dir = Directory(appDataDir());
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return PinService._(File('${dir.path}/$_pinFileName'));
  }

  /// true, если пин уже задан.
  bool get isPinSet => (_read()['hash'] as String?)?.isNotEmpty ?? false;

  /// Число накопленных неверных вводов.
  int get failedAttempts => _read()['failed'] as int? ?? 0;

  /// Устанавливает пин. ArgumentError, если не проходит правила ТЗ.
  void setPin(String pin) {
    if (!isValidPin(pin)) throw ArgumentError('Недопустимый пин');
    _write({'hash': _hash(pin), 'failed': 0});
  }

  /// Проверяет пин: успех сбрасывает счётчик неудач, промах - растит.
  bool verify(String pin) {
    final data = _read();
    final expected = data['hash'] as String?;
    if (expected == null) return false;
    final ok = _hash(pin) == expected;
    _write({
      'hash': expected,
      'failed': ok ? 0 : (data['failed'] as int? ?? 0) + 1,
    });
    return ok;
  }

  /// Сброс: удаляет весь каталог данных приложения - ПОШТУЧНО, а не одним
  /// рекурсивным вызовом. Раньше dir.deleteSync(recursive: true) бросал
  /// исключение на первом же занятом файле (expenses.db при закрывающейся
  /// БД), из-за чего сброс обрывался молча, а экран пина оставался с
  /// заполненными кружками. Теперь: pin.json удаляется первым (сброс пина
  /// гарантирован), каждый следующий файл - в собственном try/catch,
  /// занятый файл не мешает удалить остальные. Возвращает false, если
  /// что-то удалить не удалось; исключений НЕ бросает.
  bool resetAll() {
    final dir = Directory(appDataDir());
    if (!dir.existsSync()) return true;
    // 1. Пин первым - он никогда не занят процессом.
    try {
      _file.deleteSync();
    } catch (_) {}
    // 2. Остальное по одному: занятый файл не прерывает цикл.
    var allDeleted = true;
    try {
      for (final entry in dir.listSync(followLinks: false)) {
        try {
          if (entry is Directory) {
            entry.deleteSync(recursive: true);
          } else {
            entry.deleteSync();
          }
        } catch (_) {
          allDeleted = false;
        }
      }
      // 3. Пустой каталог убираем; если не вышло - не страшно.
      try {
        if (dir.listSync().isEmpty) dir.deleteSync();
      } catch (_) {}
    } catch (_) {
      allDeleted = false;
    }
    return allDeleted;
  }

  // ---------- internals ----------

  String _hash(String pin) => sha256.convert(utf8.encode('$_salt$pin')).toString();

  void _write(Map<String, Object?> data) => _file.writeAsStringSync(jsonEncode(data));

  Map<String, dynamic> _read() {
    if (!_file.existsSync()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ---------- Правила ТЗ ----------

  /// 4 символа, только цифры, не 4 одинаковые, не подряд (1234/4321).
  static bool isValidPin(String pin) {
    if (pin.length != 4) return false;
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    if (pin.runes.toSet().length == 1) return false;
    if (_isSequential(pin, 1) || _isSequential(pin, -1)) return false;
    return true;
  }

  static bool _isSequential(String pin, int step) {
    final digits = pin.codeUnits.map((u) => u - 48).toList();
    for (var i = 1; i < digits.length; i++) {
      if (digits[i] - digits[i - 1] != step) return false;
    }
    return true;
  }
}
