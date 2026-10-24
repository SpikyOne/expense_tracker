// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка TripDao на хосте, без эмулятора. Запуск:
// dart-aurora run tool/check_trip_dao.dart

// Скрипты tool/ осознанно печатают отчёт в консоль - отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/data/dao/expense_dao.dart';
import 'package:expense_tracker/data/dao/trip_dao.dart';
import 'package:expense_tracker/data/database/database_service.dart';
import 'package:expense_tracker/domain/models/models.dart';
import 'package:sqlite3/sqlite3.dart';

int _passed = 0;
int _failed = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    _passed++;
    print('OK   $name');
  } else {
    _failed++;
    print('FAIL $name - ожидалось: $expected, получено: $actual');
  }
}

/// Проверка, что [action] выбрасывает исключение ровно типа [T], причём
/// текст ошибки содержит [messagePart] - иначе можно пройти «не за ту»
/// ошибку (например, FOREIGN KEY вместо CHECK).
void checkThrows<T extends Object>(String name, void Function() action, String messagePart) {
  try {
    action();
    _failed++;
    print('FAIL $name - исключение не выброшено');
  } on T catch (e) {
    if (e.toString().contains(messagePart)) {
      _passed++;
      print('OK   $name');
    } else {
      _failed++;
      print('FAIL $name - в ошибке ожидалось "$messagePart", получено: $e');
    }
  } catch (e) {
    _failed++;
    print('FAIL $name - выброшено ${e.runtimeType} вместо $T: $e');
  }
}

void main() {
  final db = DatabaseService.inMemory();
  final tripDao = TripDao(db);
  final expenseDao = ExpenseDao(db);

  // Траты вставляем готовым ExpenseDao: проверяем только TripDao, но
  // траты обязаны быть валидными (FK на категорию).
  final categoryId = db.getCategories().first.id!;

  int insertExpense({int? tripId}) => expenseDao.insert(
    Expense(amountKopecks: 100, dateIso: '2026-10-23', categoryId: categoryId, tripId: tripId),
  );

  final t1Id = tripDao.insert(const Trip(title: 'Сапсан', startDateIso: '2026-10-22', endDateIso: '2026-10-25'));
  final t2Id = tripDao.insert(const Trip(title: 'Казань', startDateIso: '2026-10-20', endDateIso: '2026-10-21'));
  final t3Id = tripDao.insert(const Trip(title: 'Питер', startDateIso: '2026-10-22', endDateIso: '2026-10-23'));

  // ---------- Вставка и чтение ----------
  check('insert: возвращает id больше нуля', t1Id > 0, true);
  check(
    'getById: все поля на месте',
    tripDao.getById(t1Id),
    Trip(id: t1Id, title: 'Сапсан', startDateIso: '2026-10-22', endDateIso: '2026-10-25'),
  );
  check('getById: несуществующий id - null', tripDao.getById(-1), null);

  // ---------- Список ----------
  // Порядок: start_date DESC; при равной дате - id DESC
  // («Питер» вставлен позже «Сапсана» при том же 2026-10-22).
  check(
    'query: новые раньше, при равной дате - вставленные позже раньше',
    [for (final t in tripDao.query()) t.id].join('|'),
    [t3Id, t1Id, t2Id].join('|'),
  );

  // ---------- Правка ----------
  checkThrows<ArgumentError>(
    'update: без id - ArgumentError',
    () => tripDao.update(const Trip(title: 'x', startDateIso: '2026-10-01', endDateIso: '2026-10-02')),
    'не заполнен',
  );
  checkThrows<StateError>(
    'update: несуществующая - StateError',
    () => tripDao.update(const Trip(id: -1, title: 'x', startDateIso: '2026-10-01', endDateIso: '2026-10-02')),
    'не найдена',
  );
  final edited = Trip(id: t2Id, title: 'Казань-2026', startDateIso: '2026-10-19', endDateIso: '2026-10-21');
  tripDao.update(edited);
  check('update: поля перезаписаны', tripDao.getById(t2Id), edited);

  // ---------- Ограничение схемы ----------
  checkThrows<SqliteException>(
    'insert: конец раньше начала отклонён (CHECK)',
    () => tripDao.insert(const Trip(title: 'Кривая', startDateIso: '2026-10-25', endDateIso: '2026-10-20')),
    'CHECK',
  );

  // ---------- Счётчик трат ----------
  final e1Id = insertExpense(tripId: t1Id);
  final e2Id = insertExpense(tripId: t1Id);
  insertExpense(); // личная, без поездки
  check('expensesCount: считает траты поездки', tripDao.expensesCount(t1Id), 2);

  // ---------- Удаление с отвязкой трат ----------
  checkThrows<StateError>('delete: несуществующая - StateError', () => tripDao.delete(-1), 'не найдена');

  tripDao.delete(t1Id);
  check('delete: поездка исчезла', tripDao.getById(t1Id), null);
  check('delete: траты поездки остались', expenseDao.getById(e1Id)!.expense.id, e1Id);
  check('delete: trip_id первой траты отвязан (SET NULL)', expenseDao.getById(e1Id)!.expense.tripId, null);
  check('delete: trip_id второй траты отвязан (SET NULL)', expenseDao.getById(e2Id)!.expense.tripId, null);
  check('expensesCount после удаления: 0', tripDao.expensesCount(t1Id), 0);

  db.close();

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
