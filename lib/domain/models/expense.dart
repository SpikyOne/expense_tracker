// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Модель траты - чистый Dart, без Flutter-импортов.
//
// Ключевые решения:
//   * деньги — только целые копейки (int): 199,99 руб. хранится как 19999;
//     double для денег не используется вообще — ошибки округления;
//   * дата — строка ISO-8601 ('2026-10-24'): колонка TEXT, при этом
//     сортировка по строке = сортировка по дате;
//   * способ оплаты — enum ровно из 4 значений ТЗ;
//   * маппинг в/из SQLite ручной, без кодогенерации.
//
// Хранение — таблица expenses (схема появится в М2.3):
//
//   id              INTEGER PRIMARY KEY AUTOINCREMENT
//   amount_kopecks  INTEGER NOT NULL CHECK (amount_kopecks >= 0)
//   date_iso        TEXT NOT NULL
//   category_id     INTEGER NOT NULL REFERENCES categories(id)
//   payee           TEXT NOT NULL DEFAULT ''
//   payment_method  TEXT NOT NULL CHECK (payment_method IN
//                     ('card', 'cash', 'qr_code', 'other'))
//   comment         TEXT NOT NULL DEFAULT ''
//   is_business     INTEGER NOT NULL DEFAULT 0
//   trip_id         INTEGER REFERENCES trips(id) ON DELETE SET NULL

/// Способы оплаты из ТЗ: карта, наличные, qr-code, иной.
enum PaymentMethod {
  card('card', 'Карта'),
  cash('cash', 'Наличные'),
  qrCode('qr_code', 'QR-код'),
  other('other', 'Иной');

  const PaymentMethod(this.storageKey, this.title);

  /// Ключ, под которым значение лежит в SQLite (TEXT) и приезжает из CSV.
  final String storageKey;

  /// Название, которое видим пользователь.
  final String title;

  /// Разбор ключа из БД; неизвестное значение мягко уходит в «Иной».
  static PaymentMethod fromKey(String key) =>
      values.firstWhere((m) => m.storageKey == key, orElse: () => PaymentMethod.other);

  /// Разбор человеческого названия — пригодится при импорте CSV.
  static PaymentMethod fromTitle(String title) =>
      values.firstWhere((m) => m.title.toLowerCase() == title.trim().toLowerCase(), orElse: () => PaymentMethod.other);
}

/// Трата: личная или служебная, опционально привязана к командировке.
class Expense {
  /// Имена колонок таблицы expenses — единый источник правды
  /// для toMap/fromMap здесь и CREATE TABLE в М2.3.
  static const colId = 'id';
  static const colAmountKopecks = 'amount_kopecks';
  static const colDateIso = 'date_iso';
  static const colCategoryId = 'category_id';
  static const colPayee = 'payee';
  static const colPaymentMethod = 'payment_method';
  static const colComment = 'comment';
  static const colIsBusiness = 'is_business';
  static const colTripId = 'trip_id';

  /// id в БД; null — трата ещё не сохранена.
  final int? id;

  /// Сумма в копейках: 19999 = 199,99 руб. Только int, никаких double.
  final int amountKopecks;

  /// Дата траты в ISO-8601, например '2026-10-24'.
  final String dateIso;

  /// Ссылка на categories.id.
  final int categoryId;

  /// Получатель платежа — название организации из ТЗ.
  final String payee;

  /// Способ оплаты: карта, наличные, qr-code, иной.
  final PaymentMethod paymentMethod;

  /// Произвольный комментарий, может быть пустым.
  final String comment;

  /// true — служебная трата, false — личная.
  final bool isBusiness;

  /// Ссылка на trips.id; null — трата вне командировок.
  final int? tripId;

  const Expense({
    this.id,
    required this.amountKopecks,
    required this.dateIso,
    required this.categoryId,
    this.payee = '',
    this.paymentMethod = PaymentMethod.card,
    this.comment = '',
    this.isBusiness = false,
    this.tripId,
  });

  /// Дата как DateTime — для календаря в форме и группировки по дням.
  DateTime get date => DateTime.parse(dateIso);

  /// Сумма в рублях — только для отображения, в расчётах не участвует.
  double get amountRubles => amountKopecks / 100;

  /// Рублях из поля ввода -> копейки: 19.99 -> 1999.
  /// round() страхует от двоичных хвостов вида 1998.9999999.
  static int rublesToKopecks(double rubles) => (rubles * 100).round();

  /// Та же трата с изменёнными полями — для формы редактирования.
  Expense copyWith({
    int? id,
    int? amountKopecks,
    String? dateIso,
    int? categoryId,
    String? payee,
    PaymentMethod? paymentMethod,
    String? comment,
    bool? isBusiness,
    int? tripId,
    bool clearTrip = false,
  }) => Expense(
    id: id ?? this.id,
    amountKopecks: amountKopecks ?? this.amountKopecks,
    dateIso: dateIso ?? this.dateIso,
    categoryId: categoryId ?? this.categoryId,
    payee: payee ?? this.payee,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    comment: comment ?? this.comment,
    isBusiness: isBusiness ?? this.isBusiness,
    tripId: clearTrip ? null : (tripId ?? this.tripId),
  );

  /// Строка для INSERT/UPDATE. id и trip_id при null не пишем —
  /// SQLite сам подставит AUTOINCREMENT и NULL.
  Map<String, Object?> toMap() => {
    if (id != null) colId: id,
    colAmountKopecks: amountKopecks,
    colDateIso: dateIso,
    colCategoryId: categoryId,
    colPayee: payee,
    colPaymentMethod: paymentMethod.storageKey,
    colComment: comment,
    colIsBusiness: isBusiness ? 1 : 0,
    if (tripId != null) colTripId: tripId,
  };

  /// Строка из SELECT.
  factory Expense.fromMap(Map<String, Object?> map) => Expense(
    id: map[colId] as int?,
    amountKopecks: map[colAmountKopecks] as int,
    dateIso: map[colDateIso] as String,
    categoryId: map[colCategoryId] as int,
    payee: map[colPayee] as String? ?? '',
    paymentMethod: PaymentMethod.fromKey(map[colPaymentMethod] as String? ?? 'other'),
    comment: map[colComment] as String? ?? '',
    isBusiness: (map[colIsBusiness] as int? ?? 0) != 0,
    tripId: map[colTripId] as int?,
  );

  @override
  String toString() =>
      'Expense(id: $id, ${amountRubles.toStringAsFixed(2)} руб., $dateIso, '
      'категория: $categoryId, $paymentMethod, '
      '${isBusiness ? 'служебная' : 'личная'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Expense &&
          other.id == id &&
          other.amountKopecks == amountKopecks &&
          other.dateIso == dateIso &&
          other.categoryId == categoryId &&
          other.payee == payee &&
          other.paymentMethod == paymentMethod &&
          other.comment == comment &&
          other.isBusiness == isBusiness &&
          other.tripId == tripId;

  @override
  int get hashCode =>
      Object.hash(id, amountKopecks, dateIso, categoryId, payee, paymentMethod, comment, isBusiness, tripId);
}
