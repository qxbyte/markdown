# 实现计划：收紧 App 窗口顶部导航栏高度（compact-window-toolbar）

Spec Type: Feature
Workflow: requirements-first
Status: Tasks Draft
Review Status: confirmed

## 概述

实现按“移除副标题撑高因素 -> 同步原生修改状态 -> 收紧工具栏按钮 -> 验证”的顺序推进。改动集中在 `ContentView`，尽量不触碰窗口生命周期、文档保存逻辑和主内容布局。

## 任务

- [x] 1. 移除顶部栏副标题高度占用
  - [x] 1.1 从 `ContentView` 移除 `.navigationSubtitle(document.isDirty ? "已修改" : "")`
    - 保留 `.navigationTitle(document.displayName)`
    - 避免修改状态变化时通过副标题撑高标题栏
    - 文件：`Sources/MarkdownEditor/ContentView.swift`
    - 验证：`swift build`
    - _需求：1.1、2.1、2.2、3.3_

- [x] 2. 使用原生窗口修改状态表达
  - [x] 2.1 将 `MarkdownDocument.isDirty` 同步到 `NSWindow.isDocumentEdited`
    - 复用现有窗口访问机制或增加轻量窗口状态同步视图
    - 在窗口出现、修改状态变化、文档切换/保存后同步状态
    - 文件：`Sources/MarkdownEditor/ContentView.swift`
    - 验证：`swift build`
    - _需求：2.2、3.3_

- [x] 3. 收紧视图模式工具栏按钮
  - [x] 3.1 调整 `modeButton` 尺寸和工具栏间距
    - 减小图标字号、按钮 frame、背景圆角和外层 `HStack` 间距/内边距
    - 保持三个按钮固定尺寸，选中状态不改变布局尺寸
    - 文件：`Sources/MarkdownEditor/ContentView.swift`
    - 验证：`swift build`
    - _需求：1.1、1.2、2.3、2.4_

- [x] 4. 检查点 —— 构建、测试与规格校验
  - [x] 4.1 运行验证命令
    - 运行 `swift build`
    - 运行 `swift test`
    - 运行 `python3 /Users/xueqiang/.codex/skills/spec-hub/scripts/spec_lint.py specs/compact-window-toolbar`
    - 如验证受沙箱限制，按实际情况记录并重跑必要命令
    - _需求：1.3、3.1、3.2_

## 验收

- [x] 所有 required 任务完成。
- [x] 所有指定验证命令通过。
- [x] 未完成或跳过的 optional 任务已记录。
- [ ] 用户确认验收。
