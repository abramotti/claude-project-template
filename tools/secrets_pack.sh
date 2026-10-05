#!/usr/bin/env bash
# Собирает доступы проекта в один архив и шифрует паролем владельца (AES-256, PBKDF2 600 000 итераций).
# Результат — «Секреты (зашифровано)/доступы.tar.gz.enc», его можно хранить в GitHub: без пароля не открыть.
# Пароль спрашивает openssl, нигде не сохраняется. Потерял пароль — архив не восстановить.
#   bash tools/secrets_pack.sh      — собрать и зашифровать
# Что попадает в архив: папка .local/, все файлы .env проекта и файлы с компьютера из tools/secrets_extra.txt.
# Расшифровка — tools/secrets_unpack.sh (см. ВОССТАНОВЛЕНИЕ.md).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/Секреты (зашифровано)/доступы.tar.gz.enc"
TMP=$(mktemp -d); trap 'rm -rf "$TMP" "$OUT.new"' EXIT
B="$TMP/доступы"; mkdir -p "$B/проект" "$B/компьютер"

echo "Собираю…"
# 1. .local/ и все .env проекта — с путями, чтобы secrets_unpack.sh --restore вернул их на место
while IFS= read -r -d '' f; do
  mkdir -p "$B/проект/$(dirname "$f")"
  cp -p "$f" "$B/проект/$f"
done < <(find . \( -name .git -o -name node_modules -o -name .venv -o -name venv \) -prune -o \
  -type f \( -path './.local/*' -o -name '.env' -o -name '.env.*' \) \
  ! -name '.env.example' ! -name '.DS_Store' -print0)

# 2. файлы вне проекта (ssh-ключи и т. п.) — по списку
if [ -f tools/secrets_extra.txt ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in '~'*) p="$HOME${line#\~}" ;; *) p="$line" ;; esac
    if [ -e "$p" ]; then
      case "$p" in "$HOME"/*) rel="домашняя папка/${p#"$HOME"/}" ;; *) rel="${p#/}" ;; esac
      d="$B/компьютер/$(dirname "$rel")"; mkdir -p "$d"; cp -Rp "$p" "$d/"
    else
      echo "  нет: $line"
    fi
  done < tools/secrets_extra.txt
fi

N=$(find "$B" -type f | wc -l | tr -d ' ')
if [ "$N" = "0" ]; then
  echo "Шифровать нечего: положи значения в .local/доступы/ДОСТУПЫ.md и запусти снова." >&2
  exit 1
fi
date '+Собрано %d.%m.%Y %H:%M' > "$B/СОБРАНО.txt"
echo "Файлов: $N"
mkdir -p "$(dirname "$OUT")"
COPYFILE_DISABLE=1 tar -czf "$TMP/a.tgz" -C "$TMP" доступы

echo "Пароль архива (дважды). Архив уже был — вводи прежний пароль."
echo "Запиши его туда, где он переживёт потерю компьютера: менеджер паролей, бумага."
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt -in "$TMP/a.tgz" -out "$OUT.new"
# проверка: расшифровывается тем же паролем
echo "Проверка — введи пароль ещё раз:"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in "$OUT.new" | tar -tzf - >/dev/null
mv "$OUT.new" "$OUT"
echo "Готово: $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))."
echo "Скажи Claude «сделай бэкап» — зашифрованный архив уйдёт в GitHub вместе с проектом."
