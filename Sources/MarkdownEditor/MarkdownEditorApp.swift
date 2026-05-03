import SwiftUI

@main
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EditorSceneView(appDelegate: appDelegate)
        }
        .defaultSize(width: 650, height: 750)
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
        // window 引用在视图生命周期内稳定，updateNSView 不重复回调
        // 避免 SwiftUI 每次重渲染（如 isDirty 变化）都触发 registerWindow
    }
}
