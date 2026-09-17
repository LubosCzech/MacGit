#if DEBUG
import AppKit
import SwiftUI

/// Ladicí režim: `Revision --snapshots <složka>` uloží snímky okna pro všechny sekce (funguje i při zamčené obrazovce).
@MainActor
enum DebugSnapshots {
    static func runIfRequested(store: AppStore) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshots"), index + 1 < args.count else { return }
        let directory = URL(fileURLWithPath: args[index + 1])
        let dark = args.contains("--dark")
        Task {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
            try? await Task.sleep(for: .seconds(3))
            if let width = args.firstIndex(of: "--width").flatMap({ Double(args[$0 + 1]) }), let window = NSApp.windows.first(where: \.isVisible) {
                var frame = window.frame
                frame.size.width = width
                window.setFrame(frame, display: true)
                try? await Task.sleep(for: .seconds(1))
            }
            guard let project = store.project(store.selectedProjectID) else { return }
            let model = store.model(for: project)
            let suffix = dark ? "-dark" : ""
            for section in RepositoryModel.Section.allCases {
                model.section = section
                switch section {
                case .changes: model.selectedChangePaths = Set(model.status.changes.prefix(1).map(\.path))
                case .history: model.selectedCommitID = model.commits.first?.id
                default: break
                }
                try? await Task.sleep(for: .seconds(2))
                capture(to: directory.appendingPathComponent("\(section.rawValue)\(suffix).png"))
            }
            store.inspectorShown = true
            model.section = .history
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appendingPathComponent("history-inspector\(suffix).png"))
            model.section = .changes
            model.inspectorTab = .repository
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appendingPathComponent("repository-inspector\(suffix).png"))
            store.inspectorShown = false
            NSApp.terminate(nil)
        }
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        // Rozložení split view jako text – skleněné vrstvy se do snímku nevykreslí.
        var lines: [String] = []
        func walk(_ view: NSView, depth: Int) {
            if let split = view as? NSSplitView {
                lines.append(String(repeating: "  ", count: depth) + "split vertical=\(split.isVertical) " + split.arrangedSubviews.map { "\(Int($0.frame.minX))+\(Int($0.frame.width))\($0.isHidden ? "(hidden)" : "")" }.joined(separator: " | "))
            }
            if String(describing: type(of: view)).contains("Table") || String(describing: type(of: view)).contains("Outline") {
                let rows = (view as? NSTableView)?.numberOfRows ?? -1
                lines.append(String(repeating: "  ", count: depth) + "\(type(of: view)) x=\(Int(view.convert(view.bounds, to: nil).minX)) w=\(Int(view.frame.width)) rows=\(rows)")
            }
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        walk(view, depth: 0)
        try? lines.joined(separator: "\n").write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }
}
#endif
