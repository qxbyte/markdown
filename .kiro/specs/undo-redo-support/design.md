# 设计文档：撤销/重做支持（undo-redo-support）

## 概述

本设计为 macOS Markdown 编辑器添加完整的撤销（Command+Z）和重做（Shift+Command+Z）支持。

编辑器核心是 `NSTextView`，通过 `MarkdownTextEditor`（`NSViewRepresentable`）桥接到 SwiftUI。`NSTextView` 内置了与 `NSUndoManager` 的原生集成，理论上只需 `allowsUndo = true` 即可获得文本输入/删除的撤销能力。然而当前实现存在三处破坏点：

1. **格式化操作绕过 UndoManager**：`Coordinator` 在执行 `toggleWrappedText`、`createOrToggleLink`、`insertMarkdownText` 等操作时，通过 `isUpdating = true` 标志直接操作 `textStorage`，导致这些变更不经过 `NSUndoManager` 的自动记录机制。
2. **外部更新清空 undo 栈**：`updateNSView` 在检测到 `textView.string != text` 时直接赋值 `textView.string = text`，这会重置 `NSTextView` 内部的 undo 栈，导致跨文档的 undo 历史污染。
3. **Edit 菜单缺少撤销/重做条目**：`FileCommands` 使用 `CommandGroup(replacing: .newItem)` 和 `CommandGroup(replacing: .saveItem)` 替换了部分菜单组，但没有处理 Edit 菜单的 undo/redo 条目，导致标准菜单项缺失或无法响应。

**设计目标**：以最小侵入性修复上述三处问题，充分利用 AppKit 原生机制，不引入自定义 undo 栈。

---

## 架构

### 现有架构

```
SwiftUI Layer
  └── ContentView
        └── MarkdownTextEditor (NSViewRepresentable)
              ├── makeNSView → NSScrollView + ImageDropTextView (NSTextView)
              ├── updateNSView → 同步外部 text 到 NSTextView
              └── Coordinator (NSTextViewDelegate)
                    ├── textDidChange → 同步 NSTextView 到 document.text
                    ├── toggleWrappedText / createOrToggleLink → 格式化操作
                    └── insertMarkdownText → 图片插入

AppKit Layer
  └── NSTextView
        ├── NSTextStorage (字符 + 属性存储)
        ├── NSUndoManager (内置，与 NSTextView 原生集成)
        └── MarkdownSyntaxHighlighter (属性高亮)

Menu Layer
  └── FileCommands (Commands)
        ├── CommandGroup(replacing: .newItem)
        └── CommandGroup(replacing: .saveItem)
        [缺少 Edit 菜单 undo/redo 处理]
```

### 修复后架构

核心变化：

1. **格式化/图片插入操作**：改用 `NSTextView.shouldChangeText(in:replacementString:)` + `didChangeText()` 配对调用，或直接通过 `undoManager.registerUndo` 手动注册，让 `NSUndoManager` 感知这些操作。
2. **外部更新**：区分"文档切换"（需清空 undo 栈）和"普通外部同步"（不应发生），通过 `undoManager.disableUndoRegistration()` 包裹外部更新，并在文档切换时调用 `undoManager.removeAllActions()`。
3. **语法高亮**：在 `highlight(_:)` 调用前后包裹 `beginEditing()`/`endEditing()`，并通过 `NSTextStorage` 的 `edited(_:range:changeInLength:)` 机制确保只修改属性而不触发 undo 记录。
4. **Edit 菜单**：依赖 macOS 标准机制——只要 `NSTextView` 是 first responder 且其 `undoManager` 有内容，系统会自动启用/禁用并更新 Edit 菜单中的 Undo/Redo 条目。`FileCommands` 不需要替换 `.undoRedo` 命令组。

```
修复后数据流：

用户输入/删除
  → NSTextView 原生处理 → NSUndoManager 自动记录 ✓

格式化操作 (toggleWrappedText 等)
  → textView.shouldChangeText(in:replacementString:)  [通知 UndoManager 准备]
  → textStorage.replaceCharacters(in:with:)
  → textView.didChangeText()                          [完成记录]
  → undoManager.setActionName("加粗") 等              [设置操作名称]

外部更新 (updateNSView, 文档切换)
  → undoManager.disableUndoRegistration()
  → textView.string = text  (或 textStorage.replaceCharacters)
  → undoManager.enableUndoRegistration()
  → undoManager.removeAllActions()                    [文档切换时清空]

语法高亮 (highlight)
  → storage.beginEditing()
  → storage.addAttribute(...)  [仅修改属性，不修改字符]
  → storage.endEditing()
  [NSTextStorage 不将纯属性变更记录到 UndoManager]

Edit 菜单
  → macOS 系统自动根据 NSTextView.undoManager 状态更新 ✓
```

