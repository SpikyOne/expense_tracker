// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Проверка ExpenseDao на хосте, без эмулятора. Запуск:
// dart-aurora run tool/check_expense_dao.dart

// Скрипты tool/ осознанно печатают отчёт в консоль — отключаем
// avoid_print только здесь. Анализатор файлы tool/ продолжает проверять.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:expense_tracker/data/dao/category_dao.dart';
import 'package:expense_tracker/data/dao/expense_dao.dart';
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
    print('FAIL $name — ожидалось: $expected, получено: $actual');
  }
}

/// Проверка, что [action] выбрасывает исключение ровно типа [T], причём
/// текст ошибки содержит [messagePart] — иначе можно пройти «не за ту»
/// ошибку (например, FOREIGN KEY вместо CHECK).
void checkThrows<T extends Object>(String name, void Function() action, String messagePart) {
  try {
    action();
    _failed++;
    print('FAIL $name — исключение не выброшено');
  } on T catch (e) {
    if (e.toString().contains(messagePart)) {
      _passed++;
      print('OK   $name');
    } else {
      _failed++;
      print('FAIL $name — в ошибке ожидалось "$messagePart", получено: $e');
    }
  } catch (e) {
    _failed++;
    print('FAIL $name — выброшено ${e.runtimeType} вместо $T: $e');
  }
}

