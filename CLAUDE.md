# Revision (složka MacGit)

Nativní git klient pro macOS 26+ (SwiftUI, Liquid Glass, Swift 6), **české UI**. Veškeré know-how je v [Docs/](Docs/README.md) – před větší změnou si přečti příslušný dokument.

- Architektura a data na disku: `Docs/Architektura.md`
- Build, testy, ověřování, konvence: `Docs/Vyvoj.md`
- UI pravidla a ověřené záseky SwiftUI: `Docs/UI-Liquid-Glass.md` (+ skill `revision-ui-change`)
- Proč je co udělané a co uživatel odmítl: `Docs/Rozhodnuti.md`

## Rychle

```bash
xcodegen generate && xcodebuild -project Revision.xcodeproj -scheme Revision -derivedDataPath build build -quiet
swift test --package-path Packages/GitKit
```

## Pravidla

- `Revision.xcodeproj` se generuje z `project.yml` – needitovat ručně.
- Každou změnu UI ověř v běžící aplikaci v obou stylech a tématech (skill `revision-verify-ui`).
- Testovatelná logika patří do `Packages/GitKit` a dostane test.
- Tajné údaje jen v Klíčence. Sparkle klíč (Klíčenka, účet `revision-updates`) nikdy nečíst ani nekopírovat.
- Necommitovat, nepushovat, netagovat a nevydávat bez výslovného pokynu uživatele. Repozitář, bundle ID ani adresu feedu neměnit.
- Nové know-how (zásek, rozhodnutí, postup) zapiš do příslušného souboru v `Docs/`.