---

## 组件与接口

### 1. `MarkdownTextEditor`（修改）

**`makeNSView` 变更**：无需修改，`allowsUndo = true` 已设置。

**`updateNSView` 变更**：

```swift
func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let textView = scrollView.documentView as! NSTextView
    applyEditorStyle(to: textView, coordinator: context.coordinator)
    guard !textView.hasMarkedText() else { return }
    guard textView.string != text else { return }

    // 外部更新：禁用 undo 记录，更新完成后清空 undo 栈
    let undoManager = textView.undoManager
    undoManager?.disableUndoRegistration()
    context.coordinator.isUpdating = true

    let selected = textView.selectedRanges
    textView.string = text
    textView.selectedRanges = selected
    if let storage = textView.textStorage {
        context.coordinator.highlighter?.highlight(storage)
    }

    context.coordinator.isUpdating = false
    undoManager?.enableUndoRegistration()
    undoManager?.removeAllActions()   // 清空跨文档的 undo 历史
}
```

**关键决策**：`removeAllActions()` 在每次外部更新后调用，确保打开文件、新建文档后 undo 栈干净。这符合需求 4.1、4.2、4.3。

### 2. `Coordinator`（修改）

**格式化操作的 undo 注册方式**：

当前代码在 `toggleWrappedText` 等方法中设置 `isUpdating = true` 后直接操作 `textStorage`，绕过了 `NSUndoManager`。

修复方案：使用 `NSTextView.shouldChangeText(in:replacementString:)` + `didChangeText()` 配对，这是 AppKit 推荐的方式，会自动通知 `NSUndoManager`：

```swift
private func toggleWrappedText(prefix: String, suffix: String, in textView: NSTextView) {
    let selected = textView.selectedRange()
    guard selected.location != NSNotFound, selected.length > 0 else { return }
    let source = textView.string as NSString
    let selectedText = source.substring(with: selected)
    let replacement: String
    let newSelectionRange: NSRange

    if selectedText.hasPrefix(prefix), selectedText.hasSuffix(suffix),
       selectedText.count >= prefix.count + suffix.count {
        let start = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
        let end = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
        replacement = String(selectedText[start..<end])
        newSelectionRange = NSRange(location: selected.location, length: replacement.count)
    } else {
        replacement = "\(prefix)\(selectedText)\(suffix)"
        newSelectionRange = NSRange(location: selected.location + prefix.count, length: selected.length)
    }

    // 使用 shouldChangeText/didChangeText 配对，让 NSUndoManager 自动记录
    guard textView.shouldChangeText(in: selected, replacementString: replacement) else { return }
    textView.textStorage?.replaceCharacters(in: selected, with: replacement)
    textView.didChangeText()
    textView.setSelectedRange(newSelectionRange)

    // 设置操作名称，用于 Edit 菜单显示
    textView.undoManager?.setActionName(actionName(for: prefix))

    if let storage = textView.textStorage {
        highlighter?.highlight(storage)
    }
    parent.text = textView.string
}
```

**注意**：移除 `isUpdating = true/false` 包裹，改由 `shouldChangeText`/`didChangeText` 机制处理。`textDidChange` 回调中的 `parent.text = tv.string` 赋值会触发 SwiftUI 重渲染，进而调用 `updateNSView`，但此时 `textView.string == text`，guard 条件会提前返回，不会清空 undo 栈。

**图片插入操作**：

```swift
private func insertMarkdownText(_ string: String, in tv: NSTextView) {
    let range = tv.selectedRange()
    let insertRange = NSRange(location: range.location, length: 0)

    guard tv.shouldChangeText(in: insertRange, replacementString: string) else { return }
    tv.textStorage?.replaceCharacters(in: insertRange, with: string)
    tv.didChangeText()
    tv.setSelectedRange(NSRange(location: insertRange.location + (string as NSString).length, length: 0))
    tv.undoManager?.setActionName("插入图片")

    if let storage = tv.textStorage { highlighter?.highlight(storage) }
    parent.text = tv.string
}
```

