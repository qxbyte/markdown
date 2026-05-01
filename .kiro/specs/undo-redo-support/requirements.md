# 需求文档

## 简介

本功能为 macOS Markdown 编辑器 App 添加完整的撤销（Command+Z）和重做（Shift+Command+Z）支持。

该 App 使用 `NSTextView` 作为编辑器核心，并通过 SwiftUI 的 `NSViewRepresentable`（`MarkdownTextEditor`）将其桥接到 SwiftUI 视图层。当前问题根源在于：

1. `Coordinator` 在执行格式化操作（加粗、斜体等）时，通过 `isUpdating` 标志绕过了 `NSUndoManager`，导致这些操作无法被撤销。
2. `updateNSView` 在外部数据变更时直接赋值 `textView.string = text`，会清空 `NSTextView` 内置的 undo 栈。
3. `FileCommands` 中没有注册撤销/重做菜单项，导致 macOS 标准 Edit 菜单中的撤销/重做条目缺失或无法响应。

实现目标：用户在编辑器中的所有文本操作（输入、删除、格式化、图片插入）均可通过 Command+Z 撤销、通过 Shift+Command+Z 重做，且菜单项状态（启用/禁用、标题）随 undo 栈动态更新。

---

## 词汇表

- **Editor**：`MarkdownTextEditor`，基于 `NSTextView` 的 SwiftUI 可表示视图，是用户输入文本的核心组件。
- **UndoManager**：`NSUndoManager`，AppKit 提供的撤销/重做管理器，与 `NSTextView` 原生集成。
- **Coordinator**：`MarkdownTextEditor.Coordinator`，`NSTextViewDelegate` 实现类，负责将 `NSTextView` 的变更同步到 SwiftUI 绑定。
- **FormatOperation**：格式化操作，包括加粗、斜体、删除线、行内代码、链接插入等通过 `textStorage.replaceCharacters` 执行的操作。
- **ExternalUpdate**：外部更新，指由 SwiftUI 数据层（`document.text`）驱动、经由 `updateNSView` 写入 `NSTextView` 的文本变更（如打开文件、新建文档）。
- **UndoMenuItem**：Edit 菜单中的"撤销"条目，快捷键 Command+Z。
- **RedoMenuItem**：Edit 菜单中的"重做"条目，快捷键 Shift+Command+Z。

---

## 需求

### 需求 1：普通文本输入与删除可撤销

**用户故事：** 作为编辑器用户，我希望通过 Command+Z 撤销刚才输入或删除的文字，以便快速纠正误操作。

#### 验收标准

1. WHEN 用户在 Editor 中输入或删除字符，THE UndoManager SHALL 记录该操作以支持后续撤销。
2. WHEN 用户按下 Command+Z，THE Editor SHALL 将文本恢复到上一次操作前的状态。
3. WHEN 用户按下 Shift+Command+Z，THE Editor SHALL 将文本重新应用已撤销的操作。
4. WHILE Editor 的 UndoManager 没有可撤销操作，THE UndoMenuItem SHALL 保持禁用状态。
5. WHILE Editor 的 UndoManager 没有可重做操作，THE RedoMenuItem SHALL 保持禁用状态。

---

### 需求 2：格式化操作可撤销

**用户故事：** 作为编辑器用户，我希望通过 Command+Z 撤销加粗、斜体、删除线、行内代码、链接等格式化操作，以便在误触快捷键或工具栏按钮后恢复原文。

#### 验收标准

1. WHEN 用户执行 FormatOperation，THE UndoManager SHALL 将该操作注册为一个可撤销的步骤。
2. WHEN 用户按下 Command+Z 撤销 FormatOperation，THE Editor SHALL 将选中文本恢复为格式化前的内容，并恢复操作前的选区范围。
3. WHEN 用户在撤销 FormatOperation 后按下 Shift+Command+Z，THE Editor SHALL 重新应用该格式化操作。
4. THE UndoManager SHALL 将每次 FormatOperation 注册为独立的撤销步骤，而非与相邻的字符输入合并。

---

### 需求 3：图片插入操作可撤销

**用户故事：** 作为编辑器用户，我希望通过 Command+Z 撤销通过拖拽或粘贴插入的图片 Markdown 标记，以便在误操作后恢复文本。

#### 验收标准

1. WHEN 用户通过拖拽图片文件到 Editor 触发图片插入，THE UndoManager SHALL 将该插入操作注册为可撤销步骤。
2. WHEN 用户通过粘贴图片到 Editor 触发图片插入，THE UndoManager SHALL 将该插入操作注册为可撤销步骤。
3. WHEN 用户按下 Command+Z 撤销图片插入，THE Editor SHALL 移除已插入的图片 Markdown 标记并恢复插入前的光标位置。

---

### 需求 4：外部更新不破坏 undo 栈

**用户故事：** 作为编辑器用户，我希望打开文件或新建文档后，undo 栈被正确重置，而不是保留上一个文档的历史记录。

#### 验收标准

1. WHEN ExternalUpdate 由打开文件操作触发，THE UndoManager SHALL 清空当前 undo 栈，使撤销/重做操作不跨文档生效。
2. WHEN ExternalUpdate 由新建文档操作触发，THE UndoManager SHALL 清空当前 undo 栈。
3. WHILE Editor 正在处理 ExternalUpdate，THE UndoManager SHALL 不记录该次文本替换为可撤销操作。
4. IF ExternalUpdate 与用户正在进行的编辑发生竞争，THEN THE Editor SHALL 优先保留用户的当前编辑状态，不覆盖未提交的输入。

---

### 需求 5：Edit 菜单撤销/重做条目正确显示

**用户故事：** 作为编辑器用户，我希望 macOS 菜单栏的 Edit 菜单中显示"撤销"和"重做"条目，并能通过菜单点击执行对应操作。

#### 验收标准

1. THE Editor SHALL 在 macOS Edit 菜单中提供 UndoMenuItem，快捷键为 Command+Z。
2. THE Editor SHALL 在 macOS Edit 菜单中提供 RedoMenuItem，快捷键为 Shift+Command+Z。
3. WHEN UndoManager 包含可撤销操作，THE UndoMenuItem SHALL 显示为启用状态，标题格式为"撤销 [操作名称]"。
4. WHEN UndoManager 包含可重做操作，THE RedoMenuItem SHALL 显示为启用状态，标题格式为"重做 [操作名称]"。
5. WHEN 用户点击 UndoMenuItem，THE UndoManager SHALL 执行撤销操作，等同于按下 Command+Z。
6. WHEN 用户点击 RedoMenuItem，THE UndoManager SHALL 执行重做操作，等同于按下 Shift+Command+Z。

---

### 需求 6：语法高亮不干扰 undo 栈

**用户故事：** 作为编辑器用户，我希望语法高亮的重新渲染不会产生额外的撤销步骤，以便 Command+Z 只撤销我的实际编辑操作。

#### 验收标准

1. WHEN MarkdownSyntaxHighlighter 对 textStorage 应用样式属性，THE UndoManager SHALL 不将该样式变更注册为可撤销操作。
2. THE MarkdownSyntaxHighlighter SHALL 仅修改 NSTextStorage 的属性（attributes），而不修改字符内容（characters），以避免触发内容级别的 undo 记录。
