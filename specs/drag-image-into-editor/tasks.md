# 实现计划：拖拽图片插入当前文档（drag-image-into-editor）

Spec Type: Feature
Workflow: requirements-first
Status: Tasks Draft
Review Status: unreviewed

## 概述

实现按“核心路径处理 -> 编辑器接入 -> 预览接入 -> 验证”的顺序推进。优先覆盖已保存文档的资源复制和相对路径插入，同时保留未保存文档的不中断体验。

## 任务

- [x] 1. 增加图片资源路径处理核心逻辑
  - [x] 1.1 新增 `MarkdownImageAssetManager`
    - 处理已保存文档资源目录创建、图片复制、唯一文件名、Markdown 路径编码
    - 处理未保存文档绝对路径回退
    - 文件：`Sources/MarkdownEditorCore/MarkdownImageAssetManager.swift`
    - 验证：`swift test`
    - _需求：2.1、2.2、2.3、3.1、4.1_

  - [x] 1.2 增加资源路径单元测试
    - 覆盖已保存文档复制到 `<文档名>.assets`
    - 覆盖同名冲突生成唯一文件名
    - 覆盖未保存文档插入绝对路径
    - 文件：`Tests/MarkdownEditorTests/MarkdownImageAssetManagerTests.swift`
    - 验证：`swift test`
    - _需求：2.1、2.2、2.3、3.1_

- [x] 2. 接入当前文档上下文和拖拽插入
  - [x] 2.1 将文档 URL 传入编辑器
    - `ContentView` 调用 `MarkdownTextEditor(text:documentURL:)`
    - `MarkdownTextEditor.updateNSView` 刷新 coordinator parent
    - 文件：`Sources/MarkdownEditor/ContentView.swift`、`Sources/MarkdownEditor/MarkdownTextEditor.swift`
    - 验证：`swift test`
    - _需求：1.1、2.1、3.1_

  - [x] 2.2 拖入图片时使用资源管理器生成 Markdown
    - 调用 `MarkdownImageAssetManager.references`
    - 多图按行插入
    - 失败时显示提示并避免插入坏链接
    - 文件：`Sources/MarkdownEditor/MarkdownTextEditor.swift`
    - 验证：`swift test`
    - _需求：1.1、1.2、1.4、2.4_

- [x] 3. 修复预览相对路径解析
  - [x] 3.1 将文档目录传入预览器
    - `ContentView` 调用 `MarkdownPreviewView(markdownText:baseURL:)`
    - 文件：`Sources/MarkdownEditor/ContentView.swift`
    - 验证：`swift test`
    - _需求：4.1、4.3_

  - [x] 3.2 预览器使用文档目录作为 HTML base URL
    - 已保存文档注入 HTML `<base>` 指向文档目录
    - 预览统一通过临时 HTML 文件加载，保留绝对路径图片读取能力
    - 文件：`Sources/MarkdownEditor/MarkdownPreviewView.swift`
    - 验证：`swift test`
    - _需求：4.1、4.2_

- [x] 4. 检查点 —— 构建与测试
  - 运行 `swift test`
  - 如遇现有未提交改动导致的编译问题，只做最小兼容修复并记录。

- [x] 5. 收尾修复预览区本地图片读取策略
  - 使用临时 HTML 文件承载 preview 内容
  - 已保存文档注入文档目录 `<base>`，让相对图片路径解析到当前文档目录
  - 保持绝对本地图片路径可加载
  - 文件：`Sources/MarkdownEditor/MarkdownPreviewView.swift`
  - 验证：`swift test`、`swift build`
  - _需求：4.1、4.2、4.3_

## 验收

- [x] 所有 required 任务完成。
- [x] 所有指定验证命令通过。
- [x] 未完成或跳过的 optional 任务已记录。
- [ ] 用户确认验收。
