# Revision — návrh UI/UX (macOS 26, Liquid Glass)

Podklady: návrh hlavního okna (mockup z 17. 9. 2026), `Design/ColorPalette.png`, `Design/Logo.png`. Mockup ulož prosím do `Design/Mockup-Main.png`, ať je součástí repozitáře.
Cíl: aplikace jako výstavní skříň Apple Liquid Glass — plné světlé i tmavé téma, fluidní animace tam, kde nesou význam.

---

## 1. Vrstvy (základní pravidlo celého návrhu)

Liquid Glass patří do navigační a ovládací vrstvy, nikdy do obsahu. Celá aplikace se drží tří vrstev:

| Vrstva | Co do ní patří | Materiál |
|---|---|---|
| **Plátno** | pozadí okna a sloupců | značkový gradient (`RevisionSurface`), bez skla |
| **Obsah** | seznamy souborů/commitů, diff, texty inspektoru | neprůhledné plochy, jemné obrysy, žádné sklo |
| **Ovládání / navigace** | toolbar, přepínače sekcí, plovoucí lišty, commit panel, karty akcí, výběr v postranním panelu | `.glassEffect(.regular[.tint][.interactive])` |

Důsledek: diff a seznamy zůstanou perfektně čitelné, sklo se objevuje jen tam, kde se něco ovládá — přesně jak to dělá systém.

---

## 2. Barevné tokeny (světlo i tma z jednoho zdroje)

Dnešní `Brand` je seznam konstant a `RevisionSurface` řeší téma `if scheme == .dark`. Nahradíme to sémantickými tokeny, které se samy překlápí (`NSColor(name:dynamicProvider:)` → `Color`), takže ve views už žádné větvení podle schématu není.

| Token | Světlé | Tmavé | Použití |
|---|---|---|---|
| `canvas` | `#EAF3FF` (Frosted Surface) | `#0E1630` (Midnight Navy) | pozadí okna |
| `canvasBloom` | Primary Blue 6 %, Cyan 7 % | Cobalt 12 %, Indigo 8 % | nasvícení gradientu v rozích |
| `surface` | bílá 92 % | `#141C33` | karty, hlavičky, commit panel |
| `surfaceRaised` | bílá | `#182140` | vybraný řádek, pole |
| `hairline` | `#D8E2F0` (Mist Gray) | bílá 8 % | obrysy 0,5 pt |
| `textPrimary` | `#111827` (Text Dark) | `#ECF2FF` | hlavní text |
| `textSecondary` | Text Dark 62 % | `#ECF2FF` 60 % | cesty, popisky |
| `accent` | `#197BFF` (Primary Blue) | `#4C9DFF` | akce, výběr, značka |
| `accentDeep` | `#0F52E8` (Cobalt) | `#3F44F4` (Indigo) | gradienty, AI prvky |
| `highlight` | `#63D7FF` (Cyan Accent) | `#63D7FF` | zvýraznění, badge AI |
| `diffAdd` / `diffAddText` | `#E4F7EA` / `#1B7F3B` | `#16351F` / `#7EE2A0` | diff přidáno |
| `diffRemove` / `diffRemoveText` | `#FDEAEC` / `#B42334` | `#3A1A20` / `#FF9AA5` | diff smazáno |
| `statusM/A/D/R/U` | jantar / zelená / červená / modrá / šedá | totéž zesvětlené | odznaky stavu souboru |

Pravidla: akcent v tmavém režimu je zesvětlený `#4C9DFF`, aby proti navy držel kontrast ≥ 4,5 : 1; barevné plochy diffu nesou význam i bez barvy (znaménko `+`/`−` a odznak).
Volba tématu (`RevisionAppearance`: systém / světlé / tmavé) se dotáhne do nastavení a platí pro všechna okna.

---

## 3. Plátno

`RevisionSurface` se překreslí na dvouvrstvý gradient: základní `canvas` + dvě měkké radiální „záře" (accent vlevo nahoře, highlight vpravo dole) v opacitě 6–12 %. Záře se velmi pomalu (30 s, lineárně, plynule tam a zpět) posouvá o pár procent — pod sklem to vytvoří živou refrakci, aniž by to rušilo. Vypíná se při Reduce Motion, Low Power a Reduce Transparency (pak zůstane plochá barva).

---

## 4. Toolbar

Pořadí zleva: **⧉ přepínač panelu │ větev + synchronizace │ hledání + zobrazení + účet**. Tři skupiny = strop podle HIG.

- **Větev** — skleněná kapsle: ikona větve, název, chevron; menu s lokálními větvemi, „Nová větev…", „Zobrazit všechny".
- **Fetch / Pull / Push** — jedna skupina kulatých skleněných tlačítek s odznaky (`ahead`/`behind`). Fetch při běhu rotuje (`.symbolEffect(.rotate)`), po dokončení `.bounce`; čísla odznaků se mění přes `.contentTransition(.numericText())`.
- **Hledání** — skleněný orb s lupou, po kliknutí se roztáhne na pole (244 pt). Oproti dnešku se nebude prohazovat `if`/`else` (to neanimuje), ale poroste jedna kapsle: šířka + opacita obsahu v jedné `matchedGeometry` scéně. ⌘F otevře, Esc zavře, prázdné pole se po ztrátě fokusu samo sbalí.
- **Zobrazení** (ikona posuvníků z mockupu) — menu: strom složek, ignorované/nesledované soubory, řazení, hustota řádků. Nahradí dnešní osamocené tlačítko u přepínače sekcí.
- **Účet** — kulatý skleněný avatar (iniciály, když není obrázek): stav přihlášení k GitHub/GitLab, rychlý přechod do Nastavení. Přihlášené účty už v aplikaci existují, jen je zviditelníme.

