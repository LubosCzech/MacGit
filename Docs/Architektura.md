# Architektura

Revision je nativní git klient pro macOS 26+ v SwiftUI. Veškerou práci s gitem dělá **systémový `git`** spouštěný jako podproces – žádná libgit2. Aplikace záměrně neběží v sandboxu (spouští `git`, `ssh`, `gpg`, CLI agenty).

## Vrstvy

```
MacGit/App          vstup aplikace, menu (Commands), ladicí snímky
MacGit/Model        AppStore (globální stav) · RepositoryModel (jeden otevřený repozitář)
MacGit/Services     Klíčenka, zálohy, aktualizace, AI, sledování souborů, migrace
MacGit/Views        SwiftUI – Shell (kostra okna), sekce, inspektor, nastavení, listy
Packages/GitKit     čistý Swift balíček: git, parsery, hosting API, SSH, review, formát zálohy
```

Pravidlo: **všechno, co jde otestovat bez UI, patří do GitKitu** (parsery, příkazy, formát zálohy, shrnutí chyb). Aplikace je tenká vrstva nad ním.

### GitKit (`Packages/GitKit/Sources/GitKit`)

| Soubor | Co dělá |
|---|---|
| `GitRunner.swift` | Spouští git (`/opt/homebrew/bin` → `/usr/local/bin` → `/usr/bin`). Doplňuje PATH o Homebrew, `GIT_TERMINAL_PROMPT=0`, `LC_ALL=en_US.UTF-8`, `GIT_EDITOR=true`, vždy `-c core.quotepath=false -c color.ui=false`. stdin se zapisuje z jiného vlákna (velké patche se nezablokují). |
| `GitContext.swift` | Prostředí pro přihlášení: `GitCredential` (system / sshKey / https) → env + `-c` volby, `askpassScript`. Viz [Git-a-prihlaseni.md](Git-a-prihlaseni.md). |
| `GitRepository.swift` | Operace nad repozitářem: status, commit `--only` vybraných souborů, discard, patch/shelf, větve, push/pull/fetch, `push(branch:toRemote:)`, ověření podpisu, config. |
| `Parsers.swift` | Parsery výstupu gitu (porcelain status, log, diff, podpisy z `--pretty=raw`). |
| `Models.swift` | Datové typy (FileChange, Commit, Branch, Remote…). |
| `FileTree.swift` | Strom složek pro seznam změn; slučuje řetězce složek (`a/b/c`), otisk podstromu pro O(1) porovnání. |
| `GitErrorSummary.swift` | Lidské shrnutí chyb gitu (chráněná větev, odmítnutý push, chybějící upstream…). Pořadí pravidel je důležité – specifické před obecným `[rejected]`. |
| `HostingClient.swift` | GitHub/GitLab API (i self-hosted): ověření tokenu, výpis repozitářů, nahrání SSH klíče, URL pro PR/MR. |
| `HostKeys.swift` | `ssh-keyscan`, otisky SHA256, zápis do `~/.ssh/known_hosts`. |
| `SSHKeys.swift` | Klíče v `~/.ssh`, generování Ed25519, ssh-agent + Klíčenka macOS, `allowed_signers`. |
| `AgentReview.swift` | Detekce CLI agentů, sestavení příkazů jen pro čtení, prompt, parsování výsledku. Viz [AI.md](AI.md). |
| `ChangeSummary.swift` | Kompaktní přehled změn pro malý jazykový model. |
| `ConfigBackup.swift` | Formát zálohy konfigurace + šifrování. Viz [Zalohy.md](Zalohy.md). |

### Model aplikace

