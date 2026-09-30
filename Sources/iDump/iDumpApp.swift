import SwiftUI

@main
struct iDumpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = PhoneLibrary()

    var body: some Scene {
        Window("iDump", id: "main") {
            ContentView()
                .environment(library)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { library.start() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` rather than as a bundled .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        PhoneLibrary.clearPreviews()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        PhoneLibrary.clearPreviews()
    }
}
