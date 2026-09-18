import SwiftUI

/// Hledání v toolbaru: skleněný orb s lupou, který se po kliknutí fluidně roztáhne do pole.
///
/// Je to jeden trvalý pohled, kterému se animuje šířka – záměna `if`/`else` dvou pohledů
/// se v `ToolbarItem` neanimuje a hledání by jen skokem přeskočilo do pole.
struct SearchOrb: View {
    @Bindable var model: RepositoryModel

    /// 80 % šířky systémového pole (305 pt).
    private static let expandedWidth: CGFloat = 244
    private static let height: CGFloat = 28

    @FocusState private var isFocused: Bool
    /// Obsah pole se objeví až během růstu, aby text nevyskočil z orbu.
    @State private var showsField = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? { reduceMotion ? nil : .bouncy(duration: 0.4, extraBounce: 0.08) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if model.isSearchExpanded {
                    close(clearText: true)
                } else {
                    withAnimation(animation) { model.isSearchExpanded = true }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isSearchExpanded ? Theme.textSecondary : Theme.textPrimary)
                    .frame(width: Self.height, height: Self.height)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(model.isSearchExpanded ? "Zavřít hledání (esc)" : "Hledat (⌘F)")
            .accessibilityLabel(model.isSearchExpanded ? "Zavřít hledání" : "Hledat")

            if model.isSearchExpanded {
                TextField(model.section.searchPrompt, text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isFocused)
                    .opacity(showsField ? 1 : 0)
                    .accessibilityLabel(model.section.searchPrompt)
                    .onKeyPress(.escape) {
                        close(clearText: true)
                        return .handled
                    }

                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(showsField ? 1 : 0)
                    .accessibilityLabel("Vymazat hledání")
                    .padding(.trailing, 8)
                }
            }
        }
        .frame(width: model.isSearchExpanded ? Self.expandedWidth : Self.height, height: Self.height, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(animation, value: model.isSearchExpanded)
        .task(id: model.isSearchExpanded) {
            guard model.isSearchExpanded else {
                showsField = false
                return
            }
            try? await Task.sleep(for: .seconds(0.10))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showsField = true }
            isFocused = true
        }
        .task(id: isFocused) {
            // Prázdné pole se po odkliknutí zase sbalí do orbu.
            guard !isFocused, model.isSearchExpanded, model.searchText.isEmpty else { return }
            try? await Task.sleep(for: .seconds(0.15))
            guard !isFocused, model.searchText.isEmpty else { return }
            close(clearText: false)
        }
        .task(id: model.section) {
            guard model.isSearchExpanded, model.searchText.isEmpty else { return }
            close(clearText: false)
        }
    }

    private func close(clearText: Bool) {
        if clearText { model.searchText = "" }
        isFocused = false
        showsField = false
        withAnimation(animation) { model.isSearchExpanded = false }
    }
}
