#!/usr/bin/env bash
# Copyright (c) 2026, Григорьев Серафим. BSD-3-Clause License. См. LICENSE.
#
# Единый прогон всех автопроверок проекта на хосте:
#   1) dart-aurora analyze — ноль замечаний (требование ТЗ);
#   2) все чек-скрипты tool/check_*.dart — CRUD, схема, поиск и т.д.
#
# Использование: ./tool/run_all_checks.sh
# Код возврата:  0 — всё зелёное; 1 — есть провалы; 2 — окружение сломано.

set -u

# Всегда работаем от корня проекта, откуда бы скрипт ни запустили.
cd "$(dirname "$0")/.."

# Без dart-aurora проверки не имеют смысла — сообщаем и выходим.
if ! command -v dart-aurora >/dev/null 2>&1; then
  echo 'ОШИБКА: dart-aurora не найден в PATH.'
  exit 2
fi

failed=0

# ---------- 1. Статический анализатор ----------
echo '=== dart-aurora analyze ==='
if dart-aurora analyze; then
  echo 'OK   анализатор: ноль замечаний'
else
  echo 'FAIL анализатор: есть замечания (см. выше)'
  failed=1
fi
echo

# ---------- 2. Чек-скрипты ----------
# Каждый скрипт сам печатает OK/FAIL по своим проверкам и выходит
# с ненулевым кодом, если хоть одна упала. Собираем глоубом —
# новый check_*.dart подхватится автоматически.
shopt -s nullglob
check_scripts=(tool/check_*.dart)
shopt -u nullglob

if [ "${#check_scripts[@]}" -eq 0 ]; then
  echo 'ОШИБКА: в tool/ нет ни одного check_*.dart — проверки не найдены.'
  exit 2
fi

for script in "${check_scripts[@]}"; do
  echo "=== dart-aurora run $script ==="
  if dart-aurora run "$script"; then
    echo "OK   $script"
  else
    code=$?
    echo "FAIL $script (код возврата $code)"
    failed=1
  fi
  echo
done

# ---------- Итог ----------
if [ "$failed" -eq 0 ]; then
  echo 'ВСЁ ОК: анализатор и все чек-скрипты зелёные.'
else
  echo 'ЕСТЬ ОШИБКИ: провалы помечены FAIL выше.'
fi
exit "$failed"
