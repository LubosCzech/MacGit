import Foundation

/// Šablona .gitignore podle toho, co v projektu je (Xcode/Swift, Node, .NET, Python…).
enum GitignoreTemplate {
    static func contents(for directory: URL) -> String {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: directory.appendingPathComponent(name).path) }
        let items = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []

        var sections: [String] = ["""
        # macOS
        .DS_Store
        """]

        let isApple = items.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") } || exists("Package.swift") || exists("project.yml")
        if isApple {
            sections.append("""
            # Xcode / Swift
            build/
            DerivedData/
            .build/
            .swiftpm/
            xcuserdata/
            *.xcuserstate
            *.xcscmblueprint
            *.ipa
            *.dSYM.zip
            *.dSYM
            """)
        }
        if exists("package.json") {
            sections.append("""
            # Node
            node_modules/
            dist/
            .env
            npm-debug.log*
            """)
        }
        if items.contains(where: { $0.hasSuffix(".sln") || $0.hasSuffix(".slnx") || $0.hasSuffix(".csproj") }) {
            sections.append("""
            # .NET
            bin/
            obj/
            .vs/
            *.user
            """)
        }
        if exists("requirements.txt") || exists("pyproject.toml") {
            sections.append("""
            # Python
            __pycache__/
            *.pyc
            .venv/
            venv/
            """)
        }
        if !isApple {
            sections.append("""
            # Build výstupy
            build/
            """)
        }
        return sections.joined(separator: "\n\n") + "\n"
    }
}
