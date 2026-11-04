# Revision 1.1

## Novinky

- **Zálohy konfigurace** v Nastavení → Zálohy. Revision jednou denně uloží prostory, projekty, účty, changelisty, rozepsané commit zprávy, shelf a nastavení vzhledu a drží posledních 14 záloh. Složku můžeš přesunout třeba na iCloud Drive.
- Záloha se dá uložit i ručně do souboru, například pro přechod na nový Mac. Hesla a tokeny do ní můžeš volitelně přibalit, zašifrované heslem, které zadáš.
- Obnovení ze zálohy nejdřív uloží současný stav, takže jde vrátit, a pak Revision restartuje.

## Opravy

- SSH klíč vygenerovaný v Revision teď funguje i s přihlášením „Systémové“ a v terminálu. Nový klíč dostane výchozí název `id_ed25519` a na přání se zapíše do `~/.ssh/config`.
- V Nastavení → SSH klíče je u každého klíče vidět, jestli ho systém použije. Klíč s vlastním názvem jde jedním tlačítkem zapsat do `~/.ssh/config`.
- Výběr SSH klíče v dialogu klonování a v nastavení projektu už nehlásí prázdnou složku `~/.ssh`.
- Hlášení „Server odmítl SSH klíč“ srozumitelněji vysvětluje, co zkontrolovat.
