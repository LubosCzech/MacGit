---
name: revision-release
description: Vydání nové verze Revision přes Sparkle a GitHub Releases (testy, tag, notarizace, draft, publish). Použij, když uživatel chce vydat verzi, připravit release notes nebo řeší spadlé vydání.
---

# Vydání Revision

Podrobnosti: `Docs/Vydavani.md`. Vydání **spouští uživatel** – ty připravíš podklady, vysvětlíš kroky a pomůžeš s chybami. Push, tag, upload ani publish nedělej bez výslovného pokynu.

## Bezpečnostní pravidla (nikdy neporušit)

- Soukromý Sparkle klíč je v Klíčence (účet `revision-updates`) – nikdy ho nečti, nekopíruj do projektu ani chatu.
- Neměň `GITHUB_REPOSITORY`, `SPARKLE_PUBLIC_ED_KEY`, `SPARKLE_KEY_ACCOUNT`, bundle ID `cz.svetik.Revision` ani `APPLE_TEAM_ID` – rozbilo by to aktualizace všem instalacím.
- Hesla k notarizaci jsou v profilu `nimbo-notary` (notarytool) – nezadávej je.
- Publikované archivy a podepsaný appcast se nikdy neupravují ručně. Oprava = vyšší build.

## Postup

1. **Poznámky:** aktualizuj `RELEASE_NOTES.md` v kořeni – první řádek `# Revision <verze>`, česky, pro uživatele (co je nového, ne seznam commitů). Ukaž uživateli ke schválení.
2. **Čistá pracovní kopie na `main`** – uživatel commitne sám.
3. Uživatel spustí **z kořene projektu**:
   ```bash
   cd ~/Projekty/AI/MacGit
   bash scripts/new-release.sh <verze>
   ```
   Skript: testy (`scripts/run-tests.sh`), zvýšení `APP_BUILD`, commit verze, tag `v<verze>` + push tagu, build universal, podpis Developer ID, notarizace + staple, DMG, podepsaný appcast, draft na GitHubu.
4. Ověřit aktualizaci z předchozí verze (nainstalovaná v /Applications → Zkontrolovat aktualizace).
5. `bash scripts/new-release.sh publish` → Latest + kontrola veřejného feedu.
6. Kontrola: `bash scripts/new-release.sh status`, `gh release list --repo LubosCzech/MacGit`, `curl -sIL https://github.com/LubosCzech/MacGit/releases/latest/download/appcast.xml` (200).

## Když to spadne

- Přerušené vydání se dokončí **stejným příkazem se stejnou verzí** – hotové kroky se přeskočí.
- „No such file or directory“ → spuštěno mimo kořen projektu.
- Publish spadl v závěrečné kontrole (např. 404 hned po zveřejnění) → nejdřív `gh release list`; vydání často už je venku a v pořádku.
- Chyba notarizace → `xcrun notarytool log <id> --keychain-profile nimbo-notary`.
- Novou zkušenost zapiš do sekce „Zkušenosti“ v `Docs/Vydavani.md`.
