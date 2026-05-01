# 需求文档：DMG 安装界面优化

Spec Type: Feature
Workflow: requirements-first
Status: Requirements Draft
Review Status: unreviewed

## 简介

当前 release 脚本生成的 DMG 仅包含 `MarkdownEditor.app` 和 `/Applications` 软链接。用户打开 DMG 后看到的是默认 Finder 文件夹视图，缺少常见 macOS App 安装镜像的视觉引导。

本功能优化 DMG 安装界面，使其更接近主流 macOS App 分发体验：打开 DMG 后显示固定尺寸 Finder 窗口，左侧为 App，右侧为 Applications，背景图提供清晰拖拽箭头与安装提示。

---

## 词汇表

- **DMG**：macOS 磁盘镜像安装包，由 `scripts/build-release-assets.sh` 生成。
- **安装窗口**：用户双击打开 DMG 后 Finder 展示的镜像窗口。
- **背景图**：DMG 内 `.background/background.png`，用于在 Finder 图标视图中显示拖拽引导。
- **Applications 链接**：DMG 内指向 `/Applications` 的软链接。
- **读写镜像**：构建过程中用于写入 Finder 元数据的临时 UDRW 镜像。
- **压缩镜像**：最终发布给用户的 UDZO 镜像。

---

## 需求

### 需求 1：提供主流拖拽安装布局

**用户故事：** 作为下载用户，我希望打开 DMG 后能直观看到“把 App 拖到 Applications”的界面，以便快速完成安装。

#### 验收标准

1. WHEN 用户打开生成的 DMG，THE Finder SHALL 以图标视图展示安装窗口。
2. WHEN 安装窗口显示，THE `MarkdownEditor.app` SHALL 位于窗口左侧，THE `Applications` 链接 SHALL 位于窗口右侧。
3. WHEN 安装窗口显示，THE 背景图 SHALL 显示从 App 指向 Applications 的拖拽箭头。
4. WHILE 用户查看安装窗口，THE Finder 工具栏和状态栏 SHALL 默认隐藏。

---

### 需求 2：自动生成可维护的 DMG 背景图

**用户故事：** 作为发布维护者，我希望背景图由脚本生成，以便未来调整尺寸、文案或样式时不需要维护二进制设计源文件。

#### 验收标准

1. WHEN release 脚本构建 DMG，THE 脚本 SHALL 自动生成 `.background/background.png`。
2. WHEN 背景图生成，THE 图像 SHALL 包含安装标题、简短拖拽提示和居中箭头。
3. IF 背景图生成失败，THEN THE release 脚本 SHALL 失败退出，避免发布缺少引导界面的 DMG。

---

### 需求 3：构建流程保持稳定

**用户故事：** 作为发布者，我希望优化 DMG 外观不破坏现有 `.app` 和 `.pkg` 产物生成流程，以便继续使用同一发布命令。

#### 验收标准

1. WHEN 执行 `scripts/build-release-assets.sh <version>`，THE 脚本 SHALL 继续生成 `.app`、`.dmg`、`.pkg`。
2. WHEN DMG 生成完成，THE 最终 `.dmg` SHALL 为压缩只读镜像。
3. WHEN 临时读写镜像、挂载点或 staging 目录被创建，THE 脚本 SHALL 在成功或失败时清理临时资源。
4. IF Finder 元数据写入失败，THEN THE 脚本 SHALL 失败退出并清理已挂载镜像。

---

## 边界情况

1. WHEN 构建机器没有可用 Finder 图形会话，THE 脚本 SHALL 在 Finder 布局步骤失败并停止，而不是静默生成低质量 DMG。
2. WHEN DMG 挂载点或设备名获取失败，THE 脚本 SHALL 停止并返回错误。
3. WHEN 版本号不同，THE DMG 文件命名 SHALL 继续使用 `MarkdownEditor-<version>.dmg`。

---

## 非功能需求

1. THE 实现 SHALL 使用 macOS 自带工具和 Swift/AppKit，不引入新的第三方依赖。
2. THE 背景图 SHALL 使用与 Finder 安装窗口匹配的 640x420 pt 画布生成，保证布局位置稳定。
3. THE 视觉风格 SHALL 简洁、主流、接近常见 macOS 拖拽安装镜像。

---

## 假设

- 发布构建运行在 macOS 图形会话中，允许 `Finder` 通过 AppleScript 写入窗口布局元数据。
- 最终 DMG 仍由 `scripts/build-release-assets.sh` 生成，`package-app.sh` 的本地安装流程不在本次范围内。
- 背景图画布固定为 640x420 pt；在 Retina 环境中输出可为 1280x840 px。

## 待确认问题

- 安装窗口文案是否需要完全中文化，还是保持主流英文 `Drag to Applications`？
