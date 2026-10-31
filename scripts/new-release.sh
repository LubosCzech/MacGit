#!/bin/bash
# Jedním příkazem od čísla verze k draftu na GitHubu.
#
# Publikování zůstává samostatný krok schválně: draft jde nejdřív vyzkoušet
# skutečnou aktualizací z předchozí verze a teprve pak zveřejnit.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
Použití:
  bash scripts/new-release.sh <verze> [--yes]   připraví a nahraje draft
  bash scripts/new-release.sh publish [--yes]   zveřejní připravený draft
  bash scripts/new-release.sh status            ukáže, kde vydání stojí

Přerušené vydání (třeba spadlá notarizace) dokončíte stejným příkazem
se stejným číslem verze; hotové kroky se přeskočí.

Příklad: bash scripts/new-release.sh 1.7
USAGE
}

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
note() { printf '  %s\n' "$1"; }
fail() { printf '\n✗ %s\n' "$1" >&2; exit 1; }

confirm() {
  if $ASSUME_YES; then return 0; fi
  printf '\n%s\n  Napište "ano" pro pokračování: ' "$1"
  local answer; read -r answer
  [[ "$answer" == ano ]] || fail "Zrušeno. Nic se neodeslalo."
}

released_on_github() {
  gh release view "v$1" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1
}