- **`AppStore`** (`@Observable`, jedna instance, vzniká v `RevisionApp.init`): prostory, projekty, účty, výběr, viditelnost inspektoru, cache `RepositoryModel` pro každý projekt, `ReviewCenter`. Ukládá `state.json`.
- **`RepositoryModel`**: stav otevřeného repozitáře – status, změny, strom, historie, větve, shelf, sekce (`changes/history/branches/shelf`), záložka inspektoru, hledání, commit zpráva, běžící operace (`busyTitle`), chyby a dialogy (SSH unlock, důvěra serveru). Workspace (changelisty, rozepsané zprávy, historie review) ukládá s debounce do `workspaces/<id>.json`.
- **`RepositoryWatcher`**: FSEvents s debounce → obnovení statusu.
- Všechny síťové operace jdou přes `RepositoryModel.perform(...)`, který řeší zamčený SSH klíč (`SSHUnlockSheet`) a neznámý server (`HostTrustSheet`) a pak operaci zopakuje.

### Kostra okna

`RootView` → `StyledShell` volí podle stylu rozhraní:

- **`WindowShell`** (styl Revision) – vlastní `HStack` sloupců (panel │ seznam │ detail │ inspektor) oddělených `ColumnDivider`, jedno plátno `RevisionSurface`, jeden toolbar přes celou šířku. Záměrně **bez `NavigationSplitView`** – viz [UI-Liquid-Glass.md](UI-Liquid-Glass.md).
- **`ClassicShell`** (styl Klasický) – `NavigationSplitView` + `.inspector` + `.searchable` + systémový toolbar.

Sdílené sloupce: `RepositoryContentColumn` a `RepositoryDetailColumn` v `Views/Repository/RepositoryColumns.swift`.

## Data na disku

| Co | Kde |
|---|---|
| Prostory, projekty, účty, výběr | `~/Library/Application Support/Revision/state.json` |
| Workspace projektu (changelisty, zprávy, review) | `…/Revision/workspaces/<projectID>.json` |
| Shelf | `…/Revision/shelves/<projectID>/<shelfID>.patch` (binární patch; metadata shelfu jsou ve workspace) |
| Askpass skript | `…/Revision/askpass.sh` (0700, přepisuje se při startu) |
| Zálohy konfigurace | `…/Revision/Backups/` (nebo složka zvolená v Nastavení) |
| Tajné údaje | Klíčenka, služba `cz.svetik.Revision`, účty `account.<uuid>`, `project.<uuid>.password`, `ssh.<cesta ke klíči>` |
| Předvolby | UserDefaults `cz.svetik.Revision` (`interfaceStyle`, `revisionAppearance`, šířky sloupců…) |
| Výstupy AI review | `~/Library/Caches/cz.svetik.Revision/Reviews` |
| Dočasné worktree pro review | `$TMPDIR/Revision-reviews` |

## Souběžnost (Swift 6)

- `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` a `SWIFT_APPROACHABLE_CONCURRENCY` – vše v aplikaci je implicitně MainActor.
- GitKit typy jsou `Sendable`; `GitRunner` běží na `DispatchQueue.global` a vrací přes continuation.
- **Pozor:** uzávěry, které volá systém mimo hlavní vlákno (např. `NSColor(name:dynamicProvider:)`), musí být `nonisolated` + `@Sendable`, jinak SIGTRAP `_dispatch_assert_queue_fail`. Viz [UI-Liquid-Glass.md](UI-Liquid-Glass.md#pády).

## Migrace z MacGit

Aplikace se dřív jmenovala MacGit (bundle `cz.svetik.MacGit`). Při startu (`AppMigration`, `AppStore.init`):

- `Application Support/MacGit` se přesune na `…/Revision`, pokud nový ještě neexistuje,
- předvolby se jednorázově zkopírují ze starého bundle ID (`migratedFromMacGit`),
- `Keychain.get` čte i ze staré služby `cz.svetik.MacGit` a údaj přeuloží pod novou.

Bundle ID `cz.svetik.Revision` už **neměnit** bez stejné migrace (předvolby, Klíčenka, Application Support). Složka projektu a GitHub repozitář se dál jmenují MacGit – repozitář přejmenovat nejde, je v adrese aktualizací.
