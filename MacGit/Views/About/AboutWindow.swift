import AppKit
import SwiftUI

/// Okno „O aplikaci Revision“ – vlastní panel místo systémového, aby nesl studio,
/// podporu a vzhled aplikace (styl Revision i Klasický, světlé i tmavé téma).
@MainActor
final class AboutWindow {
    static let shared = AboutWindow()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: AboutContent.size.width, height: AboutContent.size.height),
                                 styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "O aplikaci Revision"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // NSPanel se při deaktivaci aplikace schová; okno O aplikaci musí zůstat,
            // když uživatel přepne jinam a zpátky.
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: AboutHostView())
            window.center()
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

/// Panel žije mimo scény SwiftUI, takže si vzhled a styl čte sám z předvoleb.
private struct AboutHostView: View {
    @AppStorage("revisionAppearance") private var appearance: RevisionAppearance = .system
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyle: InterfaceStyle = .revision

    var body: some View {
        AboutContent()
            .environment(\.interfaceStyle, interfaceStyle)
            .preferredColorScheme(appearance.colorScheme)
            .tint(Theme.accent)
            .id(interfaceStyle)
    }
}

struct AboutContent: View {
    static let size = CGSize(width: 400, height: 470)

    @Environment(\.interfaceStyle) private var style

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Verze \(version) (\(build))"
    }

    private var year: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                RevisionIdentity(size: 96)
                    .shadow(color: Theme.accent.opacity(style == .revision ? 0.35 : 0), radius: 18, y: 6)
                Text("Revision")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("See changes. Build with confidence.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                Text(versionText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                Text("Nativní git klient pro macOS. Repozitáře, klíče i tokeny zůstávají na tvém Macu.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.top, 14)

            Divider().padding(.vertical, 20)

            // Značka studia je přibalená, ne stahovaná: okno O aplikaci nedělá žádný
            // síťový požadavek, o který si uživatel neřekl.
            HStack(spacing: 14) {
                Image("SvtkMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text("svtk").font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(".dev").font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    Text("Nezávislé softwarové studio")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Link(destination: SupportLink.studio) {
                    Label("Otevřít svtk.dev", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .adaptiveButtonStyle(prominent: true)
                .accessibilityLabel("Otevřít svtk.dev v prohlížeči")

                Link(destination: SupportLink.page) {
                    Label("Kávu pro vývojáře", systemImage: "cup.and.saucer")
                        .frame(maxWidth: .infinity)
                }
                .adaptiveButtonStyle()
                .accessibilityLabel("Podpořit vývoj Revision přes Buy Me a Coffee")
            }
            .controlSize(.large)
            .padding(.top, 16)

            Spacer(minLength: 12)

            Text("© \(String(year)) svtk.dev · Aktualizace přes Sparkle")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 20)
        .padding(.top, 10)
        .frame(width: Self.size.width, height: Self.size.height)
        .background { RevisionSurface().ignoresSafeArea() }
    }
}