**`textDidChange` 回调**：

移除 `isUpdating` 检查对 `parent.text` 赋值的影响——格式化操作现在通过 `shouldChangeText`/`didChangeText` 触发 `textDidChange`，因此 `textDidChange` 中的 `parent.text = tv.string` 赋值是正确的，不需要 `isUpdating` 保护。

`isUpdating` 标志仍保留，但仅用于 `updateNSView` 中的外部更新场景，防止 `textDidChange` 在外部更新期间反写 `document.text`。

### 3. `MarkdownSyntaxHighlighter`（修改）

当前 `highlight(_:)` 直接调用 `storage.addAttribute(...)` 等方法。`NSTextStorage` 在 `beginEditing()`/`endEditing()` 配对外调用属性修改时，可能触发 delegate 通知并被 `NSUndoManager` 记录。

修复方案：在 `highlight(_:)` 中包裹 `beginEditing()`/`endEditing()`，并确保只修改属性（不修改字符内容）：

```swift
func highlight(_ storage: NSTextStorage) {
    let text = storage.string
    guard !text.isEmpty else { return }

    storage.beginEditing()
    defer { storage.endEditing() }

    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)

    resetBaseStyle(in: storage, range: fullRange)
    // ... 其余高亮逻辑不变 ...
}
```

`NSTextStorage` 的 `beginEditing()`/`endEditing()` 会将多次属性修改合并为一次 delegate 通知，且纯属性变更（不改变字符内容）不会被 `NSUndoManager` 记录为可撤销操作。

### 4. `FileCommands`（修改）

macOS 的 Edit 菜单 Undo/Redo 条目由系统自动管理：当 `NSTextView` 是 first responder 时，系统会查询其 `undoManager` 的 `canUndo`/`canRedo` 状态，并自动更新菜单项的启用状态和标题（"撤销 加粗"、"重做 斜体" 等）。

**当前问题**：`FileCommands` 没有替换 `.undoRedo` 命令组，理论上系统应自动处理。但需要确认没有其他代码干扰了 responder chain 或 `undoManager` 的查找。

**修复方案**：在 `FileCommands` 中显式添加 `.undoRedo` 命令组，确保 Undo/Redo 菜单项存在且行为正确：

```swift
CommandGroup(replacing: .undoRedo) {
    Button("撤销") {
        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
    }
    .keyboardShortcut("z", modifiers: .command)
    .disabled(!canUndo)

    Button("重做") {
        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
    }
    .keyboardShortcut("z", modifiers: [.command, .shift])
    .disabled(!canRedo)
}
```

**注意**：SwiftUI 的 `CommandGroup` 中的 `Button` 无法直接访问 `NSUndoManager` 状态。更好的方案是依赖 macOS 标准机制——不替换 `.undoRedo` 命令组，让系统自动处理。如果系统菜单不响应，则需要检查 responder chain。

**推荐方案**：不在 `FileCommands` 中替换 `.undoRedo`，而是确保 `NSTextView` 的 `undoManager` 正确连接到 window 的 responder chain。macOS 会自动处理 Edit 菜单的 Undo/Redo 条目。

---

## 数据模型

### UndoManager 状态流转

```
初始状态
  canUndo = false, canRedo = false

用户输入文字 "Hello"
  → NSTextView 自动记录
  canUndo = true ("撤销 输入"), canRedo = false

用户执行加粗 (toggleWrappedText)
  → shouldChangeText/didChangeText + setActionName("加粗")
  canUndo = true ("撤销 加粗"), canRedo = false

用户按 Command+Z (撤销加粗)
  → 文本恢复，选区恢复
  canUndo = true ("撤销 输入"), canRedo = true ("重做 加粗")

用户按 Shift+Command+Z (重做加粗)
  → 格式化重新应用
  canUndo = true ("撤销 加粗"), canRedo = false

外部更新 (打开文件 / 新建文档)
  → disableUndoRegistration + textView.string = newText + enableUndoRegistration + removeAllActions
  canUndo = false, canRedo = false
```

### 操作名称映射

