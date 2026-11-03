# AI funkce

## AI review větve / commitu

Revision nemá vlastní model – spouští **nainstalované CLI agenty** uživatele v režimu jen pro čtení.

### Průběh (`ReviewCenter.startReview`)

1. Rozsah (`ReviewScope`): větev = změny od merge-base se základní větví (výchozí `origin/HEAD` → `main` → `master`), commit = změny oproti prvnímu rodiči (první commit oproti prázdnému stromu).
2. `git worktree add --detach` do `$TMPDIR/Revision-reviews/…` – **pracovní kopie uživatele zůstane nedotčená**, agent nevidí rozpracované změny a nemůže je poškodit.
3. Agent běží v tom worktree s promptem (`AgentReview.swift`), výstup Markdown jde do `~/Library/Caches/cz.svetik.Revision/Reviews` (systém smí při nedostatku místa smazat).
4. Po doběhnutí / zrušení se worktree odstraní. Záznam (`ReviewRecord`) je ve workspace projektu; review běžící při ukončení aplikace se při dalším startu označí jako přerušená (`markInterrupted`).

### Příkazy agentů (`AgentCommand.review`)

| Agent | Příkaz |
|---|---|
| Claude Code | `claude -p <prompt> --output-format text --permission-mode dontAsk --allowedTools "Read,Grep,Glob,LS,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*)" --disallowedTools "Edit,Write,NotebookEdit,WebFetch,WebSearch" [--model]` |
| Codex | `codex exec --sandbox read-only --skip-git-repo-check --ephemeral -C <worktree> -o <soubor> [-m] <prompt>` (odpověď zapíše do souboru sám) |
| Cursor | `cursor-agent -p --output-format text --mode ask --trust --workspace <worktree> [--model] <prompt>` |
| Grok | `grok --prompt <prompt> --directory <worktree> [--model]` – **příznaky neověřené** |

- Detekce: známé instalační složky + PATH z přihlašovacího shellu (`AgentDetector.loginShellPath`, včetně `~/.zshrc`) – GUI aplikace PATH z terminálu nemá.
- Modely: dotaz na CLI, jinak záložní aliasy (`fallbackModels`). Volba agenta a modelu se pamatuje (`review.agent`, `review.model`).

### Formát výstupu

Prompt vynucuje české sekce `## Shrnutí`, `## Celkové riziko`, `## Místa k prověření`, `## Bezpečnost`, `## Výkon`, `## Testy`, `## Doporučení`. Nálezy jsou řádky `- [KRITICKÉ|DŮLEŽITÉ|K ZVÁŽENÍ] cesta:řádek — nadpis`. `ParsedReview` je rozebere pro kartu v inspektoru (záložka Review); když parsování selže, zobrazí se surový Markdown. Text před prvním nadpisem se zahodí (agenti občas přidají úvodní větu).

### Živý test

```bash
MACGIT_LIVE_REVIEW="${repo}:branch:base:agent:model" swift test --package-path Packages/GitKit --filter LiveAgentReviewTests
```

## Návrh commit zprávy (Apple Intelligence)

`CommitMessageGenerator` – systémový on-device model přes `FoundationModels` (`@Generable Suggestion { summary, body }`), streamuje rozpracovaný text do pole.

- Vstup: `ChangeSummary` (kompaktní přehled vybraných změn, limit 7 000 znaků – kontext modelu je ~4 096 tokenů včetně instrukcí a odpovědi) + větev + předměty posledních commitů (model podle nich odhadne styl).
- Zprávy jsou **anglicky** – model neumí česky.
- Dostupnost: v EU zatím Apple Intelligence často není (`modelNotReady`), UI pak ukáže důvod a tlačítko s jiskřičkou je neaktivní. Zkratka ⌥⌘G.
