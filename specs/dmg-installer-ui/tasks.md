# 实现计划：DMG 安装界面优化（dmg-installer-ui）

Spec Type: Feature
Workflow: requirements-first
Status: Tasks Draft
Review Status: unreviewed

## 概述

实现集中在 release 构建脚本：新增背景图生成脚本，然后改造 DMG 构建为“临时读写镜像设置 Finder 布局 -> 转换压缩镜像”的标准流程。App 源码不参与本次改动。

## 任务

- [x] 1. 增加 DMG 背景图生成能力
  - [x] 1.1 新增 Swift/AppKit 背景图脚本
    - 绘制 640x420 pt 背景图
    - 包含标题、简短提示和中间箭头
    - 文件：`scripts/generate-dmg-background.swift`
    - 验证：`swift scripts/generate-dmg-background.swift /tmp/markdown-dmg-background.png`
    - _需求：2.1、2.2、2.3_

- [x] 2. 改造 DMG 构建流程
  - [x] 2.1 在 staging 目录中写入背景图
    - 创建 `.background` 目录
    - 调用背景图生成脚本
    - 文件：`scripts/build-release-assets.sh`
    - 验证：`bash -n scripts/build-release-assets.sh`
    - _需求：2.1、3.1_

  - [x] 2.2 使用临时读写镜像写入 Finder 布局
    - 创建 UDRW 临时镜像
    - 挂载为可由 Finder 识别的读写卷
    - 通过 AppleScript 设置图标视图、背景图、窗口尺寸、图标位置
    - detach 后转换为 UDZO
    - 文件：`scripts/build-release-assets.sh`
    - 验证：`bash -n scripts/build-release-assets.sh`
    - _需求：1.1、1.2、1.3、1.4、3.2_

  - [x] 2.3 增加构建临时资源清理
    - 对 staging、临时 DMG、挂载点设置 trap 清理
    - 确保失败时尝试 detach
    - 文件：`scripts/build-release-assets.sh`
    - 验证：`bash -n scripts/build-release-assets.sh`
    - _需求：3.3、3.4_

- [x] 3. 检查点 —— 验证脚本
  - 运行 `bash -n scripts/build-release-assets.sh`
  - 运行背景图生成脚本并检查 PNG 输出。
  - 如环境允许，运行完整 release 构建脚本生成 DMG。

## 验收

- [x] 所有 required 任务完成。
- [x] 所有指定验证命令通过。
- [x] 若未运行完整 DMG 构建，原因已记录。
- [ ] 用户确认验收。
