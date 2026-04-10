# MarkdownEditor

macOS 原生 Markdown 编辑器，移植自 IntelliJ IDEA Markdown 插件的预览样式与字体体验。

## 技术栈

| 模块 | 技术 |
|------|------|
| UI 框架 | SwiftUI + AppKit (macOS 13+) |
| Markdown 解析 | [Down](https://github.com/johnxnguyen/Down) (wraps cmark-gfm) |
| 预览渲染 | WKWebView |
| 编辑器 | NSTextView + 自定义 Markdown 语法高亮 |
| 字体配置 | 内置多字体切换 + 字号调整（持久化） |
| 样式 | `default.css`，移植自 IntelliJ Markdown Plugin |

## 项目结构

```
Sources/MarkdownEditor/
├── MarkdownEditorApp.swift   # App 入口 (@main)
├── EditorStyleSettings.swift # 编辑器字体配置（字体族/字号）
├── ContentView.swift         # 主布局：编辑器 / 预览 split view
├── MarkdownDocument.swift    # 文档状态、文件读写
├── MarkdownTextEditor.swift  # NSTextView 包装（编辑器侧）
├── MarkdownPreviewView.swift # WKWebView 包装（预览侧）
├── MarkdownProcessor.swift   # Markdown → HTML 转换
├── FileCommands.swift        # 菜单命令（文件操作 + 字体设置）
└── Resources/
    └── default.css           # 预览样式（移植自 IntelliJ 插件）
```

## 字体设置

- 菜单路径：`字体` -> `选择字体`
- 支持字体：JetBrains Mono / SF Mono / Menlo / Monaco / Courier New / Fira Code
- 字号快捷键：
  - `⌘=` 增大字号
  - `⌘-` 减小字号
  - `⌘0` 重置字号
- 字体与字号使用 `@AppStorage` 持久化，重启应用后仍保持

## 开发

用 Xcode 打开 `Package.swift`：

```bash
open Package.swift
# 或
xed .
```

首次打开 Xcode 会自动解析 Down 依赖，等待完成后选 `MarkdownEditor` Scheme 运行即可。

## 功能

- [x] Editor / Editor and Preview / Preview 三模式切换
- [x] 实时分屏预览
- [x] 编辑器语法高亮（标题、代码块、链接、粗斜体等）
- [x] 编辑器字体选择与字号调整（持久化）
- [x] Light / Dark mode 自适应
- [x] GitHub Flavored Markdown（GFM）
- [x] 新建 / 打开 / 保存 `.md` 文件
- [x] 多窗口/多 tab 独立文档状态
- [x] 新窗口置顶并级联偏移打开
- [ ] 编辑器 / 预览滚动同步（TODO）
- [ ] 预览代码高亮主题可配置（TODO）
