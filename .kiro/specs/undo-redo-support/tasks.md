# 实现计划：撤销/重做支持（undo-redo-support）

## 概述

基于设计文档，通过三处最小侵入性修复，让编辑器的所有文本操作（输入、删除、格式化、图片插入）均可通过 Command+Z 撤销、Shift+Command+Z 重做，同时确保语法高亮不污染 undo 栈，Edit 菜单正确响应。

## 任务

- [ ] 1. 修复语法高亮对 undo 栈的干扰
  - [x] 1.1 在 `MarkdownSyntaxHighlighter.highlight(_:)` 中包裹 `beginEditing()`/`endEditing()`
    - 在 `highlight(_:)` 方法体开头调用 `storage.beginEditing()`，并用 `defer { storage.endEditing() }` 确保配对
    - 确认方法内所有操作仅调用 `addAttribute`/`removeAttribute`，不修改字符内容
    - 文件：`Sources/MarkdownEditor/MarkdownSyntaxHighlighter.swift`
    - _需求：6.1、6.2_

  - [ ] 1.2 编写属性测试：语法高亮不改变字符内容（属性 4）
    - **属性 4：语法高亮不改变字符内容**
    - 对任意 Markdown 文本，`highlight(_:)` 前后 `NSTextStorage.string` 应完全不变
    - 使用 SwiftCheck，`forAll(Gen<String>.markdownString(maxLength: 500))`
    - **验证：需求 6.2**

  - [ ] 1.3 编写属性测试：语法高亮不污染 undo 栈（属性 5）
    - **属性 5：语法高亮不污染 undo 栈**
    - 对任意文本和任意 `canUndo` 初始状态，`highlight(_:)` 后 `undoManager.canUndo` 应与调用前一致
    - 使用 SwiftCheck，`forAll(Gen<String>.markdownString(maxLength: 500), Bool.arbitrary)`
    - **验证：需求 6.1**

- [ ] 2. 修复外部更新清空 undo 栈的问题
  - [ ] 2.1 修改 `MarkdownTextEditor.updateNSView` 中的外部更新逻辑
    - 在 `textView.string = text` 赋值前后，用 `undoManager?.disableUndoRegistration()` / `undoManager?.enableUndoRegistration()` 包裹
    - 赋值完成后调用 `undoManager?.removeAllActions()` 清空跨文档的 undo 历史
    - 保留现有的 `isUpdating = true/false` 标志，防止 `textDidChange` 在外部更新期间反写 `document.text`
    - 保留 `guard !textView.hasMarkedText() else { return }` 以保护 IME 输入状态（需求 4.4）
    - 文件：`Sources/MarkdownEditor/MarkdownTextEditor.swift`，方法：`updateNSView`
    - _需求：4.1、4.2、4.3、4.4_

  - [ ] 2.2 编写单元测试：外部更新后 undo 栈清空
    - 执行编辑操作后触发外部更新，验证 `undoManager.canUndo == false`
    - 覆盖"打开文件"和"新建文档"两种场景
    - _需求：4.1、4.2_

