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

## Značka

Logo, ikona a paleta jsou v `Design/` (`Logo.png`, `AppIcon-source.png`, `ColorPalette.png`).
Akcentová barva aplikace je Primary Blue `#197BFF` (v tmavém režimu `#4C9DFF`), celá paleta je v `MacGit/Views/Components/Brand.swift`.

## Struktura

- `Packages/GitKit` – veškerá práce s gitem (spouští systémový `git`), parsery, hosting API. Testy: `cd Packages/GitKit && swift test`
- `MacGit/Model` – `AppStore` (prostory, projekty, účty), `RepositoryModel` (stav otevřeného repozitáře)
- `MacGit/Views` – SwiftUI

## Build

```bash
xcodegen generate
xcodebuild -project Revision.xcodeproj -scheme Revision -derivedDataPath build build
open build/Build/Products/Debug/Revision.app
```

Aplikace záměrně neběží v sandboxu (spouští `git`, `ssh`, `gpg`).
