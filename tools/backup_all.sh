#!/usr/bin/env bash
# Полный бэкап проекта: добавить ВСЕ изменения, проверить их на секреты и тяжёлые файлы,
# закоммитить и отправить в GitHub. Claude зовёт его в конце каждой сессии и по просьбе «сделай бэкап».
#   bash tools/backup_all.sh            — сохранить и отправить
#   NO_PUSH=1 bash tools/backup_all.sh  — только сохранить на этом компьютере
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -e .git ]; then
  echo "Git в этой папке не настроен — бэкапить некуда. Скажи Claude: «подключи бэкап в GitHub»." >&2
  exit 1
fi

git add -A   # весь проект; секреты и тяжёлое видео отсекает .gitignore

# контроль: живые секреты и файлы тяжелее лимита GitHub не должны уйти в репозиторий
SECRETS='[0-9]{8,11}:AA[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9_-]{30,}|live_[A-Za-z0-9_-]{30,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[abp]-[A-Za-z0-9-]{20,}|BEGIN [A-Z ]*PRIVATE KEY'
secret_files=""
big_files=""
while IFS= read -r -d '' f; do
  hits=$(git --literal-pathspecs diff --cached -U0 -- "$f" | grep -E '^\+' | grep -cE "$SECRETS" || true)
  if [ "${hits:-0}" != "0" ]; then secret_files="$secret_files  $f"$'\n'; fi
  if [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d ' ')" -gt 95000000 ]; then big_files="$big_files  $f"$'\n'; fi
done < <(git diff --cached --name-only -z --diff-filter=AM)

if [ -n "$secret_files" ] || [ -n "$big_files" ]; then
  git reset -q
  if [ -n "$secret_files" ]; then
    printf 'Похоже на секрет (токен, ключ) в файлах:\n%s' "$secret_files" >&2
    echo "Убери значение в .local/доступы/ и запусти бэкап снова." >&2
  fi
  if [ -n "$big_files" ]; then
    printf 'Файлы тяжелее 95 МБ — GitHub их не примет:\n%s' "$big_files" >&2
    echo "Перенеси их в облачный диск или добавь в .gitignore." >&2
  fi
  echo "Бэкап отменён, ничего не отправлено." >&2
  exit 1
fi

if git diff --cached --quiet; then
  echo "Новых изменений нет."
else
  git commit -q -m "${COMMIT_MSG:-Бэкап $(date '+%d.%m.%Y %H:%M')}"
fi

if [ -n "${NO_PUSH:-}" ]; then
  echo "Сохранено на этом компьютере: $(git log -1 --format='%h %s')"
  exit 0
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "Сохранено только на этом компьютере — GitHub не подключён. Скажи Claude: «подключи бэкап в GitHub»."
  exit 0
fi
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  git pull --rebase --autostash -q
  git push -q
else
  git push -q -u origin HEAD
fi
echo "Отправлено: $(git log -1 --format='%h %s')"
