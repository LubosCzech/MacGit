# Git, přihlášení a remoty

## Způsoby přihlášení projektu (`ProjectAuth`)

| Volba | Co se stane | Tajný údaj |
|---|---|---|
| `system` | výchozí chování gitu – ssh-agent, `~/.ssh/config`, osxkeychain helper | žádný v Revision |
| `sshKey(path)` | `GIT_SSH_COMMAND=ssh -i <klíč> -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new`; bez passphrase navíc `BatchMode=yes` | passphrase v Klíčence `ssh.<cesta>` |
| `account(UUID)` | HTTPS s tokenem uloženého účtu GitHub/GitLab | token v Klíčence `account.<uuid>` |
| `password(username)` | HTTPS uživatel + heslo/token | `project.<uuid>.password` |

`AppStore.credential(for:)` → `GitCredential` → `GitContext.credential(_:askpassPath:)` (env + `-c` volby). Kontext se použije **jen u síťových operací** (`GitRepository.networkContext`).

### Askpass

Tajné údaje se gitu/ssh nikdy nepředávají v argumentech. `askpass.sh` v Application Support (0700) vrací `$MACGIT_USERNAME` / `$MACGIT_SECRET` z prostředí procesu:

- HTTPS: `GIT_ASKPASS` + `-c credential.helper=` (vynuluje osxkeychain, aby nepodstrčil staré údaje),
- SSH passphrase: `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` + `DISPLAY=:0`,
- na výzvu „Bad passphrase / try again“ skript skončí kódem 1, aby se ssh nezacyklilo.

Názvy proměnných `MACGIT_*` zůstaly z doby MacGit – neměnit, jen interní.

### Zamčený SSH klíč a neznámý server

`RepositoryModel.perform(...)` obaluje každou síťovou operaci:

- **Neznámý / změněný klíč serveru** (`HostKeyTrust.problem(in:)`) → `HostTrustSheet` ukáže otisky SHA256 z `ssh-keyscan`, po potvrzení se zapíšou do `~/.ssh/known_hosts` a operace se zopakuje. Endpoint se bere z remotu, se kterým operace mluví (u „Push do…“ z cílového remotu, jinak origin).
- **Klíč není k dispozici** (`SSHKeyManager.isKeyUnavailable`) → `SSHUnlockSheet`: passphrase se přidá do ssh-agenta (volitelně i do Klíčenky macOS, pak funguje i v terminálu) a operace se zopakuje. Týká se i podepisování commitů SSH klíčem při HTTPS přihlášení.
- Při startu `SSHKeyManager.loadKeychainKeys()` načte do agenta klíče s passphrase v Klíčence macOS – GUI aplikace jinak agenta z terminálu nevidí.

### PATH v GUI

Aplikace spuštěná z Finderu nemá PATH z shellu. `GitRunner` doplňuje `/opt/homebrew/bin`, `/usr/local/bin` atd. (gpg, git-lfs, pinentry). CLI agenti pro review dostávají PATH z přihlašovacího shellu (`AgentDetector.loginShellPath`).

## Podpisy commitů

- Per repozitář v inspektoru (Repozitář): `user.name`, `user.email`, podepisování GPG / SSH / X.509 (`commit.gpgsign`, `gpg.format`, `user.signingkey`).
- Ověřování SSH podpisů: Revision generuje `Application Support/Revision/allowed_signers` (tvoje klíče z `~/.ssh` × tvoje e-maily z globálního gitu, účtů a identity repozitáře) a použije ho jen, když repozitář ani globální config nemá vlastní `gpg.ssh.allowedSignersFile`.
- Seznam podepsaných commitů v historii se čte rychle z `git log --pretty=raw` (hlavička `gpgsig`), samotné ověření se dělá líně jen pro vybraný commit.
- **Identita podle remotu není** (jiný e-mail/podpis pro GitLab než GitHub). Uživatel to řešit nechce – na GitLabu má přidaný druhý e-mail k účtu.

## Hosting (GitHub / GitLab, i self-hosted)

`HostingClient`: ověření tokenu, výpis a klonování repozitářů, nahrání SSH klíče (GitHub eviduje přihlašovací a podpisové klíče zvlášť, GitLab jedním klíčem oboje), URL nového PR/MR z větve, odkaz na commit na webu. Token je v Klíčence, nikdy v `state.json`.

## Push do… (zrcadlo na GitLabu)

Scénář uživatele: hlavní repozitář je `origin` na GitHubu, občas chce verzi poslat i do GitLabu.

1. Přidat remote (inspektor → Repozitář → Remoty, nebo `git remote add gitlab git@gitlab.com:<ns>/<repo>.git`).
2. Toolbar Push → šipka / podržení → „Push větve X do…“ → `gitlab`. Totéž v menu Repozitář → Push do.
3. Volba „Přibalit tagy“ (`pushToIncludesTags`) přidá `--tags`.

Implementace: `GitRepository.push(branch:toRemote:includeTags:context:)` = `git push <remote> refs/heads/X:refs/heads/X [--tags]` – **nikdy nemění upstream**, běžný Push dál míří na origin.

Bezpečnost přihlášení (`AppStore.context(forPushTo:primaryHost:auth:projectID:)`): údaje projektu patří k jeho hlavnímu serveru, **token ani heslo se nikdy nepošlou jinému hostu**. Pro cizí host se použije uložený účet se stejným hostem, jinak systémové přihlášení. SSH klíč se použije všude (serveru se neprozradí, jen podepíše výzvu).

### Chráněná větev na GitLabu

První push do prázdného projektu projde, další (zvlášť force nebo přepsání historie) GitLab odmítne: `pre-receive hook declined` / „You are not allowed to push code to protected branches“. `GitErrorSummary` to hlásí jako „Větev je na serveru chráněná“ (pravidlo musí být před obecným `[rejected]`; zachytí i GitHub `GH006`). Řešení na straně serveru: GitLab → Settings → Repository → Protected branches → Unprotect (nebo povolit force push). Uživatel zvolil unprotect.

## Další git chování

- **Commit jen vybraných souborů:** `git commit --only -- <cesty>` – index s ostatními změnami zůstane nedotčený.
- **Shelf:** `git add --intent-to-add` pro nové soubory, pak `git diff <base> --binary --find-renames` vybraných cest → patch; změny se pak z pracovního stromu vrátí. Obnovení: `git apply`, při neúspěchu `git apply --3way`; do changelistu stejného jména.
- **Changelisty** jsou čistě aplikační (workspace JSON), git o nich neví; soubory, které už nejsou změněné, se z přiřazení samy odstraní (`pruneWorkspace`).
- **Velká repozitáře:** strom změn se staví jen při změně souborů; repozitář bez `.gitignore` s velkým množstvím nesledovaných souborů dostane nabídku vytvořit `.gitignore` ze šablony (`GitignoreTemplate`).
