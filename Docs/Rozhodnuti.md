# Deník rozhodnutí a zpětné vazby

Proč je něco udělané právě takhle a co už bylo zkoušeno a odmítnuto. Nejnovější nahoře. Než něco „zjednodušíš“, podívej se sem.

## 2026-11-04 · SSH klíč na novém Macu
- Klíč vygenerovaný v Revision (`id_ed25519_macgit`) nefungoval se „Systémovým“ přihlášením – ssh vlastní názvy sám nezkouší. Revision teď nabízí výchozí název a umí klíč zapsat do `~/.ssh/config` (s výslovným přepínačem / tlačítkem, protože jde o soubor mimo Revision).
- Opravena chyba prázdného výběru klíčů v dialogu klonování a v inspektoru.

## 2026-11-01 · Zálohy konfigurace
- Tajné údaje v záloze jen volitelně a jen šifrované heslem; automatické zálohy je nikdy neobsahují.
- Obnova přes restart aplikace, ne přenačtení za běhu – spolehlivější pro všechna okna a cache modelů.
- SSH klíče z `~/.ssh` se nezálohují – jsou mimo správu Revision a jejich kopírování do jednoho souboru je riziko.
- Detaily: [Zalohy.md](Zalohy.md).

## 2026-10-31 · První vydání v1.0
- Vydávání převzaté z Nima (Sparkle, notarizace, `new-release.sh`). Publikování je záměrně samostatný krok (draft → ověřit aktualizaci → publish).
- Repozitář LubosCzech/MacGit a bundle `cz.svetik.Revision` zůstávají – po vydání už se nemění (adresa feedu je zapečená v instalacích).
- Opraveny dvě chyby skriptů (detekce prvního vydání, 404 při pollingu). Detaily: [Vydavani.md](Vydavani.md).

## 2026-10 · Push do… a GitLab
- Uživatel má hlavní repozitář na GitHubu (origin) a občas posílá verzi do GitLabu. Řešení: „Push do…“ s výběrem remotu, upstream se nemění.
- Tokeny/hesla projektu se nikdy neposílají cizímu hostu (bezpečnost > pohodlí).
- Chráněnou větev na GitLabu uživatel vyřešil sám (unprotect); aplikace jen srozumitelně hlásí příčinu.
- Identita/podpis podle remotu: **nedělat**, uživatel to nepotřebuje (má druhý e-mail u účtu).

## 2026-09-25 · Distribuce
- Sparkle 2.9.6 jako ověřená binárka ve `Vendor/` s připnutým SHA-256 (ne SwiftPM – stejný postup jako Nimbo).
- Kontroly aktualizací volitelné a výchozí vypnuté, instalaci vždy potvrzuje uživatel; vývojové buildy feed nemají.
- Buy Me a Coffee (`buymeacoffee.com/svtkdev`): dotaz po týdnu, pak nejvýš 1× měsíčně; po „Podpořil jsem“ nebo otevření stránky už nikdy – zaplacení nejde ověřit, takže věříme uživateli. About = vlastní `NSPanel` (`AboutWindow.swift`), odkaz na svtk.dev.

## 2026-09-19/20 · Lišty nad obsahem a díra nad seznamem
- Uživatel chtěl lišty „poloprůhledné jako v Mailu“: **ne karta**, **ne tón** („barva musí zůstat stejná“). Výsledek: lišta bez pozadí + systémový scroll edge effect.
- Odmítnuto: skleněná karta kolem hlavičky, `.ultraThinMaterial`, vlastní blur přes `backgroundFilters`.
- Díra nad seznamem se vracela přes mnoho pokusů (safeAreaInset, VStack, nulování insetů, probe pohledy, přednastavené insety) – uživatel opakovaně reklamoval („pořád rozbité“, poslal video z Apple aplikace). Skutečnou příčinu odhalilo až **měření** (0. řádek Listu 97 pt u Listu vytvořeného za běhu). Ponaučení: u vizuálních chyb nejdřív změřit, pak opravovat. Detaily: [UI-Liquid-Glass.md](UI-Liquid-Glass.md#prázdná-díra-nad-seznamem).
- Commit panel dostal stejný styl jako horní lišta (bez karty, pole skleněná, Commit jako split button přes celou šířku).

## 2026-09-18 · Dva styly rozhraní
- Uživatel chtěl kromě značkového vzhledu i „classic mode – čistý Apple Liquid Glass podle HIG, jako by aplikace byla systémová“. Proto `InterfaceStyle` a všechny sdílené pohledy přes adaptivní modifikátory a tokeny.

## 2026-09-18 · Vlastní kostra okna
- První implementace redesignu na `NavigationSplitView` uživatel odmítl: „vůbec není podobné UI návrhu… rozdílná pozadí v každé části (má být jedno pro celou aplikaci)… vrchní toolbar vypadá úplně jinak“. Proto `WindowShell` – jedno plátno, jeden toolbar.
- Hlavička sloupce: žádné logo aplikace u každého repozitáře, žádné zbytečné mezery, přepínač strom/seznam v menu ⋯.
- Ponaučení: hotovou fázi vždy porovnat jako **celé okno** vedle návrhu, ne výřezy.

## 2026-09-17 · Přejmenování MacGit → Revision
- Slogan „See changes. Build with confidence.“, bundle `cz.svetik.Revision`, migrace dat ze starého ID (Application Support, Klíčenka, předvolby). Složka a GitHub repozitář zůstaly `MacGit`.

## 2026-09-16/17 · Základ
- Vlastní náhrada za Sourcetree / GitHub Desktop. Systémový `git` místo libgit2 (stejné chování jako v terminálu, podpisy, hooks, LFS). Bez sandboxu.
- AI review přes CLI agenty uživatele v dočasném worktree (žádné vlastní API klíče, nic se nesahá na pracovní kopii). Commit zprávy přes Apple Intelligence na zařízení.
