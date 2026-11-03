---
name: revision-ui-change
description: Pravidla pro psaní a úpravy SwiftUI v Revision (Liquid Glass, dva styly rozhraní, tokeny Theme, ověřené záseky macOS 26). Načti před každou změnou v MacGit/Views – nový pohled, lišta, seznam, toolbar, barvy.
---

# Změna UI v Revision

Plná pravidla a příčiny: `Docs/UI-Liquid-Glass.md`. Co uživatel už odmítl: `Docs/Rozhodnuti.md`.

## Kontrolní seznam před psaním

1. **Funguje v obou stylech?** Revision (`WindowShell`) i Klasický (`ClassicShell`). Ve sdílených pohledech:
   - barvy jen `Theme.*` (nikdy hex ani `if scheme == .dark`),
   - tlačítka `.adaptiveButtonStyle(prominent:)`, karty `.adaptiveCard()`, pole `.adaptiveFieldBackground()` – nikdy `.glass` natvrdo,
   - když se chování liší, `@Environment(\.interfaceStyle)`.
2. **Sklo jen v ovládací vrstvě.** Seznamy, diff a texty jsou neprůhledné. Bílý text jen na `Theme.accentFill`, ne na `accent`.
3. **Lišta nad/pod rolovaným obsahem** = `.glassHeader { }` / `.glassFooter { }` na rolovacím pohledu nebo sloupci. Bez vlastního pozadí, bez materiálu, bez tónu, bez karty.
4. **Seznamy nepřepínat přes `if`/`switch`.** List vytvořený za běhu pod `safeAreaBar` dostane prázdnou díru nahoře. Drž je všechny v `ZStack` a přepínej `opacity` + `allowsHitTesting` + `accessibilityHidden` (vzor: `RepositoryContentColumn`). Nenulovat `contentInsets`.
5. **Animace výběru**: `matchedGeometryEffect` s kapslí pod obsahem, ne `glassEffectID` (v LazyVStack/ToolbarItem nemorfuje). Respektuj `accessibilityReduceMotion`.
6. **Dynamické NSColor** providery `nonisolated` + `@Sendable` (jinak pád na render vlákně).
7. **Toolbar**: pořadí panel │ větev │ fetch·pull·push … hledání │ inspektor │ účet. Nová akce v toolbaru = i položka v menu baru (`MacGitApp.swift`) + zkratka + `.help` + `accessibilityLabel`. Zobrazovací volby patří do menu ⋯ ve sloupci, ne do toolbaru.
8. **NavigationSplitView** jen v `ClassicShell`. Styl Revision má jedno plátno a jeden toolbar přes celé okno.
9. Texty česky, stručně, tykání („Zálohovat teď“, „Vybrat zálohu…“).

## Po napsání

Spusť skill `revision-verify-ui` a ověř změnu v obou stylech a tématech. Pokud jsi narazil na nový zásek SwiftUI, zapiš ho do `Docs/UI-Liquid-Glass.md` (příznak → příčina → oprava → co nefunguje).
