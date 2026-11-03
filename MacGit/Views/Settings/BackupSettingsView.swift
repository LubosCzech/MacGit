import AppKit
import GitKit
import SwiftUI
import UniformTypeIdentifiers

/// Nastavení → Zálohy: automatické denní zálohy, ruční uložení a obnovení konfigurace.
struct BackupSettingsView: View {
    let backups: BackupService

    @State private var exportSheet = false
    @State private var restoreSummary: BackupService.Summary?
    @State private var message: String?
    @State private var error: String?

    private static var backupType: UTType {
        UTType(filenameExtension: ConfigBackup.fileExtension) ?? .json
    }

    var body: some View {
        @Bindable var backups = backups

        Form {
            Section("Automatické zálohy") {
                Toggle("Zálohovat konfiguraci jednou denně", isOn: $backups.automaticBackups)
                LabeledContent("Složka") {
                    HStack(spacing: 8) {
                        Text((backups.folder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(backups.folder.path)
                        Button("Změnit…", action: chooseFolder)
                        Button {
                            try? FileManager.default.createDirectory(at: backups.folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(backups.folder)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Otevřít ve Finderu")
                        .accessibilityLabel("Otevřít složku záloh ve Finderu")
                    }
                }
                if let last = backups.lastAutomaticBackup {
                    LabeledContent("Poslední automatická", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Text("Uchovává se posledních \(BackupService.keepAutomaticBackups) automatických záloh. Hesla a tokeny v nich nejsou. Pro ochranu před ztrátou Macu zvol složku na iCloud Drive nebo externím disku.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastError = backups.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                }
                Button("Zálohovat teď") {
                    do {
                        let url = try backups.backupNow()
                        message = "Záloha uložena: \(url.lastPathComponent)"
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }

            Section("Přenos a obnovení") {
                LabeledContent("Uložit zálohu do souboru") {
                    Button("Uložit zálohu…") { exportSheet = true }
                }
                LabeledContent("Obnovit ze zálohy") {
                    Button("Vybrat zálohu…", action: chooseBackupToRestore)
                }
                Text("Záloha obsahuje prostory, projekty, účty, changelisty, rozepsané commit zprávy, shelf a nastavení vzhledu. Na jiném Macu musí projekty ležet ve stejných složkách, jinak je Revision označí jako nenalezené. SSH klíče z ~/.ssh záloha neobsahuje.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Label(message, systemImage: "checkmark.circle").foregroundStyle(Theme.success)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $exportSheet) {
            ExportBackupSheet(backups: backups) { url in message = "Záloha uložena: \(url.lastPathComponent)" }
        }
        .sheet(item: Binding(get: { restoreSummary.map(RestoreItem.init) }, set: { restoreSummary = $0?.summary })) { item in
            RestoreBackupSheet(backups: backups, summary: item.summary)
        }
        .alert("Záloha se nepodařila", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = backups.folder
        panel.prompt = "Vybrat"
        if panel.runModal() == .OK, let url = panel.url {
            backups.folder = url
        }
    }

    private func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.backupType]
        panel.directoryURL = backups.folder
        panel.prompt = "Pokračovat"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            restoreSummary = try backups.summary(of: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private struct RestoreItem: Identifiable {
        let summary: BackupService.Summary
        var id: URL { summary.url }
    }
}

/// Uložení zálohy: volitelně s hesly a tokeny zašifrovanými heslem.
private struct ExportBackupSheet: View {
    let backups: BackupService
    let onSaved: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var includeSecrets = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var isWorking = false

    private var canSave: Bool {
        !includeSecrets || (password.count >= 8 && password == confirmation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uložit zálohu konfigurace").font(.title3.bold())

            Toggle("Přibalit hesla a tokeny", isOn: $includeSecrets)
            Text("Tokeny účtů, hesla projektů a passphrase SSH klíčů z Klíčenky. Zašifrují se heslem, které zadáš teď – bez něj je z této zálohy nikdo nepřečte, ani ty.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if includeSecrets {
                SecureField("Heslo zálohy (aspoň 8 znaků)", text: $password)
                SecureField("Heslo znovu", text: $confirmation)
                if !confirmation.isEmpty && password != confirmation {
                    Text("Hesla se neshodují.").font(.caption).foregroundStyle(Theme.statusDeleted)
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.statusDeleted)
            }

            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Uložit…", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isWorking)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ConfigBackup.fileExtension) ?? .json]
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Revision-\(stamp).\(ConfigBackup.fileExtension)"
        panel.directoryURL = backups.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try backups.export(to: url, includeSecrets: includeSecrets, password: includeSecrets ? password : nil)
            onSaved(url)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Obnovení: shrnutí zálohy, heslo k šifrovaným údajům a potvrzení nahrazení.
private struct RestoreBackupSheet: View {
    let backups: BackupService
    let summary: BackupService.Summary
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Obnovit konfiguraci ze zálohy").font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Soubor", summary.url.lastPathComponent)
                row("Vytvořena", summary.backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                row("Verze Revision", summary.backup.appVersion)
                row("Obsah", "\(summary.spaces) prostorů, \(summary.projects) projektů, \(summary.accounts) účtů, \(summary.shelves) souborů ve shelfu")
                row("Hesla a tokeny", summary.hasSecrets ? "ano, zašifrovaná" : "ne")
            }
            .font(.callout)

            if summary.hasSecrets {
                SecureField("Heslo zálohy", text: $password)
                Text("Bez hesla se obnoví konfigurace bez hesel a tokenů – ty zůstanou, jak jsou v Klíčence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label("Současné prostory, projekty, účty, changelisty a shelf se nahradí. Předtím se uloží záloha současného stavu, takže obnovení jde vrátit. Revision se pak restartuje.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(Theme.statusDeleted)
            }

            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Obnovit a restartovat", role: .destructive) {
                    do {
                        try backups.restore(summary.backup, password: password.isEmpty ? nil : password)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