- [ ] 3. 修复格式化操作绕过 UndoManager 的问题
  - [ ] 3.1 重构 `Coordinator.toggleWrappedText` 使用 `shouldChangeText`/`didChangeText` 配对
    - 移除方法内的 `isUpdating = true/false` 包裹
    - 在 `textStorage?.replaceCharacters` 前调用 `guard textView.shouldChangeText(in:replacementString:) else { return }`
    - 替换完成后调用 `textView.didChangeText()`
    - 根据 `prefix` 调用 `textView.undoManager?.setActionName(...)` 设置操作名称（加粗/斜体/删除线/行内代码/链接）
    - 文件：`Sources/MarkdownEditor/MarkdownTextEditor.swift`，方法：`toggleWrappedText`
    - _需求：2.1、2.2、2.4_

  - [ ] 3.2 重构 `Coordinator.replaceSelection`（链接操作）使用 `shouldChangeText`/`didChangeText` 配对
    - 移除方法内的 `isUpdating = true/false` 包裹
    - 同样添加 `shouldChangeText`/`didChangeText` 配对调用
    - 调用 `textView.undoManager?.setActionName("链接")`
    - 文件：`Sources/MarkdownEditor/MarkdownTextEditor.swift`，方法：`replaceSelection`
    - _需求：2.1、2.2、2.4_

  - [ ] 3.3 重构 `Coordinator.insertMarkdownText`（图片插入）使用 `shouldChangeText`/`didChangeText` 配对
    - 移除方法内的 `isUpdating = true/false` 包裹
    - 添加 `shouldChangeText`/`didChangeText` 配对调用
    - 调用 `textView.undoManager?.setActionName("插入图片")`
    - 文件：`Sources/MarkdownEditor/MarkdownTextEditor.swift`，方法：`insertMarkdownText`
    - _需求：3.1、3.2、3.3_

  - [ ] 3.4 添加 `actionName(for:)` 辅助方法，将 prefix 映射为操作名称
    - 实现 `private func actionName(for prefix: String) -> String` 方法
    - 映射关系：`"**"` → `"加粗"`，`"*"` → `"斜体"`，`"~~"` → `"删除线"`，`` "`" `` → `"行内代码"`
    - 文件：`Sources/MarkdownEditor/MarkdownTextEditor.swift`，`Coordinator` 内
    - _需求：2.1、5.3、5.4_

  - [ ] 3.5 编写属性测试：格式化操作可撤销（属性 1）
    - **属性 1：格式化操作可撤销（round-trip）**
    - 对任意文本和任意非空选区，执行格式化后 `undoManager.undo()`，文本和选区应恢复到操作前状态
    - 使用 SwiftCheck，`forAll(Gen<String>.alphanumericString(...), Gen<FormatAction>.arbitrary)`
    - **验证：需求 2.1、2.2**

  - [ ] 3.6 编写属性测试：格式化操作 undo-redo round-trip（属性 2）
    - **属性 2：格式化操作 undo-redo round-trip**
    - 对任意文本，执行格式化后依次 `undo()` 再 `redo()`，文本应与格式化后状态完全一致
    - 使用 SwiftCheck，`forAll(Gen<String>.alphanumericString(...), Gen<FormatAction>.arbitrary)`
    - **验证：需求 2.3**

  - [ ] 3.7 编写属性测试：图片插入可撤销（属性 3）
    - **属性 3：图片插入可撤销（round-trip）**
    - 对任意文本和任意图片名称，执行插入后 `undoManager.undo()`，文本和光标位置应恢复到插入前状态
    - 使用 SwiftCheck，`forAll(Gen<String>.alphanumericString(...), Gen<String>.alphanumericString(...))`
    - **验证：需求 3.1、3.2、3.3**

- [ ] 4. 检查点 —— 确保所有测试通过
  - 确保所有测试通过，如有疑问请向用户确认。

- [ ] 5. 修复 Edit 菜单撤销/重做条目
  - [ ] 5.1 确认 `FileCommands` 不替换 `.undoRedo` 命令组，依赖 macOS 标准机制
    - 检查 `FileCommands.swift`，确认没有 `CommandGroup(replacing: .undoRedo)` 调用
    - 若存在则移除，让系统自动根据 `NSTextView.undoManager` 状态管理 Edit 菜单
    - 若系统菜单不响应，则检查 responder chain，确保 `NSTextView` 的 `undoManager` 正确连接
    - 文件：`Sources/MarkdownEditor/FileCommands.swift`
    - _需求：5.1、5.2、5.3、5.4、5.5、5.6_

  - [ ] 5.2 编写单元测试：操作名称格式正确
    - 执行各类格式化操作后，验证 `undoManager.undoActionName` 非空且符合预期（"加粗"、"斜体"等）
    - _需求：5.3、5.4_

  - [ ] 5.3 编写单元测试：初始状态 undo/redo 禁用
    - 验证初始状态下 `undoManager.canUndo == false`，`undoManager.canRedo == false`
    - _需求：1.4、1.5_

  - [ ] 5.4 编写单元测试：格式化为独立 undo 步骤
    - 执行文本输入后再执行格式化，验证一次 `undo()` 只撤销格式化，不撤销输入
    - _需求：2.4_

- [ ] 6. 最终检查点 —— 确保所有测试通过
  - 确保所有测试通过，如有疑问请向用户确认。

## 备注

- 标有 `*` 的子任务为可选项，可跳过以加快 MVP 进度
- 每个任务均引用了具体需求条款以保证可追溯性
- 属性测试依赖 [SwiftCheck](https://github.com/typelift/SwiftCheck)，需在 `Package.swift` 中添加该依赖
- 检查点确保每个阶段的增量验证
- 属性测试验证系统的普遍正确性，单元测试验证具体示例和边界条件
