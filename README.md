# MarkdownEditor

macOS 原生 Markdown 编辑器，移植自 IntelliJ IDEA Markdown 插件的预览样式与字体体验。

## 技术栈

| 模块 | 技术 |
|------|------|
| UI 框架 | SwiftUI + AppKit (macOS 13+) |
| Markdown 解析 | [Down](https://github.com/johnxnguyen/Down) (wraps cmark-gfm) |
| 预览渲染 | WKWebView |
| 代码字体 | JetBrains Mono |
| 样式 | `default.css`，移植自 IntelliJ Markdown Plugin |

## 项目结构

```
Sources/MarkdownEditor/
├── MarkdownEditorApp.swift   # App 入口 (@main)
├── ContentView.swift         # 主布局：编辑器 / 预览 split view
├── MarkdownDocument.swift    # 文档状态、文件读写
├── MarkdownTextEditor.swift  # NSTextView 包装（编辑器侧）
├── MarkdownPreviewView.swift # WKWebView 包装（预览侧）
├── MarkdownProcessor.swift   # Markdown → HTML 转换
├── FileCommands.swift        # 菜单命令（新建、打开）
└── Resources/
    └── default.css           # 预览样式（移植自 IntelliJ 插件）
```

## 依赖要求

- **JetBrains Mono** 字体需安装到系统（字体名：`JetBrains Mono`）
  - 下载：https://www.jetbrains.com/lp/mono/
  - 未安装时自动回退到系统等宽字体

## 开发

用 Xcode 打开 `Package.swift`：

```bash
open Package.swift
# 或
xed .
```

首次打开 Xcode 会自动解析 Down 依赖，等待完成后选 `MarkdownEditor` Scheme 运行即可。

## 功能

- [x] 实时分屏预览
- [x] JetBrains Mono 代码字体
- [x] Light / Dark mode 自适应
- [x] GitHub Flavored Markdown（GFM）
- [x] 新建 / 打开 / 保存 `.md` 文件
- [ ] 语法高亮（TODO：集成 highlight.js）
- [ ] 编辑器 / 预览滚动同步（TODO）
- [ ] 多标签页（TODO）
