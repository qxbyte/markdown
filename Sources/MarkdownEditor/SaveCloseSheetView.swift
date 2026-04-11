import SwiftUI
import AppKit

// MARK: - Tag Color Model

enum TagColor: String, CaseIterable, Hashable {
    case red    = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green  = "Green"
    case blue   = "Blue"
    case purple = "Purple"
    case gray   = "Gray"

    var displayName: String {
        switch self {
        case .red:    return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green:  return "绿色"
        case .blue:   return "蓝色"
        case .purple: return "紫色"
        case .gray:   return "灰色"
        }
    }

    var color: Color {
        switch self {
        case .red:    return Color(NSColor.systemRed)
        case .orange: return Color(NSColor.systemOrange)
        case .yellow: return Color(NSColor.systemYellow)
        case .green:  return Color(NSColor.systemGreen)
        case .blue:   return Color(NSColor.systemBlue)
        case .purple: return Color(NSColor.systemPurple)
        case .gray:   return Color(NSColor.systemGray)
        }
    }
}

// MARK: - Main Sheet View

struct SaveCloseSheetView: View {
    @State private var fileName: String
    @State private var saveLocation: URL
    @State private var selectedTags: [TagColor] = []
    @FocusState private var isFileNameFocused: Bool

    let onDelete: () -> Void
    let onCancel: () -> Void
    let onSave: (URL, [TagColor]) -> Void

    init(
        defaultFileName: String,
        defaultLocation: URL,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onSave: @escaping (URL, [TagColor]) -> Void
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
                        TagsPickerField(selectedTags: $selectedTags)
                    }

                    FormRow(label: "位置：") {
                        LocationPickerView(location: $saveLocation)
                    }
                }
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
                    onSave(url, selectedTags)
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

// MARK: - Form Row

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

// MARK: - Tags Picker

private struct TagsPickerField: View {
    @Binding var selectedTags: [TagColor]
    @State private var isShowingPicker = false

    var body: some View {
        Button(action: { isShowingPicker.toggle() }) {
            HStack(spacing: 6) {
                ForEach(selectedTags, id: \.self) { tag in
                    Circle()
                        .fill(tag.color)
                        .frame(width: 12, height: 12)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isShowingPicker ? Color.accentColor : Color(NSColor.separatorColor),
                    lineWidth: isShowingPicker ? 2 : 0.5
                )
        )
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            TagColorMenu(selectedTags: $selectedTags)
        }
    }
}

private struct TagColorMenu: View {
    @Binding var selectedTags: [TagColor]
    @State private var hoveredTag: TagColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(TagColor.allCases, id: \.self) { tag in
                HStack(spacing: 12) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 14, height: 14)
                    Text(tag.displayName)
                        .foregroundColor(.primary)
                    Spacer()
                    if selectedTags.contains(tag) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                            .font(.caption.bold())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(hoveredTag == tag ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onHover { isHovered in hoveredTag = isHovered ? tag : nil }
                .onTapGesture { toggle(tag) }
            }
        }
        .frame(width: 160)
        .padding(.vertical, 4)
    }

    private func toggle(_ tag: TagColor) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }
}

// MARK: - Location Picker

private struct LocationPickerView: View {
    @Binding var location: URL

    var body: some View {
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

// MARK: - Destructive Button Style

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