Diff přepínač (sjednocený / vedle sebe) zůstává v hlavičce detailu, kam patří kontextově — toolbar by jinak přetekl přes tři skupiny.

---

## 5. Postranní panel

```
┌ logo + „Revision"
├ 🔍 Filtrovat…                    ⌘K
├ ▾ Práce            (ikona + barva prostoru)
│    ⎇ AI tools
│    ⎇ demo-shop
├ ▾ Soukromé
│    ⎇ svtk.dev
├ ▾ AI apps
│    ⎇ Revision                6
└ + Přidat repozitář                 ↻
```

- **Hlavička**: ikona aplikace 44 pt + název 22 pt semibold (zůstává).
- **Filtr**: skleněná kapsle s klávesovou nápovědou `⌘K` vpravo; ⌘K fokusuje.
- **Prostory**: sbalitelné sekce se symbolem a barvou prostoru; drag & drop repozitářů beze změny.
- **Řádek repozitáře**: barevný symbol větve, název, odznak počtu změn v tónované kapsli; chybějící složka = oranžový trojúhelník.
- **Výběr**: tónovaná skleněná kapsle (`.regular.tint(accent)`), která **putuje** mezi řádky (`glassEffectID` v jednom `GlassEffectContainer`) — stejný jazyk jako přepínač sekcí.
- **Patička**: skleněné tlačítko „Přidat repozitář" (menu) + kulaté tlačítko obnovy všech repozitářů.

---

## 6. Prostřední sloupec

1. **Karta repozitáře** — ikona, název, zkrácená cesta, vpravo kulaté skleněné tlačítko s akcemi (Finder, Terminál, kopírovat cestu, nastavení projektu).
2. **Přepínač sekcí** — dnešní putující skleněná kapsle, vizuálně sladěná s mockupem: vybraná položka tónovaná akcentem, počet v sekci jako číslo za názvem (`Změny 6`) s `numericText` přechodem.
3. **Seznam souborů** — řádek: zaškrtávátko, ikona typu souboru, název (13 pt), pod ním cesta (11 pt, sekundární), vpravo odznak stavu `M/A/D/R` v tónovaném čtverečku 20×20. Skupiny = changelisty s hlavičkou. Vložení/odebrání řádku animuje pružinou, přepnutí strom/seznam plynulým `.smooth`.
4. **Commit panel** — plovoucí skleněná karta (r = 22) nad seznamem:
   - pole „Shrnutí" + kulaté tlačítko s jiskřičkou (gradient accent→accentDeep) pro AI návrh, počítadlo znaků,
   - pole „Popis (nepovinný)",
   - řádek autora s indikátorem podpisu + `Amend`,
   - hlavní tlačítko `Commit 6 souborů` (`.glassProminent`, akcent) se skrytým menu „Commit a Push".
   - Po úspěšném commitu tlačítko krátce zmorfuje na fajfku (`symbolEffect(.replace)`) a seznam se s pružinou složí.

---

## 7. Detail (diff)

- **Hlavička** — plovoucí skleněná lišta: ikona a název souboru, cesta pod ním, odznak stavu, vpravo skleněný segmentovaný přepínač sjednocený/vedle sebe a šipky na další/předchozí soubor (`⌥↑/⌥↓`).
- **Tělo** — obsahová vrstva: hunk hlavičky jako samostatný tónovaný pruh s `@@` rozsahem a kontextem, číselné sloupce monospace se sekundární barvou, řádky v `diffAdd`/`diffRemove`, slovní zvýraznění uvnitř řádku sytější variantou.
- **Přechody** — změna souboru = křížový prolnutí + drobný posun (8 pt), scroll okraje `.scrollEdgeEffectStyle(.soft)`, takže lišta „plave" nad textem.

---

## 8. Inspektor

Záložky jsou kontextové (mockup ukazuje variantu pro Změny):

| Sekce aplikace | Záložky inspektoru |
|---|---|
| Změny / Shelf | **Soubor · Review · Repozitář** |
| Historie / Větve | **Commit · Review · Repozitář** |

