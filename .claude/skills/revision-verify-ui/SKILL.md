---
name: revision-verify-ui
description: Sestaví a spustí Revision (macOS git klient) a ověří změnu UI v běžící aplikaci – v obou stylech rozhraní (Revision / Klasický) a obou tématech. Použij po každé změně v MacGit/Views nebo když uživatel hlásí vizuální chybu.
---

# Ověření UI v Revision

Změna UI není hotová, dokud ji neuvidíš v běžícím okně. Kompilace nestačí.

## 1. Build a spuštění

```bash
cd ~/Projekty/AI/MacGit
xcodegen generate                      # jen když přibyl/zmizel soubor
xcodebuild -project Revision.xcodeproj -scheme Revision -derivedDataPath build build -quiet
pkill -x Revision; sleep 1
open build/Build/Products/Debug/Revision.app
```

Pozor: vývojový build sdílí data s vydanou verzí v /Applications (skutečná konfigurace uživatele). Před destruktivním testem (obnova zálohy, migrace) zkopíruj `~/Library/Application Support/Revision` a `defaults export cz.svetik.Revision` do scratchpadu.

## 2. Prohlédnutí

- Screenshot **celého okna** (computer-use `app_screenshot` aplikace Revision), ne výřez.
- Porovnej s návrhem na plátně https://claude.ai/artifact/NPRcnoi7LYPhjHAzitHUqj a s `Docs/UI-Spec.md`.
- Projdi všechny čtyři sekce (⌘1–4) – **po přepnutí sekce** zkontroluj, že nad seznamem není prázdná díra (viz `Docs/UI-Liquid-Glass.md`).
- Odroluj seznam pod horní i spodní lištu: obsah se má pod horní lištou měkce rozostřit (bez tónu, bez karty) a nad commit panelem vyblednout, bez tvrdé linky.
- Přepni styl (Nastavení → Vzhled → Styl rozhraní) a téma (světlé/tmavé) a zopakuj.
- Při zamčené obrazovce: `build/Build/Products/Debug/Revision.app/Contents/MacOS/Revision --snapshots <scratchpad>/snaps [--dark] [--width 1400]` (sklo se do těchto PNG nevykreslí).

## 3. Co nástroje neumí

Psát do `SecureField` a ovládat `NSOpenPanel`/`NSSavePanel`. Takové kroky přesně popiš uživateli k ručnímu vyzkoušení – neodhaduj výsledek.

## 4. Když něco nesedí

Nehádej – změř. Dočasně zaloguj geometrii (`onGeometryChange`, `NSScrollView.contentInsets`, výšky řádků) a teprve podle čísel opravuj. Pak logování odstraň.

## 5. Závěr

Uživateli ukaž screenshot a napiš, co bylo ověřeno a co ne. Testy GitKitu: `swift test --package-path Packages/GitKit`. Necommituj – commit dělá uživatel.