void main() {
  final db = DatabaseService.inMemory();
  final categoryDao = CategoryDao(db);
  final dao = ExpenseDao(db);

  final productsId = db.getCategories().firstWhere((c) => c.name == 'Продукты').id!;
  final transportId = db.getCategories().firstWhere((c) => c.name == 'Транспорт').id!;
  final cafeId = categoryDao.insert('Кафе у дома');

  // Командировка для проверки trip_id (TripDao появится в М3.4).
  db.rawExecute(
    "INSERT INTO trips (title, start_date, end_date) VALUES ('Сапсан', '2026-10-22', '2026-10-25');",
  );
  final tripId = db.rawSelect('SELECT MAX(id) AS id FROM trips;').first['id'] as int;

  Expense expense(
    int categoryId,
    int amountKopecks,
    String dateIso, {
    String payee = '',
    String comment = '',
    PaymentMethod method = PaymentMethod.card,
    bool business = false,
    int? trip,
  }) => Expense(
    amountKopecks: amountKopecks,
    dateIso: dateIso,
    categoryId: categoryId,
    payee: payee,
    paymentMethod: method,
    comment: comment,
    isBusiness: business,
    tripId: trip,
  );

  final e1Id = dao.insert(
    expense(productsId, 15000, '2026-10-20', payee: 'ООО «Ромашка»', comment: 'Кофе с Ёлкой'),
  );
  final e2Id = dao.insert(
    expense(productsId, 9900, '2026-10-24', payee: 'Пятёрочка', comment: 'Молоко', method: PaymentMethod.cash),
  );
  final e3Id = dao.insert(
    expense(cafeId, 45000, '2026-10-24', payee: 'Кофейня', comment: 'Латте и чизкейк', method: PaymentMethod.qrCode),
  );
  final e4Id = dao.insert(expense(transportId, 6000, '2026-10-25', payee: 'Метро', method: PaymentMethod.other));
  final e5Id = dao.insert(
    expense(transportId, 120000, '2026-10-22', payee: 'ООО «ЖелДор»', comment: 'Билет Сапсан', business: true, trip: tripId),
  );
  final e0Id = dao.insert(expense(productsId, 100, '2026-10-19'));

  String searchTextOf(int id) => db
      .rawSelect('SELECT search_text FROM expenses WHERE id = ?;', [id])
      .first['search_text'] as String;

  List<int> ids(List<ExpenseWithCategory> rows) => [for (final r in rows) r.expense.id!];

  // ---------- Вставка и чтение ----------
  check('insert: возвращает id больше нуля', e1Id > 0, true);
  check('insert: search_text заполнен из payee и comment', searchTextOf(e1Id), 'ооо ромашка кофе с елкой');
  check('insert: пустые payee и comment — пустой search_text', searchTextOf(e0Id), '');

  final fetched = dao.getById(e1Id)!;
  check(
    'getById: все поля на месте',
    fetched.expense,
    Expense(
      id: e1Id,
      amountKopecks: 15000,
      dateIso: '2026-10-20',
      categoryId: productsId,
      payee: 'ООО «Ромашка»',
      paymentMethod: PaymentMethod.card,
      comment: 'Кофе с Ёлкой',
    ),
  );
  check(
    'getById: категория из JOIN',
    fetched.category,
    Category(id: productsId, name: 'Продукты', isDefault: true),
  );
  check('getById: is_business сохраняется', dao.getById(e5Id)!.expense.isBusiness, true);
  check('getById: trip_id сохраняется', dao.getById(e5Id)!.expense.tripId, tripId);
  check('getById: несуществующий id — null', dao.getById(-1), null);

  checkThrows<SqliteException>(
    'insert: чужая категория отклонена (FK)',
    () => dao.insert(expense(999, 100, '2026-10-20')),
    'FOREIGN KEY',
  );
  checkThrows<SqliteException>(
    'insert: отрицательная сумма отклонена (CHECK)',
    () => dao.insert(expense(productsId, -1, '2026-10-20')),
    'CHECK',
  );

  // ---------- Правка ----------
  checkThrows<ArgumentError>(
    'update: трата без id — ArgumentError',
    () => dao.update(expense(productsId, 100, '2026-10-20')),
    'не заполнен',
  );
  checkThrows<StateError>(
    'update: несуществующая трата — StateError',
    () => dao.update(expense(productsId, 100, '2026-10-20').copyWith(id: -1)),
    'не найдена',
  );

  // Комментарий сохраняет основу «ёлк» — последующие поисковые проверки
  // остаются в силе, а новое слово добавляется.
  final edited = expense(
    productsId,
    15000,
    '2026-10-20',
    payee: 'ООО «Ромашка»',
    comment: 'Кофе с Ёлкой и булочкой',
  ).copyWith(id: e1Id);
  dao.update(edited);
  check('update: поля перезаписаны', dao.getById(e1Id)!.expense, edited);
  check('update: search_text пересчитан', searchTextOf(e1Id), 'ооо ромашка кофе с елкой и булочкой');

  // ---------- Список, порядок, JOIN ----------
  final allIds = [e4Id, e3Id, e2Id, e5Id, e1Id, e0Id]; // новые раньше; 10-24: e3 позже e2
  check('query: все траты, новые раньше', ids(dao.query()).join('|'), allIds.join('|'));
  check(
    'query: JOIN — у каждой траты её категория',
    dao.query().every((r) => r.category.id == r.expense.categoryId),
    true,
  );

  // ---------- Фильтры ----------
  check('фильтр: по категории', ids(dao.query(categoryId: productsId)).join('|'), [e2Id, e1Id, e0Id].join('|'));
  check('фильтр: по способу оплаты', ids(dao.query(paymentMethod: PaymentMethod.cash)).join('|'), [e2Id].join('|'));
  check(
    'фильтр: период включительно',
    ids(dao.query(fromDateIso: '2026-10-22', toDateIso: '2026-10-24')).join('|'),
    [e3Id, e2Id, e5Id].join('|'),
  );
  check('фильтр: только нижняя граница', ids(dao.query(fromDateIso: '2026-10-24')).join('|'), [e4Id, e3Id, e2Id].join('|'));
  check(
    'фильтр: период + категория (AND)',
    ids(dao.query(fromDateIso: '2026-10-19', toDateIso: '2026-10-20', categoryId: productsId)).join('|'),
    [e1Id, e0Id].join('|'),
  );

  // ---------- Поиск ----------
  check('поиск: по получателю', ids(dao.query(searchText: 'ромашка')).join('|'), [e1Id].join('|'));
  check('поиск: по комментарию', ids(dao.query(searchText: 'латте')).join('|'), [e3Id].join('|'));
  check('поиск: ё → е, по основе слова', ids(dao.query(searchText: 'Ёлк')).join('|'), [e1Id].join('|'));
  check('поиск: ё в запросе и в данных', ids(dao.query(searchText: 'Пятёрочка')).join('|'), [e2Id].join('|'));
  check('поиск: регистр и пунктуация не мешают', ids(dao.query(searchText: 'ООО, РОМАШКА!')).join('|'), [e1Id].join('|'));
  check('поиск: после правки находится новое слово', ids(dao.query(searchText: 'булочк')).join('|'), [e1Id].join('|'));
  check('поиск: пустой результат', ids(dao.query(searchText: 'несуществующее слово')).join('|'), '');
  check(
    'поиск: комбинация с категорией (AND)',
    ids(dao.query(searchText: 'молоко', categoryId: productsId)).join('|'),
    [e2Id].join('|'),
  );
  check(
    'поиск: чужая категория отсекает результат',
    ids(dao.query(searchText: 'молоко', categoryId: cafeId)).join('|'),
    '',
  );
  check('поиск: запрос из знаков препинания — фильтр пропущен', ids(dao.query(searchText: '?!')).join('|'), allIds.join('|'));

  // ---------- Удаление ----------
  checkThrows<StateError>(
    'delete: несуществующая трата — StateError',
    () => dao.delete(-1),
    'не найдена',
  );
  final e6Id = dao.insert(expense(transportId, 500, '2026-10-26', payee: 'Вокзал', comment: 'Кофе в дорогу'));
  db.rawExecute(
    'INSERT INTO receipts (expense_id, file_path, created_at) VALUES (?, ?, ?);',
    [e6Id, 'receipts/2026/10/check.jpg', '2026-10-26T10:00:00'],
  );
  dao.delete(e6Id);
  check('delete: трата исчезла', dao.getById(e6Id), null);
  check(
    'delete: чеки удаляются каскадом',
    db.rawSelect('SELECT COUNT(*) AS n FROM receipts;').first['n'] as int,
    0,
  );

  db.close();

  print('');
  print('Пройдено: $_passed, упало: $_failed');
  if (_failed > 0) {
    print('ЕСТЬ ОШИБКИ');
    exit(1);
  }
  print('ВСЁ ОК');
}
