import SwiftUI

@main
struct ImageForgeGUIApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { model.start() }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 740)
        .commands { AppCommands(model: model) }

        // Manage Models — a dedicated window (ADR-0001), single instance, opened
        // from the View menu or the Composer's first-run empty state.
        Window("Manage Models", id: "manage-models") {
            ManageModelsView()
                .environmentObject(model)
        }
        .defaultSize(width: 620, height: 580)
    }
}

/// App-specific menu-bar items layered onto SwiftUI's standard macOS menus
/// (Edit/Window keep their defaults; Undo/Redo/Cut/Copy/Paste work in the text
/// fields).
struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        // App menu → custom About (name + version + credits; icon from bundle).
        CommandGroup(replacing: .appInfo) {
            Button("About ImageForgeGUI") { model.showAboutPanel() }
        }

        // App menu → Manage Models. Model install/remove is an app-level, settings-y
        // task, so it lives in the app menu (next to About) rather than buried in View.
        CommandGroup(after: .appInfo) {
            Button("Manage Models…") { model.requestManageModels() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        // File → generation-relevant items (replaces the default "New Window").
        CommandGroup(replacing: .newItem) {
            Button("New Generation") { model.requestNewGeneration() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Reveal Library in Finder") { model.revealLibrary() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Export Selected…") { model.exportSelected() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.selection.isEmpty)
            Button("Delete Selected") { model.requestDeleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selection.isEmpty)
        }

        // View → Refresh Models (reloading the installed list is a view action).
        CommandGroup(after: .sidebar) {
            Button("Refresh Models") { model.loadModels() }
                .keyboardShortcut("r", modifiers: .command)
        }

        // Help → docs + upstream repo.
        CommandGroup(replacing: .help) {
            Button("ImageForgeGUI Help") { model.openHelp() }
            Button("image-forge on GitHub") { model.openImageForgeRepo() }
        }
    }
}
