# UI a Liquid Glass

Cíl: aplikace jako výstavní skříň Apple Liquid Glass, světlé i tmavé téma, pohyb jen tam, kde nese význam. Původní návrh je v [UI-Spec.md](UI-Spec.md), vizuální návrh na plátně: https://claude.ai/artifact/NPRcnoi7LYPhjHAzitHUqj.

## Dva styly rozhraní

Nastavení → Vzhled → „Styl rozhraní“ (`InterfaceStyle`, UserDefaults `interfaceStyle`).

| | **Revision** (výchozí) | **Klasický** |
|---|---|---|
| Kostra | vlastní `WindowShell` | `ClassicShell` = `NavigationSplitView` + `.inspector` |
| Pozadí | jedno plátno `RevisionSurface` (navy / frosted + záře) | systémové (`RevisionSurface` vrací `Color.clear`) |
| Toolbar | jeden přes celou šířku, `.toolbarBackgroundVisibility(.hidden)`, bez titulku | systémový s titulkem a podtitulkem, `.searchable` |
| Přepínač sekcí | `RevisionTabPicker` – putující gradientová kapsle | segmentový `Picker` (`ClassicSectionBar`) |
| Barvy | značková paleta (`Brandish`) | systémové barvy, akcent z nastavení macOS (`controlAccentColor`) |
| Lišty nad obsahem | bez pozadí, systémový scroll edge effect | pevná lišta nad obsahem |

- `InterfaceStyle.current` (statická, MainActor) nastavuje `RevisionApp` z uloženého nastavení; při změně se okna přestaví přes `.id(style)`, takže computed tokeny v `Theme` jsou vždy aktuální. V pohledech je styl také v prostředí: `@Environment(\.interfaceStyle)`.
- Téma (systém / světlé / tmavé) je samostatné nastavení `revisionAppearance` a platí pro oba styly.

## Vrstvy a sklo

| Vrstva | Co | Materiál |
|---|---|---|
| Plátno | pozadí okna | `RevisionSurface`, bez skla |
| Obsah | seznamy, diff, texty inspektoru | neprůhledné, **nikdy `glassEffect`** |
| Ovládání | toolbar, přepínače, pole a tlačítka v lištách, karty akcí | `.glassEffect(.regular[.tint][.interactive])` |

## Tokeny (`MacGit/Views/Components/Theme.swift`)

- Pohledy používají jen `Theme.*` – `canvas`, `surface`, `surfaceRaised`, `surfaceSunken`, `hairline`, `hairlineStrong`, `textPrimary`, `textSecondary`, `accent`, `accentDeep`, `accentText`, `accentFill`, `highlight`, `selectionTint`, `accentGradient`, `diff*`, `status*`, `success`, `warning`, `info`. Žádné `if scheme == .dark` v pohledech.
- Každý token je computed: Klasický → systémová `NSColor`, Revision → `Brandish` (privátní paleta z dynamických `NSColor`, které se samy překlápí světlo/tma).
- **Tři modré role:** `accent` (ikony, tenké plochy), `accentText` (text na plátně), `accentFill` (výplň pod bílým textem). Bílý text nikdy na `accent` – v tmavém tématu by měl kontrast 2,8 : 1. Kontrast všech dvojic je spočítaný v [UI-Spec.md §12](UI-Spec.md).
- Syrová paleta značky: `Brand.swift` (Primary Blue `#197BFF`, Cobalt `#0F52E8`, Indigo `#3F44F4`, Cyan `#63D7FF`, Midnight Navy `#0E1630`, Frosted `#EAF3FF`, Mist Gray `#D8E2F0`, Text Dark `#111827`).

## Přizpůsobivé modifikátory (`InterfaceStyle.swift`)

| Modifikátor | Revision | Klasický |
|---|---|---|
| `.adaptiveButtonStyle(prominent:)` | `.glass` / `.glassProminent` | `.bordered` / `.borderedProminent` |
| `.adaptiveCard(cornerRadius:tint:)` | `glassEffect` | `background.secondary` + linka |
| `.adaptiveFieldBackground()` | `glassEffect(.regular.interactive())` | `surfaceRaised` + linka |
| `.glassHeader { }` | `safeAreaBar(edge: .top)` + `.scrollEdgeEffectStyle(.soft, for: .vertical)`, **bez pozadí** | `VStack { bar; content }` |
| `.glassFooter { }` | `scrollEdgeEffectHidden(true, for: .bottom)` + maska (posledních 36 pt vybledne) + `safeAreaBar(edge: .bottom)` | `safeAreaInset(edge: .bottom)` |

