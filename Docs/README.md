# Dokumentace Revision

Know-how k projektu na jednom místě. Krátký přehled funkcí je v [README v kořeni](../README.md).

| Dokument | O čem je |
|---|---|
| [Architektura.md](Architektura.md) | Vrstvy aplikace, GitKit, modely, kde co leží na disku, souběžnost, migrace z MacGit |
| [Vyvoj.md](Vyvoj.md) | Build, spuštění, testy, ladicí snímky, ověřování UI, konvence kódu |
| [UI-Liquid-Glass.md](UI-Liquid-Glass.md) | Dva styly rozhraní, tokeny, pravidla skla, **ověřené záseky SwiftUI** a co uživatel odmítl |
| [UI-Spec.md](UI-Spec.md) | Původní návrh UI/UX (fáze 0–7, tokeny, animace, kontrast) |
| [Git-a-prihlaseni.md](Git-a-prihlaseni.md) | Přihlášení k remotům, askpass, SSH klíče a known_hosts, podpisy, Push do…, zrcadlo na GitLabu |
| [AI.md](AI.md) | AI review přes CLI agenty, návrh commit zprávy přes Apple Intelligence |
| [Zalohy.md](Zalohy.md) | Zálohování a obnovení konfigurace, formát souboru, šifrování |
| [Vydavani.md](Vydavani.md) | Sparkle, notarizace, `new-release.sh`, zkušenosti z prvního vydání |
| [Rozhodnuti.md](Rozhodnuti.md) | Deník rozhodnutí a zpětné vazby – proč je něco udělané právě takhle |

Vizuální návrh (plátno): https://claude.ai/artifact/NPRcnoi7LYPhjHAzitHUqj · značka: `Design/` (logo, ikona, paleta).

Skills pro Claude Code jsou v `.claude/skills/` (build a ověření UI, vydání, změna UI).
