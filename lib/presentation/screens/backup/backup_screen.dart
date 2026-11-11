// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран бэкапа (финал, ТЗ «Бэкап данных»): создание ZIP-архива и
// восстановление из него.
//
// Паттерн — report_screen: директория вводится текстом (по умолчанию
// Documents, Permissions=UserDirs), каждая операция в try/catch,
// ошибка — текстом на экране (требование ТЗ про визуальные ошибки
// при создании, экспорте и импорте бэкапа).
//
// Восстановление затирает текущие данные — подтверждение вторым
// нажатием, как у сброса пина на главном экране (showDialog в
// AuroraApp недоступен).
//
// Имя файла бэкапа содержит штамп даты ГГГГ.ММ.ДД_ЧЧ.ММ. Двоеточие
// (формат чисел из ТЗ) в имени файла недопустимо на Linux — разделитель
// подчёркивание; сам файл .zip, данные внутри в UTF-8 JSON.

import 'dart:io';

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/backup_service.dart';
import '../../../state/providers.dart';

/// Создание и восстановление ZIP-бэкапа данных приложения.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  /// Дефолт — Documents текущего пользователя. Литералы абсолютных
  /// путей в коде запрещены: валидатор Авроры отвергает пакет
  /// (BadPackageContent, "Hardcoded path").
  static String get _defaultDirectory => '${Platform.environment['HOME'] ?? '.'}/Documents';

  late final TextEditingController _directoryController;
  late final TextEditingController _fileController;

  String? _status;
  bool _busy = false;
  bool _confirmRestore = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year.toString().padLeft(4, '0')}.${p2(now.month)}.${p2(now.day)}'
        '_${p2(now.hour)}.${p2(now.minute)}';
    _directoryController = TextEditingController(text: _defaultDirectory);
    // Один файл используется и для экспорта, и для импорта: после
    // создания бэкапа путь сразу готов к восстановлению.
    _fileController = TextEditingController(text: '$_defaultDirectory/tracker_1_backup_$stamp.zip');
  }

  @override
  void dispose() {
    _directoryController.dispose();
    _fileController.dispose();
    super.dispose();
  }

  /// Данные заменены — все списочные провайдеры перечитывают БД,
  /// иначе экраны покажут старое состояние.
  void _refreshAfterRestore() {
    ref.invalidate(categoriesProvider);
    ref.invalidate(tripsProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(filteredExpensesProvider);
    ref.invalidate(receiptExpenseIdsProvider);
  }

  /// Создание бэкапа: путь из полей, сборка ZIP, ошибки — текстом.
  Future<void> _create() async {
    if (_directoryController.text.trim().isEmpty) {
      setState(() => _status = 'Укажите директорию сохранения.');
      return;
    }
    final path = _fileController.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Укажите имя файла бэкапа.');
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await BackupService.create(ref.read(databaseProvider), path);
      if (!mounted) return;
      setState(() => _status = 'Бэкап создан: $path');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка создания бэкапа: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Восстановление: полная замена текущих данных данными из архива.
  /// Подтверждение вторым нажатием — операция необратима.
  Future<void> _restore() async {
    if (!_confirmRestore) {
      setState(() => _confirmRestore = true);
      return;
    }
    setState(() => _confirmRestore = false);

    final path = _fileController.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Укажите файл бэкапа для восстановления.');
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final counts = await BackupService.restore(ref.read(databaseProvider), path);
      if (!mounted) return;
      _refreshAfterRestore();
      setState(
        () => _status = 'Восстановлено: категории ${counts['categories']}, '
            'командировки ${counts['trips']}, траты ${counts['expenses']}, '
            'чеки ${counts['receipts']}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка восстановления: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AuroraTheme.of(context);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const AuroraAppBar(headerText: 'Бэкап данных'),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _directoryController,
                decoration: const InputDecoration(
                  labelText: 'Директория сохранения',
                  hintText: '~/Documents',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fileController,
                decoration: const InputDecoration(
                  labelText: 'Файл бэкапа (.zip) — сюда пишется и отсюда восстанавливается',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.archive),
                  label: const Text('Создать бэкап'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore),
                  label: Text(
                    _confirmRestore
                        ? 'Текущие данные будут заменены. Нажмите ещё раз'
                        : 'Восстановить из бэкапа',
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(_status!, style: theme.textThemeData.regularMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
