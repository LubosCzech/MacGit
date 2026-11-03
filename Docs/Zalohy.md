# Zálohy konfigurace

Nastavení → **Zálohy** (`BackupSettingsView`), logika v `MacGit/Services/BackupService.swift`, formát a šifrování v `Packages/GitKit/Sources/GitKit/ConfigBackup.swift` (testy `ConfigBackupTests`).

## Co záloha obsahuje

- `state.json` – prostory, projekty, účty (bez tokenů), výběr,
- `workspaces/<id>.json` – changelisty, rozepsané commit zprávy, historie AI review,
- `shelves/<id>/<shelf>.patch`,
- vybrané předvolby (`BackupService.preferenceKeys`: vzhled, styl rozhraní, strom/seznam, režim diffu, šířky a viditelnost sloupců, Push s tagy, agent a model review, stav dotazu na podporu),
- **volitelně** tajné údaje z Klíčenky (tokeny účtů, hesla projektů, passphrase SSH klíčů) – jen zašifrované heslem.

**Neobsahuje:** SSH klíče z `~/.ssh`, globální git config, samotné repozitáře, cestu ke složce záloh (vázaná na konkrétní Mac). Na jiném Macu musí projekty ležet ve stejných cestách, jinak je Revision označí jako nenalezené.

## Formát `.revisionbackup`

JSON (`ConfigBackup`, `format: 1`): `createdAt`, `appVersion`, `files: [relativní cesta: Data(base64)]`, `preferences: [klíč: PreferenceValue]`, `secrets: EncryptedSecrets?`.

- `PreferenceValue` rozlišuje bool/int/double/string/date – Bool se pozná přes `CFBooleanGetTypeID`, NSNumber z UserDefaults to sám neřekne.
- Soubory záloh se zapisují s právy **0600** (obsahují cesty k projektům a případně šifrovaná hesla).
- Novější `format` než umí aplikace → `BackupError.newerFormat` (nic se neobnoví). Při změně formátu zvýšit `currentFormat` a umět načíst starší.

## Šifrování tajných údajů (`EncryptedSecrets`)

- PBKDF2-HMAC-SHA256 (CommonCrypto), **600 000 iterací**, náhodná 16B sůl → 256bit klíč → **AES-256-GCM** (CryptoKit, `combined` = nonce + text + tag).
- Iterace se ukládají do souboru; při čtení se přijme jen rozsah 100 000 – 10 000 000 (podvržený soubor nemůže vynutit slabé nebo nekonečné odvození).
- Špatné heslo i poškozená data → `wrongPassword`. Heslo nejde obnovit – bez něj se tajné údaje z té zálohy nepřečtou.
- V UI: heslo aspoň 8 znaků, zadané dvakrát.

## Ochrana při obnově

Podvržený soubor zálohy nesmí zapsat nikam mimo Revision:

- `ConfigBackup.isAllowedPath` povolí jen `state.json`, `workspaces/<x>.json`, `shelves/<id>/<soubor>`; odmítne absolutní cesty, `..`, `.`, prázdné části, `\` a `\0`. Kontroluje se už při dekódování (`unsafePath`) i těsně před zápisem.
- `ConfigBackup.isAllowedSecretKey` povolí jen `account.<uuid>`, `project.<uuid>.password`, `ssh./…`.
- Předvolby se obnoví jen z whitelistu `preferenceKeys`.

## Postup obnovy (`BackupService.restore`)

1. Nejdřív rozšifrovat tajné údaje – **se špatným heslem se nesmí přepsat nic**. Bez hesla se obnoví konfigurace bez tajných údajů (Klíčenka zůstane, jak je).
2. Bezpečnostní záloha současného stavu `Revision-pred-obnovou-<čas>.revisionbackup` – obnova jde vrátit.
3. `store.suspendPersistence()` – zastaví ukládání `AppStore` i všech `RepositoryModel`, jinak by starý stav v paměti přepsal obnovené soubory.
4. Smazat a znovu vytvořit `workspaces/` a `shelves/`, zapsat soubory, předvolby, Klíčenku.
5. Restart: `/bin/sh -c "sleep 1; open <bundle>"` + `NSApp.terminate`. Restart je nejjistější způsob, jak načíst obnovený stav do všech oken.

## Automatické zálohy

- Výchozí zapnuto (`backup.automatic`), složka `backup.folder` (výchozí `Application Support/Revision/Backups`, doporučení: iCloud Drive / externí disk).
- `runAutomaticBackupIfDue`: 10 s po startu a pak každou hodinu (`.task` v `MacGitApp`), záloha vznikne, pokud od poslední uběhlo ≥ 23 h. Vždy **bez** tajných údajů.
- Soubory `Revision-auto-<yyyy-MM-dd-HHmmss>.revisionbackup`, drží se posledních **14** (řazení podle názvu = podle času). Ruční „Zálohovat teď“ (`Revision-<čas>`) a bezpečnostní zálohy se nemažou.
- Před zálohou `store.flushPendingSaves()` zapíše odložené změny. Vedlejší efekt: vytvoří workspace soubor i pro projekty, které ho dosud neměly (prázdný výchozí).

## Ověření (1. 11. 2026)

- 7 testů formátu/šifrování (špatné heslo, poškozený soubor, nepovolená cesta, novější formát, token není v souboru čitelný…).
- Automatická záloha na skutečných datech: 25 souborů bajtově shodných s diskem, 11 předvoleb, bez tajných údajů.
- **Ručně neověřeno** (nástroje neumí psát do `SecureField` ani ovládat `NSOpenPanel`/`NSSavePanel`): export s hesly a celé obnovení včetně restartu. Nejjednodušší test: obnovit čerstvou automatickou zálohu.
