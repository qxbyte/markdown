# 需求文档：收紧 App 窗口顶部导航栏高度

Spec Type: Feature
Workflow: requirements-first
Status: Requirements Draft
Review Status: confirmed

## 简介

本功能针对 macOS MarkdownEditor 的窗口顶部导航栏做紧凑化调整。当前窗口使用 SwiftUI 的 `navigationTitle`、`navigationSubtitle` 和工具栏视图模式按钮，窗口样式已设置为 `unifiedCompact`，但顶部标题栏/工具栏在视觉上仍占用偏多垂直空间。

目标是：减少顶部导航栏上下方向的占用，让编辑区和预览区获得更多可用空间，同时保留当前文档标题、已修改状态提示和编辑/预览模式切换入口。

---

## 词汇表

- **顶部导航栏**：macOS 窗口顶部的标题栏和工具栏区域，包括文档标题、修改状态提示和视图模式切换按钮。
- **视图模式切换按钮**：`ContentView` 中用于切换 Editor、Editor and Preview、Preview 的三个 toolbar 图标按钮。
- **已修改状态提示**：当前文档存在未保存修改时显示给用户的状态反馈。
- **紧凑化**：减少顶部导航栏的垂直视觉占用，不要求改变窗口整体最小尺寸。

---

## 需求

### 需求 1：减少顶部导航栏上下方向占用

**用户故事：** 作为 Markdown 编辑用户，我希望窗口顶部导航栏更矮一些，以便让文档编辑区域更突出。

#### 验收标准

1. WHEN App 窗口显示编辑器，THE 顶部导航栏 SHALL 比当前实现更紧凑，减少上下方向的空白或控件高度。
2. WHEN 用户切换 Editor、Editor and Preview、Preview 模式，THE 顶部导航栏 SHALL 保持紧凑布局且不产生额外垂直撑高。
3. WHILE App 使用系统标题栏和工具栏，THE 实现 SHALL 不引入自绘标题栏或破坏 macOS 原生窗口行为。

### 需求 2：保留现有导航功能和状态表达

**用户故事：** 作为文档编辑用户，我希望顶部栏变小后仍能看到文档身份和保存状态，并能切换视图模式。

#### 验收标准

1. WHEN 当前文档有文件名或未命名状态，THE 窗口 SHALL 继续显示当前文档名称。
2. WHEN 当前文档存在未保存修改，THE 窗口 SHALL 继续提供“已修改”的状态反馈，但该反馈 SHALL NOT 通过增加第二行标题栏高度来显著撑高顶部导航栏。
3. WHEN 用户点击视图模式切换按钮，THE App SHALL 继续切换到对应视图模式。
4. WHEN 顶部栏按钮变小，THE 按钮图标 SHALL 不被裁剪，点击目标 SHALL 仍满足普通桌面 App 的可用性。

### 需求 3：保持主内容区域布局稳定

**用户故事：** 作为分屏预览用户，我希望顶部栏调整不影响编辑器和预览器本身的布局行为。

#### 验收标准

1. WHEN 顶部导航栏紧凑化后，THE 编辑器和预览器 SHALL 继续填满剩余窗口空间。
2. WHEN 用户调整窗口尺寸，THE 编辑器和预览器 SHALL CONTINUE TO 遵循当前最小宽高和分屏布局。
3. WHEN 文档修改状态变化，THE 主内容区域 SHALL NOT 因顶部栏状态文字变化而发生明显跳动。

---

## 边界情况

1. WHEN 文档名较长，THE 标题显示 SHALL 继续交由系统标题栏处理，不造成工具栏按钮重叠。
2. WHEN App 处于未保存文档状态，THE 标题栏 SHALL 仍显示“未命名”。
3. WHEN 文档状态在已保存和已修改之间切换，THE 顶部栏高度 SHALL 保持稳定。

---

## 非功能需求

1. THE 实现 SHALL 优先使用 SwiftUI/AppKit 现有标题栏和工具栏 API。
2. THE 实现 SHALL 避免引入新的第三方依赖。
3. THE 实现 SHALL 保持 macOS 13+ 和当前 Swift Package 结构兼容。

## 待确认问题

- 本次默认按“保留原生标题栏，只收紧标题栏内容和工具栏按钮尺寸”处理；是否确认？
