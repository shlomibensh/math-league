#!/usr/bin/env bash
# מעלה את ליגת המספרים ל-GitHub Pages בפקודה אחת, בעזרת GitHub CLI (gh).
# שימוש:  ./deploy.sh            (שם הרפו: math-league)
#         ./deploy.sh my-repo    (שם אחר)
set -euo pipefail
REPO="${1:-math-league}"
cd "$(dirname "$0")"

# רק הקבצים של המשחק עולים לרפו – שום קובץ אחר מהתיקייה.
FILES=(index.html config.js schema.sql README.md deploy.sh manifest.webmanifest icon-192.png icon-512.png apple-touch-icon.png .github/workflows/keepalive.yml)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "חסר הקובץ $f. מריצים את הסקריפט מתוך התיקייה שחולצה מה-ZIP."; exit 1; }
done

command -v git >/dev/null || { echo "חסר git"; exit 1; }
command -v gh  >/dev/null || { echo "חסר GitHub CLI – מתקינים מ-https://cli.github.com ומריצים שוב"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login -w -p https
OWNER="$(gh api user -q .login)"
FULL="$OWNER/$REPO"

if gh repo view "$FULL" >/dev/null 2>&1; then echo "הרפו $FULL כבר קיים – עוצר כדי לא לדרוס אותו."; exit 1; fi

# git: repo חדש בתיקייה הזו
[ -d .git ] || git init -q
git checkout -q -B main
if [ -z "$(git config user.name || true)" ]; then
  git config user.name "$OWNER"
  git config user.email "$(gh api user -q '.id')+$OWNER@users.noreply.github.com"
fi
git add -- "${FILES[@]}"
git commit -qm "ליגת המספרים" || true

echo "יוצר את $FULL ומעלה…"
gh repo create "$FULL" --public --source=. --remote=origin --push

echo "מפעיל GitHub Pages…"
echo '{"source":{"branch":"main","path":"/"}}' | gh api -X POST "repos/$FULL/pages" --input - >/dev/null 2>&1 \
  || echo '{"source":{"branch":"main","path":"/"}}' | gh api -X PUT "repos/$FULL/pages" --input - >/dev/null

echo "מגדיר את הסודות לפעולת ה-keepalive…"
URL="$(sed -n "s/.*supabaseUrl: *'\([^']*\)'.*/\1/p" config.js)"
KEY="$(sed -n "s/.*supabaseKey: *'\([^']*\)'.*/\1/p" config.js)"
if [ -n "$URL" ] && [ -n "$KEY" ]; then
  gh secret set SUPABASE_URL -R "$FULL" -b "$URL"
  gh secret set SUPABASE_KEY -R "$FULL" -b "$KEY"
  for i in 1 2 3 4 5; do
    gh workflow run keepalive.yml -R "$FULL" >/dev/null 2>&1 && { echo "ה-keepalive הופעל פעם ראשונה ✓"; break; }
    sleep 4
  done
else
  echo "config.js ריק – מדלג על הסודות (אין Supabase)."
fi

echo
echo "✓ מוכן. האתר יעלה תוך דקה-שתיים בכתובת:"
echo "   https://$OWNER.github.io/$REPO/"
