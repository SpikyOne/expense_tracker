// Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
//
// Модель командировки - чистый Dart, без Flutter-импортов.
//
// Командировка группирует служебные траты: траты ссылаются на поездку
// колонкой expenses.trip_id. При удалении поездки SQLite сам отвязывает
// траты (FK ON DELETE SET NULL) — сами траты при этом не трогаются.
//
// Хранение — таблица trips:
//
//   id          INTEGER PRIMARY KEY AUTOINCREMENT
//   title       TEXT NOT NULL
//   start_date  TEXT NOT NULL
//   end_date    TEXT NOT NULL CHECK (end_date >= start_date)

/// Командировка: служебная поездка с периодом.
class Trip {
  /// Имена колонок таблицы trips - единый источник правды:
  /// toMap/fromMap здесь и CREATE TABLE в слое data используют их.
  static const colId = 'id';
  static const colTitle = 'title';
  static const colStartDate = 'start_date';
  static const colEndDate = 'end_date';

  /// id в БД; null - командировка ещё не сохранена.
  final int? id;

  /// Название поездки («Сапсан», «Казань, переговоры»).
  final String title;

  /// Первый день поездки, ISO-8601 ('2026-10-22').
  final String startDateIso;

  /// Последний день поездки включительно, ISO-8601 ('2026-10-25').
  final String endDateIso;

  const Trip({
    this.id,
    required this.title,
    required this.startDateIso,
    required this.endDateIso,
  });

  /// Начало поездки как DateTime - для календаря в форме.
  DateTime get start => DateTime.parse(startDateIso);

  /// Конец поездки (включительно) как DateTime.
  DateTime get end => DateTime.parse(endDateIso);

  /// Та же командировка с изменёнными полями - для формы правки.
  Trip copyWith({int? id, String? title, String? startDateIso, String? endDateIso}) => Trip(
    id: id ?? this.id,
    title: title ?? this.title,
    startDateIso: startDateIso ?? this.startDateIso,
    endDateIso: endDateIso ?? this.endDateIso,
  );

  /// Строка для INSERT/UPDATE. id при null не пишем -
  /// SQLite сам подставит AUTOINCREMENT.
  Map<String, Object?> toMap() => {
    if (id != null) colId: id,
    colTitle: title,
    colStartDate: startDateIso,
    colEndDate: endDateIso,
  };

  /// Строка из SELECT.
  factory Trip.fromMap(Map<String, Object?> map) => Trip(
    id: map[colId] as int?,
    title: map[colTitle] as String,
    startDateIso: map[colStartDate] as String,
    endDateIso: map[colEndDate] as String,
  );

  @override
  String toString() => 'Trip(id: $id, $title, $startDateIso..$endDateIso)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Trip &&
          other.id == id &&
          other.title == title &&
          other.startDateIso == startDateIso &&
          other.endDateIso == endDateIso;

  @override
  int get hashCode => Object.hash(id, title, startDateIso, endDateIso);
}