`glassHeader`/`glassFooter` se dávají na **rolovací pohled** (List/ScrollView), resp. na celý sloupec (`RepositoryContentColumn`), ne dovnitř seznamu.

## Toolbar (styl Revision)

Pořadí podle návrhu: `⧉ panel │ BranchMenu │ Fetch · Pull · Push ……… SearchOrb │ inspektor │ AccountMenu`.
Levá skupina `placement: .navigation`, pak `ToolbarSpacer(.flexible)`, pravá skupina `.primaryAction`. `SearchOrb` a `AccountMenu` mají `.sharedBackgroundVisibility(.hidden)`. Přepínač seznam/strom a akce repozitáře jsou v menu ⋯ v hlavičce sloupce (`RepositoryMenuItems`), ne v toolbaru. Push je `PushToolbarButton` (Menu s `primaryAction`, nabídka „Push do…“).

## Ověřené záseky SwiftUI (macOS 26)

### Prázdná díra nad seznamem
**Příznak:** po přepnutí sekce (Změny → Historie…) vznikne nad seznamem prázdné místo ~97 pt.
**Příčina (změřeno):** SwiftUI dělá místo pod `safeAreaBar` neviditelným 0. řádkem `List`. List vytvořený **spolu s oknem** má ten řádek 0 pt + `contentInsets.top` 97 (správně). List vytvořený **až za běhu** dostane řádek 97 pt **a k tomu** inset 97 → díra. Nezávisí na tom, kdy se inset nastaví.
**Oprava:** `RepositoryContentColumn` drží všechny čtyři seznamy v `ZStack` od začátku a přepíná jen `opacity` (+ `allowsHitTesting`). Nepřepínat seznamy přes `if`/`switch`.
**Nedělat:** nulovat `contentInsets` (vypne scroll edge effect, obsah pak ostře přejíždí přes hlavičku), „pojistky“ přes probe pohledy, `safeAreaInset` místo `safeAreaBar`. Všechno zkoušeno, nefunguje nebo rozbije rozostření.
Záhlaví changelistů a skupin větví jsou obyčejné řádky, ne sticky `Section` hlavičky.

### Spodní hrana rolování
Systémový scroll edge effect na **spodní** hraně kreslí macOS vždy tvrdě (rovnoměrné rozmazání + linka), i s `.soft`. Proto `glassFooter` efekt skryje a obsah zamaskuje gradientem. Rámec masky končí u horní hrany lišty. `scrollEdgeEffectStyle` nastavovat pro `.vertical` najednou – pozdější volání pro jednu hranu přebije druhou.

### Putující výběr
`glassEffectID` **nemorfuje** mezi řádky v `LazyVStack` ani při záměně `if`/`else` v `ToolbarItem`. Funguje: `matchedGeometryEffect` s kapslí **pod** obsahem (postranní panel, `RevisionTabPicker`), nebo animovat šířku jednoho trvalého pohledu (`SearchOrb`).

### Menu přes celou šířku
`Menu` se vždy zmenší na obsah. Tlačítko přes celou šířku s rozbalovací šipkou = dvě tlačítka v `GlassEffectContainer` (split button Commit v `CommitComposer`).

### NavigationSplitView
Dává každému sloupci vlastní pozadí a rozseká toolbar podle sloupců – okno pak nepůsobí jako celek. Proto styl Revision používá vlastní `WindowShell`. V klasickém stylu pozor: minimální šířky detailu + toolbar se musí vejít do okna, jinak se postranní panel vykreslí posunutý mimo obrazovku. Linka pod toolbarem ve `WindowShell` je skutečný 1pt pohled, ne overlay (jinak sloupce dostanou odsazení toolbaru navíc).

### Pády
`NSColor(name:dynamicProvider:)` – uzávěra zdědí výchozí izolaci MainActor, ale SwiftUI barvy resolvuje i na render vlákně → SIGTRAP `_dispatch_assert_queue_fail`. Provider musí být `nonisolated static func` a uzávěra `@Sendable` (`Brandish.dynamic`).

### Rozostření bez tónu
`.ultraThinMaterial` a jiné materiály přidávají tón (uživatel odmítl – „barva musí zůstat stejná“). `NSView.backgroundFilters` (CIGaussianBlur) v SwiftUI nic nerozostří. Jediné čisté řešení je systémový scroll edge effect (`safeAreaBar` + `.soft`).

## Přístupnost

Reduce Motion vypíná putování kapslí a animované plátno, Reduce Transparency nahrazuje sklo neprůhlednou plochou. Barva nikdy nenese informaci sama (písmeno stavu, znaménko v diffu). Ikonová tlačítka mají `accessibilityLabel` a `.help`.
