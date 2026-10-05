#!/usr/bin/env bash
# Расшифровывает архив доступов из «Секреты (зашифровано)/» в папку «~/Доступы — <название проекта>»
# (вне репозитория).
#   bash tools/secrets_unpack.sh            — расшифровать
#   bash tools/secrets_unpack.sh --restore  — и вернуть .local/ и файлы .env на их места в проекте
#   bash tools/secrets_unpack.sh --check    — только проверить, что архив открывается паролем
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
IN="Секреты (зашифровано)/доступы.tar.gz.enc"
DEST="$HOME/Доступы — $(basename "$ROOT")"

if [ ! -f "$IN" ]; then
  echo "Архива нет: $IN. Его создаёт tools/secrets_pack.sh." >&2
  exit 1
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "Пароль от архива:"
if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in "$IN" -out "$TMP/a.tgz" \
   || ! tar -tzf "$TMP/a.tgz" >/dev/null 2>&1; then
  echo "Архив не открылся — скорее всего, пароль неверный." >&2
  exit 1
fi
if [ "${1:-}" = "--check" ]; then
  echo "Архив открывается, файлов: $(tar -tzf "$TMP/a.tgz" | grep -vc '/$' || true)"
  exit 0
fi

mkdir -p "$DEST"
tar -xzf "$TMP/a.tgz" -C "$DEST"
chmod -R go-rwx "$DEST"
echo "Расшифровано в $DEST/доступы"

if [ "${1:-}" = "--restore" ]; then
  SRC="$DEST/доступы/проект"
  if [ -d "$SRC" ]; then
    while IFS= read -r -d '' f; do
      f="${f#./}"
      if [ -e "$ROOT/$f" ]; then
        echo "  уже есть, не перезаписываю: $f"
      else
        mkdir -p "$ROOT/$(dirname "$f")"; cp -p "$SRC/$f" "$ROOT/$f"; echo "  вернул: $f"
      fi
    done < <(cd "$SRC" && find . -type f -print0)
  fi
  if [ -n "$(find "$DEST/доступы/компьютер" -type f 2>/dev/null | head -1)" ]; then
    echo "Файлы с прежнего компьютера (ssh-ключи и т. п.) разложи вручную: $DEST/доступы/компьютер"
  fi
fi
