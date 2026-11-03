# Vývoj

## Prostředí

- macOS 26+, Xcode se SDK 26+, Swift 6, [xcodegen](https://github.com/yonaskolb/XcodeGen).
- Projekt `Revision.xcodeproj` se **generuje** z `project.yml` – ruční změny v .xcodeproj se přepíšou. Nový soubor ve `MacGit/` stačí přidat a spustit `xcodegen generate`.
- Sparkle je ověřená binárka ve `Vendor/` (gitignorováno) – na čistém klonu nejdřív `bash scripts/fetch-sparkle.sh`.

## Build a spuštění

```bash
bash scripts/fetch-sparkle.sh   # jednou
xcodegen generate
xcodebuild -project Revision.xcodeproj -scheme Revision -derivedDataPath build build -quiet
open build/Build/Products/Debug/Revision.app
```

- Před spuštěním nového buildu ukonči běžící instanci (`pkill -x Revision`), jinak `open` jen přenese do popředí starou.
- Vývojový build má prázdné `REVISION_FEED_URL`, takže se nikdy neaktualizuje z vydaných verzí. Vydaná verze v `/Applications` a vývojový build sdílí **stejná data** (Application Support, Klíčenka, UserDefaults) – testy na vývojovém buildu sahají na skutečnou konfiguraci uživatele.
- Před experimenty se zálohami/obnovou nebo migrací si udělej bezpečnostní kopii: `~/Library/Application Support/Revision` + `defaults export cz.svetik.Revision`.

## Testy

```bash
swift test --package-path Packages/GitKit   # GitKit (31 testů k 1. 11. 2026)
bash scripts/run-tests.sh                   # vše: GitKit, build aplikace, appcast, režimy podpisu
```

- Testy GitKitu vytvářejí dočasné repozitáře, nic nesahají na data uživatele.
- Živý test AI review (volá skutečného agenta):
  `MACGIT_LIVE_REVIEW="${repo}:branch:base:agent:model" swift test --package-path Packages/GitKit --filter LiveAgentReviewTests`
  V zsh používej `${repo}` – zápis `$D:f…` je modifikátor historie.

## Ověřování UI

Každou změnu UI je potřeba vidět v běžící aplikaci, ne jen zkompilovat. Postup a kontrolní seznam je ve skillu `.claude/skills/revision-verify-ui`.

- **Porovnávej celé okno**, ne výřezy – vedle návrhu na plátně, v obou stylech (Revision / Klasický) a v obou tématech.
- Snímky při zamčené obrazovce (jen DEBUG build):
  `build/Build/Products/Debug/Revision.app/Contents/MacOS/Revision --snapshots <složka> [--width 1400] [--dark]`
  Uloží PNG všech sekcí + inspektoru a `.txt` s rozložením. **Skleněné vrstvy se do těchto PNG nevykreslí** – na sklo je potřeba skutečný screenshot okna.
- Ovládání přes computer-use: do `SecureField` nástroje psát nesmí a systémové `NSOpenPanel`/`NSSavePanel` ovládat nejdou – tyhle části musí vyzkoušet uživatel.
- Na skryté chyby rozložení pomáhá dočasné logování geometrie (`onGeometryChange`, výpis `NSScrollView.contentInsets`) – tak se našla příčina „díry nad seznamem“.

## Konvence

- **České UI**, texty přímo v kódu (žádné lokalizační soubory, `developmentLanguage: cs`). Komentáře také česky, stručně a k věci – vysvětlují *proč*, ne *co*.
- Každá akce z toolbaru má i položku v menu baru a ideálně zkratku (`MacGitApp.swift`, `Commands`).
- Barvy jen přes tokeny `Theme.*`, tlačítka a karty ve sdílených pohledech přes `.adaptiveButtonStyle()` / `.adaptiveCard()` – nikdy `.glass` natvrdo. Viz [UI-Liquid-Glass.md](UI-Liquid-Glass.md).
- Logika, která jde testovat bez UI, patří do GitKitu a dostane test.
- Tajné údaje jen v Klíčence (`Keychain`), nikdy v souborech, logu ani v chatu.
- Commit dělá uživatel sám, pokud výslovně neřekne jinak. Push, tag a release jen na jeho pokyn.

## Klávesové zkratky (menu)

⌘1–4 sekce · ⌃⌘S postranní panel · ⌥⌘L změny jako strom · ⌥⌘I inspektor · ⌘F hledání · ⌘K filtr repozitářů · ⌘R obnovit · ⌘↩ commit · ⌥⌘↩ commit a push · ⌥⌘G navrhnout zprávu · ⌥⌘F fetch · ⌘T pull · ⇧⌘K push · ⇧⌘B nová větev · ⇧⌘R AI review · ⇧⌘N klonovat · ⌘O přidat existující.
