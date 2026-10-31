# Aktualizace Revision přes Sparkle

## Aktuální nastavení

- Repozitář: LubosCzech/MacGit (veřejný). Adresa aktualizací je od něj odvozená – **před prvním vydáním** případně přejmenujte repozitář a upravte GITHUB_REPOSITORY; po vydání už ji neměňte.
- Feed: https://github.com/LubosCzech/MacGit/releases/latest/download/appcast.xml – začne fungovat po prvním zveřejněném vydání.
- Sparkle 2.9.6, ověřená binárka ve Vendor/ (SHA-256 připnuté ve scripts/fetch-sparkle.sh), do aplikace se vkládá přes project.yml.
- RELEASE_MODE=notarized: Developer ID týmu Z47E3LBWRP, notarizační profil sdílený s Nimbem (nimbo-notary). Názvy jsou v gitem ignorovaném release.local.env.
- Veřejný Ed25519 klíč je v release.env, soukromý v přihlašovací Klíčence pod účtem revision-updates.
- Vývojové buildy z Xcode adresu aktualizací nemají (prázdné REVISION_FEED_URL), takže se nikdy samy neaktualizují. Doplňuje ji jen build.sh.

## Vydání nové verze

```sh
bash scripts/new-release.sh 1.0      # testy, tag v1.0, sestavení, notarizace, draft
# vyzkoušet aktualizaci z předchozí verze na ten build
bash scripts/new-release.sh publish  # teprve teď to uvidí uživatelé
```

`scripts/new-release.sh` obaluje `release.sh` a hlídá, na co se dá zapomenout: čistá pracovní kopie (tag musí ukazovat na kód, který se opravdu notarizoval), větev main, přihlášené `gh`, poznámky k vydání začínající správnou verzí, všechny testovací sady, zvýšení `APP_BUILD` a odeslání tagu. Publikování zůstává samostatný příkaz schválně — mezi draftem a zveřejněním patří ověření skutečné aktualizace.

Přerušené vydání (spadlá notarizace, výpadek sítě) se dokončí stejným příkazem se stejným číslem verze; hotové kroky se přeskočí. `bash scripts/new-release.sh status` ukáže, kde vydání stojí.

## Předpoklady

Sestavení vyžaduje macOS, Xcode se SDK 26+ a Python 3 z Command Line Tools. Příprava používá veřejné GitHub API, nevyžaduje přihlášení ani gh. Pro automatické upload/publish potřebujete GitHub CLI přihlášené přes gh auth login. Přihlášení v Safari nebo GitHub Desktop samo nepřihlásí GitHub CLI.

Klíč je již nastavený. Pro opětovné zobrazení veřejné části:

```bash
bash scripts/init-update-key.sh
```

