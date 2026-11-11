// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Экран пин-кода: один экран на два режима - создание (первый запуск
// или после сброса) и ввод. Работает без MaterialLocalizations
// (AuroraApp построен на WidgetsApp): только инлайн-тексты и AuroraPageRoute.
//
// Финал (фикс багов): сброс (3 неверных ввода / кнопка на главном экране)
// теперь (1) уведомляет через SnackBar (корневой ScaffoldMessenger уже
// есть в main), (2) показывает промежуточный экран "Пин и данные
// удалены", и только по кнопке - создание нового пина; (3) кружки
// при этом пустые. Причина старого бага - resetAll падал молча на
// занятом файле БД и обрывал _wipeAll до setState (см. PinService).

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

  /// Промежуточное состояние после сброса: экран "данные удалены".
  bool _wiped = false;

  /// 'locked' - 3 неверных ввода; 'manual' - кнопка на главном экране.
  String _wipeReason = 'manual';

  /// Режим - геттер: после сброса isPinSet == false, и экран сам
  /// перестраивается в "Создайте пин-код".
  bool get _isCreateMode => !_pin.isPinSet;

  // ---------- Ввод ----------

  void _onDigit(String d) {
    if (_wiped) return; // на промежуточном экране ввод заблокирован
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
      _wipeAll('locked');
      return;
    }
    setState(() {
      _entered = '';
      _error = 'Неверный пин. Осталось попыток: ${3 - failed}';
    });
  }

  /// ТЗ: 3 неверных ввода сбрасывают пин И данные пользователя.
  /// Фикс: уведомление (SnackBar) + промежуточный экран вместо
  /// мгновенного прыжка в "Создайте пин-код" с заполненными кружками.
  Future<void> _wipeAll(String reason) async {
    // 1. Закрываем соединение с БД: invalidate провайдера запускает
    //    ref.onDispose -> db.close(). Даём close долететь до файловой
    //    системы, иначе expenses.db останется "занят" для удаления.
    ref.invalidate(databaseProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // 2. Удаляем весь каталог данных: БД, чеки, pin.json.
    //    resetAll поштучный и не бросает исключений (см. PinService).
    var allDeleted = true;
    try {
      allDeleted = _pin.resetAll();
    } catch (_) {
      allDeleted = false;
    }
    if (!mounted) return;

    // 3. Уведомление - чего не было раньше.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          allDeleted
              ? (reason == 'locked'
                    ? 'Слишком много неверных попыток: пин и данные удалены'
                    : 'Пин и данные сброшены')
              : 'Пин сброшен, но часть файлов удалить не удалось (файл был занят)',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    // 4. Промежуточный экран: НЕ "Создайте пин-код" сразу.
    //    Буфер ввода чист - кружки будут пустые.
    setState(() {
      _wiped = true;
      _wipeReason = reason;
      _entered = '';
      _firstEntered = null;
      _error = null;
    });
  }

  /// Выход из промежуточного экрана в создание нового пина.
  void _createNewPin() {
    setState(() {
      _wiped = false;
      _entered = '';
      _firstEntered = null;
      _error = null;
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
    if (_wiped) return _buildWiped();

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

  /// Промежуточный экран после сброса: объясняет, что произошло,
  /// и только по кнопке пускает создание нового пина.
  Widget _buildWiped() {
    final locked = _wipeReason == 'locked';
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_bad_outlined, size: 64, color: Color(0xFF3EB8F0)),
                const SizedBox(height: 16),
                const Text('Пин и данные удалены', textAlign: TextAlign.center, style: TextStyle(fontSize: 22)),
                const SizedBox(height: 12),
                Text(
                  locked
                      ? 'Вы 3 раза ввели неверный пин-код.\nПин-код и все данные приложения\n(траты, чеки) безвозвратно удалены.'
                      : 'Пин-код и все данные приложения\n(траты, чеки) безвозвратно удалены\nпо вашему запросу.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _createNewPin,
                    child: const Text('Создать новый пин'),
                  ),
                ),
              ],
            ),
          ),
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
