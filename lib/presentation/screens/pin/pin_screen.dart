// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран пин-кода: один экран на два режима - создание (первый запуск
// или после сброса) и ввод. Работает без MaterialLocalizations
// (AuroraApp построен на WidgetsApp): только инлайн-тексты и AuroraPageRoute.

import 'package:aurora_controls/aurora_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pin_service.dart';
import '../../../main.dart' show HomePage;
import '../../../state/providers.dart' show databaseProvider;

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final PinService _pin = PinService.create();

  String _entered = '';
  String? _firstEntered; // первый ввод в режиме создания
  String? _error;

  /// Режим - геттер: после сброса isPinSet == false, и экран сам
  /// перестраивается в "Создайте пин-код".
  bool get _isCreateMode => !_pin.isPinSet;

  // ---------- Ввод ----------

  void _onDigit(String d) {
    if (_entered.length >= 4) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == 4) _isCreateMode ? _handleCreate() : _handleEnter();
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  // ---------- Режим создания ----------

  void _handleCreate() {
    if (_firstEntered == null) {
      if (!PinService.isValidPin(_entered)) {
        setState(() {
          _entered = '';
          _error = 'Пин слишком простой: нельзя 4 одинаковые цифры\nили подряд (1234 / 4321).';
        });
        return;
      }
      setState(() {
        _firstEntered = _entered;
        _entered = '';
        _error = 'Повторите пин для подтверждения';
      });
      return;
    }

    if (_entered != _firstEntered) {
      setState(() {
        _entered = '';
        _firstEntered = null;
        _error = 'Пины не совпадают. Начните заново';
      });
      return;
    }

    _pin.setPin(_entered);
    _goHome();
  }

  // ---------- Режим ввода ----------

  void _handleEnter() {
    if (_pin.verify(_entered)) {
      _goHome();
      return;
    }
    final failed = _pin.failedAttempts;
    if (failed >= 3) {
      _wipeAll();
      return;
    }
    setState(() {
      _entered = '';
      _error = 'Неверный пин. Осталось попыток: ${3 - failed}';
    });
  }

  /// ТЗ: 3 неверных ввода сбрасывают пин И данные пользователя.
  void _wipeAll() {
    // 1. Закрываем соединение с БД: invalidate провайдера запускает
    //    ref.onDispose -> db.close(). Иначе файл expenses.db на Linux
    //    удержан дескриптором и не удалится.
    ref.invalidate(databaseProvider);
    // 2. Удаляем весь каталог данных: БД, чеки, pin.json.
    PinService.create().resetAll();
    // 3. Режим-геттер сам перестроит экран в "создание".
    setState(() {
      _entered = '';
      _firstEntered = null;
      _error = 'Данные сброшены (3 неверных ввода). Создайте новый пин.';
    });
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      AuroraPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final title = _isCreateMode
        ? (_firstEntered == null ? 'Создайте пин-код' : 'Подтвердите пин-код')
        : 'Введите пин-код';

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const Spacer(),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => _dot(i < _entered.length)),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFE05555), fontSize: 14),
                ),
              ),
            const Spacer(),
            _keypad(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _dot(bool filled) {
    final color = const Color(0xFF3EB8F0); // акцент Авроры
    return Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
    );
  }

  Widget _keypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) _key(d, () => _onDigit(d))],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 72),
              _key('0', () => _onDigit('0')),
              _keyIcon(Icons.backspace_outlined, _onBackspace),
            ],
          ),
        ),
      ],
    );
  }

  Widget _key(String digit, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 64,
        height: 64,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(fontSize: 24),
          ),
          child: Text(digit),
        ),
      ),
    );
  }

  Widget _keyIcon(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 64,
        height: 64,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}
