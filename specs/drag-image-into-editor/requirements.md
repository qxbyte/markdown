# 需求文档：拖拽图片插入当前文档

Spec Type: Feature
Workflow: requirements-first
Status: Requirements Draft
Review Status: unreviewed

## 简介

本功能为 macOS MarkdownEditor 增加将图片文件拖拽进当前编辑文档的完整体验。当前 `MarkdownTextEditor` 已基于 `NSTextView` 支持识别图片拖拽并插入 Markdown 图片语法，但插入内容使用源文件绝对路径，尚未按当前 Markdown 文档的位置管理资源，也未让预览以文档目录作为相对路径基准。

目标是：用户从 Finder 或其他文件来源拖入图片时，编辑器在拖拽落点插入 Markdown 图片标记；对于已保存的当前文档，图片复制到文档同级资源目录并插入相对路径；预览区立即显示该图片。

---

## 词汇表

- **当前文档**：当前窗口绑定的 `MarkdownDocument`，包含 Markdown 文本和可选的 `fileURL`。
- **编辑器**：`MarkdownTextEditor`，基于 `NSTextView` 的 SwiftUI/AppKit 桥接编辑区域。
- **拖拽图片**：通过 pasteboard 提供的本地文件 URL，且内容类型符合 `public.image` 的文件。
- **资源目录**：已保存 Markdown 文件旁的 `<文档名>.assets` 目录，用于存放拖入文档的图片副本。
- **图片 Markdown 标记**：形如 `![alt](path)` 的 Markdown 图片语法。

---

## 需求

### 需求 1：在当前编辑器落点插入图片 Markdown

**用户故事：** 作为 Markdown 编辑用户，我希望把图片拖到编辑器中的目标位置后自动插入图片语法，以便不用手动复制文件路径和编写 Markdown。

#### 验收标准

1. WHEN 用户将一个或多个本地图片文件拖入编辑器，THE 编辑器 SHALL 接受拖拽并在拖拽落点插入对应的图片 Markdown 标记。
2. WHEN 用户一次拖入多张图片，THE 编辑器 SHALL 为每张图片插入一行图片 Markdown 标记，并保持用户拖入文件的顺序。
3. WHEN 拖入内容不包含本地图片文件，THE 编辑器 SHALL 继续使用 `NSTextView` 原有拖拽行为。
4. WHEN 图片 Markdown 插入完成，THE 当前文档 SHALL 标记为已修改并刷新语法高亮。

---

### 需求 2：已保存文档使用同级资源目录

**用户故事：** 作为文档作者，我希望拖入图片后文档和图片资源保存在一起，以便移动或分享文档目录时图片链接仍然有效。

#### 验收标准

1. WHEN 当前文档已有 `fileURL` 且用户拖入图片，THE 系统 SHALL 在 Markdown 文件同级创建 `<文档名>.assets` 目录（如不存在）。
2. WHEN 图片复制到资源目录，THE 系统 SHALL 插入相对于当前 Markdown 文件目录的图片路径。
3. IF 资源目录中已存在同名文件，THEN THE 系统 SHALL 生成不覆盖已有文件的唯一文件名。
4. WHEN 源图片无法复制，THE 系统 SHALL 展示失败提示且不插入指向不存在文件的 Markdown 标记。

---

### 需求 3：未保存文档保持拖拽流程不中断

**用户故事：** 作为正在快速记录内容的用户，我希望在未保存文档中拖入图片时仍能插入引用，而不是被强制要求立刻保存文档。

#### 验收标准

1. WHEN 当前文档没有 `fileURL` 且用户拖入图片，THE 系统 SHALL 插入源图片的本地绝对路径作为 Markdown 图片路径。
2. WHEN 未保存文档之后被另存为，THE 系统 SHALL 不自动迁移既有绝对路径图片引用。
3. WHEN 用户在未保存文档中拖入图片，THE 系统 SHALL 标记文档为已修改。

---

### 需求 4：预览区正确解析图片路径

**用户故事：** 作为分屏预览用户，我希望拖入图片后预览区立即显示图片，以便确认插入结果正确。

#### 验收标准

1. WHEN 当前文档已保存且 Markdown 中包含相对图片路径，THE 预览 SHALL 以当前文档所在目录作为相对路径基准加载图片。
2. WHEN Markdown 中包含绝对本地图片路径，THE 预览 SHALL 继续支持加载该图片。
3. WHEN 用户在 Editor and Preview 模式拖入图片，THE 预览 SHALL 随文档文本更新而刷新。

---

## 边界情况

1. WHEN 图片文件名包含空格或特殊字符，THE 系统 SHALL 插入可被 Markdown/HTML 预览正确解析的路径。
2. WHEN 多张图片中部分复制失败，THE 系统 SHALL 只插入成功处理的图片，并提示失败项。
3. WHEN 拖入图片与当前文档位于同一资源目录且目标文件名一致，THE 系统 SHALL 复用或生成安全目标，不破坏源文件。

---

## 非功能需求

1. WHEN 用户拖入图片，THE 系统 SHALL 使用本地文件操作完成处理，不引入网络依赖。
2. WHEN 图片插入发生，THE 系统 SHALL 尽量保持现有 `NSTextView` undo/redo 行为。
3. THE 实现 SHALL 保持对 macOS 13+ 和 Swift Package 当前结构的兼容。

---

## 假设

- 已保存文档的默认资源目录命名为 `<Markdown 文件名不含扩展名>.assets`。
- 未保存文档采用绝对路径是 MVP 行为，后续可单独增加“保存时迁移图片资源”功能。
- 本次只处理本地图片文件拖拽，不扩展远程 URL 拖入、富文本图片拖入或截图粘贴行为。

## 待确认问题

- 是否希望未保存文档拖入图片时先弹出保存面板，而不是插入绝对路径？
- 资源目录名称是否固定为 `<文档名>.assets`，还是需要使用 `assets/`？
