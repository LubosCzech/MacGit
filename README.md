# Revision

*See changes. Build with confidence.*

Nativní git klient pro macOS 26+ (SwiftUI, Liquid Glass), české UI. Dříve pracovní název MacGit.

## Funkce

- **Prostory** – vlastní skupiny repozitářů (Práce, Soukromé…) s ikonou a barvou; přepínač v postranním panelu, přesun přetažením nebo přes kontextové menu.
- **Projekty** si pamatují cestu, prostor a způsob přihlášení (`~/Library/Application Support/Revision/state.json`).
- **Changelisty** (styl JetBrains) – aktivní changelist, přesun souborů přetažením, zaškrtávání souborů do commitu.
- **Commit jen vybraných souborů** (`git commit --only`), Amend, Commit a Push.
- **Shelf** – změny se uloží jako binární patch a vrátí z pracovního stromu; obnovení do changelistu stejného jména.
- **Podpis a identita** per repozitář – `user.name/email`, podepisování GPG / SSH / X.509.
- **Přihlášení** – systémové (ssh-agent), konkrétní SSH klíč (+ passphrase), token účtu GitHub/GitLab, uživatel + heslo. Tajné údaje jsou v Klíčence, do gitu se předávají přes `GIT_ASKPASS` / `SSH_ASKPASS`.
- **GitHub / GitLab** (i self-hosted) – ověření tokenu, výpis a klonování repozitářů, nahrání SSH klíče, odkaz na nový PR/MR.
- Historie s diffy, větve (checkout, merge, přejmenování, mazání i na serveru), remoty, generování Ed25519 klíčů, sledování změn přes FSEvents.
- **Push do…** libovolného remotu (např. občasná verze do zrcadla na GitLabu) bez změny upstreamu.
- **AI review** větví a commitů přes CLI agenty, návrh commit zprávy přes Apple Intelligence.
- **Zálohy konfigurace** – automaticky denně, ručně do souboru, hesla volitelně šifrovaná.

## Značka

Logo, ikona a paleta jsou v `Design/` (`Logo.png`, `AppIcon-source.png`, `ColorPalette.png`).
Akcentová barva aplikace je Primary Blue `#197BFF` (v tmavém režimu `#4C9DFF`); syrová paleta je v `MacGit/Views/Components/Brand.swift`.

Vzhled řídí sémantické tokeny v `MacGit/Views/Components/Theme.swift` – každý se sám překlápí mezi světlým a tmavým tématem (dynamická `NSColor`), takže v pohledech není žádné větvení podle schématu. Sklo (Liquid Glass) patří jen do ovládací vrstvy, obsah (diff, seznamy) zůstává neprůhledný. Kompletní návrh UI/UX je v [Docs/UI-Spec.md](Docs/UI-Spec.md), pravidla a ověřené záseky v [Docs/UI-Liquid-Glass.md](Docs/UI-Liquid-Glass.md).

## Struktura

- `Packages/GitKit` – veškerá práce s gitem (spouští systémový `git`), parsery, hosting API. Testy: `cd Packages/GitKit && swift test`
- `MacGit/Model` – `AppStore` (prostory, projekty, účty), `RepositoryModel` (stav otevřeného repozitáře)
- `MacGit/Views` – SwiftUI

## Build

```bash
bash scripts/fetch-sparkle.sh   # jednou: ověřený Sparkle do Vendor/
xcodegen generate
xcodebuild -project Revision.xcodeproj -scheme Revision -derivedDataPath build build
open build/Build/Products/Debug/Revision.app
```

Testy všech sad najednou: `bash scripts/run-tests.sh`.

## Vydání a aktualizace

Aktualizace běží přes Sparkle (podepsaný appcast na GitHub Releases), aplikace se podepisuje Developer ID a notarizuje. Každé vydání má git tag `v<verze>`.

```bash
bash scripts/new-release.sh 1.0      # testy, commit verze, tag v1.0, build, notarizace, draft
bash scripts/new-release.sh publish  # zveřejnit až po vyzkoušení aktualizace
bash scripts/new-release.sh status   # kde vydání stojí
```

Podrobnosti v [Docs/Vydavani.md](Docs/Vydavani.md), poznámky k vydání v [RELEASE_NOTES.md](RELEASE_NOTES.md).

Aplikace záměrně neběží v sandboxu (spouští `git`, `ssh`, `gpg`).

## Dokumentace

Veškeré know-how (architektura, vývoj, UI, přihlášení, AI, zálohy, vydávání, deník rozhodnutí) je ve složce [Docs/](Docs/README.md).