- **Soubor** — velká ikona, název, cesta, odznak stavu; `+12 −2` a `132 řádků` s poměrovým proužkem (nová komponenta `DiffStatBar`); mřížka údajů (poslední změna, autor, velikost); plnoširoké skleněné tlačítko „Zobrazit ve Finderu"; přepínač zahrnutí do commitu a výběr changelistu.
- **Review** — karta „AI Review" s gradientovou jiskřičkou a počtem nálezů; pod ní nálezy se stavovou ikonou (✅ zelená / ⚠️ jantarová / ℹ️ modrá), nadpisem a shrnutím; tlačítko „Zobrazit detailní analýzu" otevře dnešní okno review. Data vzniknou parsováním sekcí a závažnosti z výstupu agenta (prompt už sekce vynucuje), s fallbackem na surový Markdown.
- **Repozitář** — dnešní obsah (identita, podpis, přihlášení, remoty) přepsaný do stejných karet.
- **Značky** (z mockupu) — volitelná novinka: per-soubor štítky uložené ve workspace, klikací filtr do hledání. Navrhuji až jako poslední fázi, je to nová funkce, ne jen vzhled.

---

## 9. Katalog animací (vše vypnutelné přes Reduce Motion)

| # | Kde | Efekt |
|---|---|---|
| 1 | Přepínač sekcí, záložky inspektoru, výběr v panelu | putující skleněná kapsle (`glassEffectID`), pružina 0,38 s / tlumení 0,82 |
| 2 | Hledání | orb ⇄ pole — plynulá změna šířky s `bouncy` křivkou |
| 3 | Fetch / Pull / Push | rotace během běhu, `bounce` po dokončení, číselné odznaky `numericText` |
| 4 | Commit | tlačítko → fajfka, seznam se složí pružinou |
| 5 | Seznamy | vkládání/mizení řádků `scale(0.98) + opacity`, pružina |
| 6 | Diff | křížové prolnutí při změně souboru, měkké okraje scrollu |
| 7 | Inspektor | vysunutí skla + postupné (staggered) naskládání karet |
| 8 | Průběh operace | spodní skleněná kapsle s určitým průběhem u dlouhých operací |
| 9 | Prostory | plynulé sbalení sekce + rotace chevronu |
| 10 | Hover | `.interactive()` sklo na všech ovládacích prvcích |
| 11 | Přepnutí repozitáře | prolnutí obsahu, karta repozitáře se promorfuje |

---

## 10. Přístupnost

- Reduce Motion → bez putování a bez animovaného plátna (okamžité přepnutí).
- Reduce Transparency → sklo nahradí neprůhledné `surface` s obrysem.
- Increase Contrast → obrysy 1 pt, sekundární text o stupeň tmavší/světlejší.
- Každá akce v toolbaru má i položku v menu a klávesovou zkratku: `⌘1–4` sekce, `⌘K` filtr panelu, `⌘F` hledání, `⌥⌘I` inspektor, `⌘↩` commit, `⌥⌘↩` commit a push.
- Barva nikdy nenese informaci sama: stav souboru má písmeno, diff znaménko, review ikonu i text.

---

## 11. Postup implementace

| Fáze | Obsah | Soubory | Stav |
|---|---|---|---|
| 0 | Tokeny a plátno, volba tématu | `Theme.swift` (nový), `Brand.swift` | ✅ hotovo |
| 1 | Postranní panel | `SidebarView.swift` | ✅ hotovo |
| 2 | Prostřední sloupec, commit panel | `RepositoryColumns.swift`, `ChangesView.swift`, `CommitComposer.swift` | ✅ hotovo |
| 3 | Diff | `DiffView.swift` | ✅ hotovo |
| 4 | Inspektor + karta AI Review | `InspectorView.swift`, `ReviewInspector.swift` (nový), `ReviewViews.swift` | ✅ hotovo |
| 5 | Toolbar: větev, synchronizace, hledání, zobrazení, účet | `RepositoryColumns.swift`, `SearchOrb.swift`, `MacGitApp.swift` | ✅ hotovo |
| 6 | Doladění pohybu, kontrola přístupnosti, snímky v obou tématech | průřezově | ✅ kontrast a pohyb hotové, snímky fází 3–5 čekají na odemčenou obrazovku |
| 7 | (volitelně) Značky souborů | model + inspektor | ⏸ nezačato, je to nová funkce |

Každá fáze končí ověřením: build, screenshot okna ve světlém i tmavém tématu, u animací natočení okna a kontrola snímků.

## 12. Naměřený kontrast

Spočítáno z tokenů (WCAG, poměr jasu). Všechny textové dvojice jsou nad 4,5 : 1:

| Dvojice | Světlé | Tmavé |
|---|---|---|
| hlavní text na plátně | 15,9 | 15,9 |
| sekundární text na plátně | 4,8 | 6,3 |
| akcent jako text (`accentText`) | 5,5 | 6,4 |
| bílý text na výplni (`accentFill`) | 6,2 | 4,8 |
| diff přidáno / smazáno | 6,8 / 7,1 | 8,5 / 7,7 |
| odznaky M · A · D · R | 4,6 · 5,2 · 6,0 · 7,3 | 6,2 · 7,0 · 5,9 · 6,5 |
| hunk hlavička | 5,0 | 5,7 |
| varování / úspěch | 5,9 / 5,1 | 8,9 / 8,9 |

Proto jsou v paletě tři modré role: `accent` (ikony a tenké plochy), `accentText` (text na plátně) a `accentFill` (výplň pod bílým textem) – zesvětlený akcent z tmavého tématu by bílý text neunesl (2,8 : 1).
