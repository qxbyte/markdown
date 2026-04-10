import SwiftUI

@main
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EditorSceneView(appDelegate: appDelegate)
        }
        .commands {
            FileCommands(appDelegate: appDelegate)
        }
    }
}

private struct EditorSceneView: View {
    @StateObject private var document = MarkdownDocument()
    let appDelegate: AppDelegate

    var body: some View {
        ContentView(document: document)
            .background(
                WindowAccessor { window in
                    appDelegate.registerWindow(window, document: document)
                }
            )
            .focusedSceneValue(\.markdownDocument, document)
            .onAppear {
                appDelegate.registerDocument(document)
                appDelegate.setActiveDocument(document)
            }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