| 操作 | `setActionName` 参数 |
|------|---------------------|
| 加粗 (`**`) | `"加粗"` |
| 斜体 (`*`) | `"斜体"` |
| 删除线 (`~~`) | `"删除线"` |
| 行内代码 (`` ` ``) | `"行内代码"` |
| 链接 (`[text](url)`) | `"链接"` |
| 图片插入 | `"插入图片"` |

### `isUpdating` 标志的精确语义

修复后，`isUpdating` 仅在 `updateNSView` 的外部更新路径中使用：

```
isUpdating = true
  ↓ 防止 textDidChange 反写 document.text（避免循环）
textView.string = text
  ↓
isUpdating = false
```

格式化操作不再使用 `isUpdating`，因为 `shouldChangeText`/`didChangeText` 会触发 `textDidChange`，而 `textDidChange` 中的 `parent.text = tv.string` 赋值是正确的（此时 `textView.string` 已是最新值）。

---

## 正确性属性

*属性（Property）是在系统所有有效执行中都应成立的特征或行为——本质上是关于系统应做什么的形式化陈述。属性是人类可读规范与机器可验证正确性保证之间的桥梁。*

### 属性 1：格式化操作可撤销（round-trip）

*对任意* Markdown 文本和任意非空选区，执行任意格式化操作（加粗、斜体、删除线、行内代码、链接）后，调用 `undoManager.undo()` 应将文本内容和选区范围恢复到操作前的状态。

**验证：需求 2.1、2.2**

### 属性 2：格式化操作 undo-redo round-trip

*对任意* Markdown 文本和任意非空选区，执行格式化操作后，依次调用 `undoManager.undo()` 再 `undoManager.redo()`，文本内容应与格式化后的状态完全一致。

**验证：需求 2.3**

### 属性 3：图片插入可撤销（round-trip）

*对任意* 编辑器文本状态和任意图片路径，执行图片 Markdown 插入后，调用 `undoManager.undo()` 应将文本内容和光标位置恢复到插入前的状态。

**验证：需求 3.1、3.2、3.3**

### 属性 4：语法高亮不改变字符内容

*对任意* Markdown 文本，调用 `MarkdownSyntaxHighlighter.highlight(_:)` 前后，`NSTextStorage.string`（字符内容）应保持完全不变。

**验证：需求 6.2**

### 属性 5：语法高亮不污染 undo 栈

*对任意* Markdown 文本和任意 `NSUndoManager` 初始状态（`canUndo` 为 true 或 false），调用 `MarkdownSyntaxHighlighter.highlight(_:)` 后，`undoManager.canUndo` 的值应与调用前保持一致。

**验证：需求 6.1**

---

## 错误处理

### 场景 1：`shouldChangeText` 返回 `false`

当 `textView.shouldChangeText(in:replacementString:)` 返回 `false` 时（例如文本视图处于只读状态），格式化操作应静默取消，不修改文本，不调用 `didChangeText()`。

处理方式：在 `guard textView.shouldChangeText(...) else { return }` 中提前返回。

### 场景 2：`undoManager` 为 `nil`

`NSTextView.undoManager` 理论上不为 `nil`（AppKit 保证），但防御性代码应使用可选链：`textView.undoManager?.setActionName(...)`。

### 场景 3：外部更新与用户输入竞争

当用户正在输入（`hasMarkedText() == true`，即 IME 输入法组字状态）时，`updateNSView` 中的 `guard !textView.hasMarkedText() else { return }` 会提前返回，保留用户的当前输入状态。这符合需求 4.4。

### 场景 4：高亮期间文本为空

`highlight(_:)` 开头的 `guard !text.isEmpty else { return }` 处理空文本情况，不执行任何操作。

---

## 测试策略

### 单元测试

针对以下具体场景编写示例测试：

- **需求 1.4/1.5**：初始状态下 `undoManager.canUndo == false`，`undoManager.canRedo == false`。
- **需求 2.4**：执行文本输入后执行格式化，验证格式化是独立的 undo 步骤（一次 undo 只撤销格式化，不撤销输入）。
- **需求 4.1/4.2**：执行编辑操作后触发外部更新，验证 `undoManager.canUndo == false`。
- **需求 5.3/5.4**：执行操作后验证 `undoManager.undoActionName` 非空且符合预期格式。

### 属性测试

使用 [SwiftCheck](https://github.com/typelift/SwiftCheck) 进行属性测试，每个属性最少运行 100 次迭代。

**属性 1 实现**（格式化操作可撤销）：

```swift
// Feature: undo-redo-support, Property 1: 格式化操作可撤销（round-trip）
property("格式化操作可撤销") <- forAll(
    Gen<String>.alphanumericString(minLength: 5, maxLength: 100),
    Gen<FormatAction>.arbitrary
) { text, action in
    let (textView, coordinator) = makeTestEditor(text: text)
    let fullRange = NSRange(location: 0, length: (text as NSString).length)
    textView.setSelectedRange(fullRange)

    let beforeText = textView.string
    let beforeRange = textView.selectedRange()

    coordinator.applyFormat(action, on: textView)

    textView.undoManager?.undo()

    return textView.string == beforeText
        && textView.selectedRange() == beforeRange
}
```

**属性 2 实现**（格式化 undo-redo round-trip）：

```swift
// Feature: undo-redo-support, Property 2: 格式化操作 undo-redo round-trip
property("格式化 undo-redo round-trip") <- forAll(
    Gen<String>.alphanumericString(minLength: 5, maxLength: 100),
    Gen<FormatAction>.arbitrary
) { text, action in
    let (textView, coordinator) = makeTestEditor(text: text)
    let fullRange = NSRange(location: 0, length: (text as NSString).length)
    textView.setSelectedRange(fullRange)

    coordinator.applyFormat(action, on: textView)
    let afterText = textView.string

    textView.undoManager?.undo()
    textView.undoManager?.redo()

    return textView.string == afterText
}
```

**属性 3 实现**（图片插入可撤销）：

```swift
// Feature: undo-redo-support, Property 3: 图片插入可撤销（round-trip）
property("图片插入可撤销") <- forAll(
    Gen<String>.alphanumericString(minLength: 0, maxLength: 200),
    Gen<String>.alphanumericString(minLength: 1, maxLength: 50)
) { text, imageName in
    let (textView, coordinator) = makeTestEditor(text: text)
    let insertPoint = NSRange(location: (text as NSString).length, length: 0)
    textView.setSelectedRange(insertPoint)

    let beforeText = textView.string
    let beforeCursor = textView.selectedRange()

    coordinator.insertImageMarkdown(name: imageName, path: "/tmp/\(imageName).png")

    textView.undoManager?.undo()

    return textView.string == beforeText
        && textView.selectedRange().location == beforeCursor.location
}
```

**属性 4 实现**（语法高亮不改变字符内容）：

```swift
// Feature: undo-redo-support, Property 4: 语法高亮不改变字符内容
property("语法高亮不改变字符内容") <- forAll(
    Gen<String>.markdownString(maxLength: 500)
) { markdownText in
    let storage = NSTextStorage(string: markdownText)
    let highlighter = MarkdownSyntaxHighlighter(baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular))

    highlighter.highlight(storage)

    return storage.string == markdownText
}
```

**属性 5 实现**（语法高亮不污染 undo 栈）：

```swift
// Feature: undo-redo-support, Property 5: 语法高亮不污染 undo 栈
property("语法高亮不污染 undo 栈") <- forAll(
    Gen<String>.markdownString(maxLength: 500),
    Bool.arbitrary
) { markdownText, hasExistingUndo in
    let (textView, _) = makeTestEditor(text: markdownText)
    if hasExistingUndo {
        // 预先制造一个 undo 步骤
        textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
    }
    let canUndoBefore = textView.undoManager?.canUndo ?? false

    if let storage = textView.textStorage {
        let highlighter = MarkdownSyntaxHighlighter(baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular))
        highlighter.highlight(storage)
    }

    return (textView.undoManager?.canUndo ?? false) == canUndoBefore
}
```

### 集成测试

- 验证 Edit 菜单中 Undo/Redo 条目存在（需求 5.1、5.2）
- 验证打开文件后 undo 栈清空（需求 4.1）
- 验证新建文档后 undo 栈清空（需求 4.2）

### 测试辅助工具

```swift
// 测试辅助：创建独立的 NSTextView + Coordinator 用于单元测试
func makeTestEditor(text: String) -> (NSTextView, MarkdownTextEditor.Coordinator) {
    let binding = Binding<String>(get: { text }, set: { _ in })
    let editor = MarkdownTextEditor(text: binding)
    let coordinator = editor.makeCoordinator()
    let scrollView = editor.makeNSView(context: /* mock context */)
    let textView = scrollView.documentView as! NSTextView
    return (textView, coordinator)
}
```
