import SwiftUI
import AppKit

struct SaveCloseSheetView: View {
    @State private var fileName: String
    @State private var saveLocation: URL
    @State private var isExecutable: Bool = false
    @FocusState private var isFileNameFocused: Bool

    let onDelete: () -> Void
    let onCancel: () -> Void
    let onSave: (URL, Bool) -> Void

    init(
        defaultFileName: String,
        defaultLocation: URL,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onSave: @escaping (URL, Bool) -> Void
    ) {
        _fileName = State(initialValue: defaultFileName)
        _saveLocation = State(initialValue: defaultLocation)
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 6) {
                    Text("你要保留此新文稿\u{201C}\(fileName)\u{201D}吗?")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("你可以选择保存更改，或者立即删除此文稿。此操作无法撤销。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Form
                VStack(spacing: 10) {
                    FormRow(label: "保存为：") {
                        TextField("", text: $fileName)
                            .focused($isFileNameFocused)
                            .textFieldStyle(.roundedBorder)
                    }

                    FormRow(label: "标签：") {
                        TextField("", text: .constant(""))
                            .textFieldStyle(.roundedBorder)
                    }

                    FormRow(label: "位置：") {
                        LocationPickerView(location: $saveLocation)
                    }
                }

                Divider()

                Toggle("使文件可执行", isOn: $isExecutable)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Buttons
            HStack(spacing: 8) {
                Button(action: onDelete) {
                    Text("删除")
                        .foregroundColor(.white)
                        .frame(minWidth: 52)
                }
                .buttonStyle(DestructiveButtonStyle())

                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(action: {
                    let url = saveLocation.appendingPathComponent(fileName)
                    onSave(url, isExecutable)
                }) {
                    Text("保存")
                        .frame(minWidth: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(NSColor(calibratedRed: 0.27, green: 0.65, blue: 0.27, alpha: 1)))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420)
        .onAppear {
            isFileNameFocused = true
        }
    }
}

// MARK: - Subviews

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .frame(width: 52, alignment: .trailing)
            content()
        }
    }
}

private struct LocationPickerView: View {
    @Binding var location: URL

    var body: some View {
        HStack(spacing: 4) {
            Button(action: chooseLocation) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(location.lastPathComponent)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: chooseLocation) {
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .frame(width: 28)
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = location
        if panel.runModal() == .OK, let url = panel.url {
            location = url
        }
    }
}

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.45, alpha: 1))
                        .opacity(configuration.isPressed ? 0.8 : 1))
            )
            .foregroundColor(.white)
    }
}