Existující klíč se zachová. Soukromý klíč nikdy neukládejte do projektu ani chatu. Bezpečně jej zálohujte mimo repozitář podle [návodu Sparkle](https://sparkle-project.org/documentation/#eddsa-ed25519-signatures). Bez Apple podpisu nelze spoléhat na obnovu ztraceného klíče rotací přes Developer ID. Neměňte účet klíče ani veřejný klíč. Bundle ID je cz.svetik.Revision; neměňte ho bez migrace předvoleb, Klíčenky a Application Support (vzor: AppMigration.swift).

## Příprava vydání

V kořeni projektu aktualizujte RELEASE_NOTES.md. Pro každé další vydání zvyšte APP_VERSION i APP_BUILD v release.env; build je stále rostoucí kladné celé číslo.

První vydání:

```bash
bash scripts/release.sh prepare --first-release
```

Další vydání:

```bash
bash scripts/release.sh prepare
```

Příprava kontroluje veřejný repozitář, shodu klíče s Klíčenkou a rostoucí build proti předchozímu podepsanému appcastu. Sestaví universal aplikaci pro Intel i Apple Silicon, podepíše ji ad-hoc, ověří vnořené podpisy a připraví DMG a podepsaný appcast. V režimu adhoc nevolá notarizační služby Apple. Poznámky se vkládají přímo do podepsaného feedu včetně upozornění na chybějící notarizaci. Delta aktualizace jsou vypnuté.

Výsledek je v dist/releases/v<verze>/: DMG, appcast.xml, RELEASE_NOTES.md, release-mode.txt a SHA256SUMS. Skript nic nenahrává ani nevytváří tagy. Existující výstup se nepřepisuje. Při selhání zůstane neúplný výstup pro diagnostiku; před opakováním jej přesuňte stranou. Starší testovací DMG v dist/ bez nastaveného klíče nepoužívejte pro první Sparkle instalaci.

## Nahrání a zveřejnění

Po kontrole zdrojů je commitněte a nahrajte. V repozitáři vytvořte a pushněte tag v<APP_VERSION> odpovídající schváleným zdrojům. Příprava tag nevyžaduje, upload jeho existenci kontroluje a sám ho nevytváří.

```bash
bash scripts/release.sh upload
```

Vznikne draft s připravenými soubory. Již existující vydání se nepřepíše; při selhání přenosu nejprve zkontrolujte nedokončený draft. Po kontrole:

```bash
bash scripts/release.sh publish
```

Před zveřejněním se ověřují podpisy, délka a URL archivu, shoda režimu s konfigurací, součty i skutečně nahrané soubory. Skript odmítne starší build. Vydání označí jako Latest a ověří veřejný feed. Pokud selže až poslední síťová kontrola, vydání už může být zveřejněné — nejprve zkontrolujte GitHub/CDN.

Bez gh lze pět uvedených souborů vložit do draftu přes GitHub web. Neuploadujte celý projekt ani klíče. Ruční publikace nemá automatickou závěrečnou kontrolu skriptu.

Každé stabilní Latest vydání tohoto repozitáře musí obsahovat appcast. Jeho odkazy na DMG používají konkrétní neměnný tag. Staré release soubory zachovejte. Neupravujte publikované archivy ani podepsané XML ručně. Pro opravu vydejte vyšší build; změna Latest nezpůsobí downgrade již aktualizovaných klientů.

## Později: Developer ID a notarizace

1. Získejte certifikát Developer ID Application s privátním klíčem v Klíčence.
2. Interaktivně nastavte profil: xcrun notarytool store-credentials nimbo-notary. Hesla nezadávejte do projektu ani chatu.
3. V release.env nastavte RELEASE_MODE=notarized. Do ignorovaného release.local.env vložte pouze názvy:

```bash
REVISION_SIGN_IDENTITY="Developer ID Application: Vaše jméno (TEAMID)"
REVISION_NOTARY_PROFILE="nimbo-notary"
```

Team ID patří do veřejného release.env jako APPLE_TEAM_ID; je součástí každého podepsaného buildu, není to tajemství. Vydání se zastaví, pokud certifikát patří jinému týmu — podpis jiným týmem by uživatelům znovu zrušil všechna udělená oprávnění. Kontrola běží dvakrát: nad názvem identity před podepsáním a nad TeamIdentifier ve skutečně podepsaném bundlu.

4. Zachovejte stejný Sparkle klíč a feed. Zvyšte verzi/build a vydejte novou aplikaci. Přechod ověřte skutečnou aktualizací z ad-hoc verze.

Notarizovaný režim podepisuje pomocníky, framework a aplikaci Developer ID s Hardened Runtime. Notarizuje a stapluje aplikaci i DMG. MacGit/MacGit.entitlements zachovává síťový přístup; aplikace není v sandboxu, protože spouští git, ssh a gpg. Chybějící certifikát/profil nebo neúspěšná notarizace zastaví přípravu, nikdy se tiše nepřejde na ad-hoc.

Mac App Store je samostatná budoucí varianta, ne pouhá změna certifikátu. Aktualizace tam zajišťuje App Store, nikoli Sparkle. Sandbox a pravidla obchodu vyžadují přezkoumání funkcí úklidu a správy aplikací; schválení současné aplikace nelze předpokládat.

## Ověření

```bash
bash Tests/release-mode-tests.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
```

Test režimů simuluje podpisové nástroje bez kontaktování Apple. Kryptografický test používá dočasný klíč mimo Klíčenku a kopii aplikace; ověřuje platný feed/ZIP a odmítnutí pozměněných souborů. Nic nepublikuje ani neinstaluje. Generátor může vytvořit cache v ~/Library/Caches/Sparkle_generate_appcast.

End-to-end test potřebuje dvě vydání: nainstalujte starší nakonfigurované Revision do Applications (ne spouštět z DMG), zveřejněte vyšší build a ověřte poznámky, stažení, instalaci/restart, zachování nastavení a systémových oprávnění. Otestujte aktuální verzi, offline síť, zrušení aktualizace, Intel/Apple Silicon a nejstarší podporovaný macOS. Revision bez nakonfigurovaného Sparkle vyžaduje první ruční instalaci.

## Zdroje

- [Sparkle: nastavení a podpisy](https://sparkle-project.org/documentation/)
- [Apple: bezpečné otevírání aplikací](https://support.apple.com/en-us/102445)
- [Pravidla App Store](https://developer.apple.com/app-store/review/guidelines/)
