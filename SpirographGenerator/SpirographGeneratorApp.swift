import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SpirographGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SpirographModel()

    var body: some Scene {
        Window("Spirograph Generator", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export SVG…") { model.exportSVG() }
                    .keyboardShortcut("e", modifiers: [.command])
                Button("Export G-code…") { model.exportGCode() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Reset Export Settings to Defaults") { model.resetExportSettings() }
            }
            CommandMenu("Spirograph") {
                Button("Randomize") { model.randomize() }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                ForEach(SpirographPreset.all) { preset in
                    Button(preset.name) { model.apply(preset) }
                }
            }
        }
    }
}