ACTION="${1:-}"
[[ -n "$ACTION" ]] || { usage; exit 1; }
[[ "$ACTION" != --help && "$ACTION" != -h ]] || { usage; exit 0; }
shift
ASSUME_YES=false
if [[ "${1:-}" == --yes ]]; then ASSUME_YES=true; shift; fi
[[ $# == 0 ]] || { usage; exit 1; }

source scripts/config.sh

if [[ "$ACTION" == status ]]; then
  printf 'Verze:      %s (build %s), režim %s\n' "$APP_VERSION" "$APP_BUILD" "$RELEASE_MODE"
  printf 'Tag v%s:   %s\n' "$APP_VERSION" \
    "$(git rev-parse -q --verify "refs/tags/v$APP_VERSION" >/dev/null && echo existuje || echo chybí)"
  printf 'Připraveno: %s\n' "$([[ -f "dist/releases/v$APP_VERSION/.ready" ]] && echo ano || echo ne)"
  printf 'GitHub:     %s\n' "$(gh release view "v$APP_VERSION" --repo "$GITHUB_REPOSITORY" \
    --json isDraft --jq 'if .isDraft then "draft" else "zveřejněno" end' 2>/dev/null || echo 'zatím nic')"
  exit 0
fi

if [[ "$ACTION" == publish ]]; then
  [[ -f "dist/releases/v$APP_VERSION/.ready" ]] || fail "Verze $APP_VERSION není připravená."
  released_on_github "$APP_VERSION" || fail "Draft v$APP_VERSION na GitHubu není. Nejdřív spusťte s číslem verze."
  confirm "Zveřejnit Revision $APP_VERSION jako Latest? Uživatelům se nabídne aktualizace.
  Ověřili jste aktualizaci z předchozí verze na tento build?"
  bash scripts/release.sh publish
  exit 0
fi

VERSION="$ACTION"
[[ "$VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || fail "Neplatné číslo verze: $VERSION"

# Tři stavy: nové vydání, rozdělaná verze bez tagu, plně otagované vydání.
RESUME=false
NEEDS_TAG=true
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  [[ "$(git rev-parse "v$VERSION^{commit}")" == "$(git rev-parse HEAD)" && "$APP_VERSION" == "$VERSION" ]] \
    || fail "Tag v$VERSION už existuje a neodpovídá aktuálnímu stavu. Zvolte vyšší verzi."
  RESUME=true
  NEEDS_TAG=false
elif [[ "$APP_VERSION" == "$VERSION" && -f "dist/releases/v$VERSION/.ready" ]]; then
  # release.env je na této verzi a build je hotový, jen se ještě netagovalo.
  RESUME=true
fi

step "Kontrola pracovní kopie"
# Tag musí ukazovat na kód, který se opravdu sestavil a notarizoval.
[[ -z "$(git status --porcelain)" ]] || fail "Pracovní kopie není čistá. Nejdřív vše zacommitujte."
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == main ]] || fail "Vydává se z větve main, jste na '$BRANCH'."
command -v gh >/dev/null || fail "Chybí GitHub CLI (gh). Nainstalujte a spusťte gh auth login."
gh auth status >/dev/null 2>&1 || fail "gh není přihlášené. Spusťte gh auth login."
git fetch --quiet origin main
# Být napřed je v pořádku (push přijde níž), být pozadu ne.
git merge-base --is-ancestor origin/main HEAD \
  || fail "main je pozadu za origin/main. Nejdřív git pull."
note "čistá kopie, větev main, gh přihlášené"

# První vydání: na GitHubu ještě není žádné stabilní vydání, takže není předchozí appcast,
# proti kterému by šlo ověřit build. release.sh prepare to samo ještě jednou potvrdí (HTTP 404).
FIRST=false
if ! gh api "repos/$GITHUB_REPOSITORY/releases/latest" >/dev/null 2>&1; then
  FIRST=true
  note "první vydání – v repozitáři $GITHUB_REPOSITORY zatím žádné není"
fi

step "Kontrola poznámek k vydání"
head -1 RELEASE_NOTES.md | grep -qx "# Revision $VERSION" \
  || fail "RELEASE_NOTES.md musí začínat řádkem '# Revision $VERSION', má '$(head -1 RELEASE_NOTES.md)'."
note "$(head -1 RELEASE_NOTES.md)"

step "Testy"
bash scripts/run-tests.sh

if $RESUME; then
  step "Pokračování ve vydání $VERSION"
  if $NEEDS_TAG; then
    note "release.env i sestavení už na $VERSION jsou, chybí jen tag"
    confirm "Označit a nahrát už připravené Revision $VERSION (build $APP_BUILD)?
  Zapíše se tag do origin/main a vznikne draft na GitHubu.
  Uživatelé zatím nic neuvidí — publikuje se až samostatným krokem."
    git tag "v$VERSION"
    git push --quiet origin main "v$VERSION"
    note "tag v$VERSION odeslán"
  else
    note "tag v$VERSION i verze v release.env sedí, přeskakuji"
  fi
elif $FIRST && [[ "$VERSION" == "$APP_VERSION" ]]; then
  # První vydání s verzí, která už v release.env je (např. 1.0, build 1): nic se nezvyšuje,
  # jen se označí aktuální commit.
  confirm "Vydat Revision $VERSION (build $APP_BUILD) – první vydání?
  Zapíše se tag v$VERSION do origin/main a vznikne draft na GitHubu.
  Uživatelé zatím nic neuvidí — publikuje se až samostatným krokem."
  step "Tag"
  git tag "v$VERSION"
  git push --quiet origin main "v$VERSION"
  note "tag v$VERSION odeslán (APP_VERSION=$APP_VERSION, APP_BUILD=$APP_BUILD)"
else
  NEW_BUILD=$((APP_BUILD + 1))
  [[ "$VERSION" != "$APP_VERSION" ]] || fail "Verze $VERSION už je v release.env. Zvolte vyšší."

  confirm "Vydat Revision $VERSION (build $NEW_BUILD)?
  Zapíše se commit a tag do origin/main a vznikne draft na GitHubu.
  Uživatelé zatím nic neuvidí — publikuje se až samostatným krokem."

  step "Verze, commit a tag"
  python3 - "$VERSION" "$NEW_BUILD" <<'PY'
import re, sys, pathlib
version, build = sys.argv[1], sys.argv[2]
path = pathlib.Path("release.env")
text = path.read_text()
text = re.sub(r'^APP_VERSION=.*$', f'APP_VERSION={version}', text, flags=re.M)
text = re.sub(r'^APP_BUILD=.*$', f'APP_BUILD={build}', text, flags=re.M)
path.write_text(text)
PY
  git add release.env
  git commit --quiet -m "Release Revision $VERSION"
  git tag "v$VERSION"
  git push --quiet origin main "v$VERSION"
  note "APP_VERSION=$VERSION, APP_BUILD=$NEW_BUILD, tag v$VERSION odeslán"
fi

step "Sestavení, notarizace a appcast"
if [[ -f "dist/releases/v$VERSION/.ready" ]]; then
  note "už připraveno, přeskakuji"
else
  [[ ! -e "dist/releases/v$VERSION" ]] || fail "dist/releases/v$VERSION existuje, ale není dokončené. Smažte jej a spusťte znovu."
  if $FIRST; then bash scripts/release.sh prepare --first-release; else bash scripts/release.sh prepare; fi
fi

step "Nahrání draftu"
if released_on_github "$VERSION"; then
  note "vydání už na GitHubu existuje, přeskakuji"
else
  bash scripts/release.sh upload
fi

cat <<DONE

✓ Draft Revision $VERSION je na GitHubu.

  Zbývá:
  1. Vyzkoušet aktualizaci z předchozí verze na tento build.
  2. bash scripts/new-release.sh publish
DONE
