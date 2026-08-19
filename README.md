# 一日 macOS App

一个本地优先的每日任务、专注计时与复盘应用。

详细需求、产品规则和验收标准见 [PRODUCT_SPEC.md](PRODUCT_SPEC.md)。

## 已实现

- 今日任务、预计用时、完成状态与手动会议
- 正向专注计时，暂停、继续和完成
- 看板：昨天、今天与带今日摘要的“已完成”成果墙
- 晚间复盘、备注和未完成任务处理策略
- 自定义模版和日期范围批量补录
- 基于历史实际用时的自动估时
- 默认 10:30 / 20:00 的可自定义本地通知
- 首次启动设置个人称呼，之后可点击侧边栏个人区域修改
- JSON 本地持久化
- 清新晨光主题的自定义 macOS App 图标
- 可滚动看板，并保留逾期、待安排和未来任务入口
- 成果墙按完成日期分组，支持编辑、删除和恢复为未完成
- 数据损坏时先备份原文件，再创建空白数据

## 构建

需要安装包含 macOS SDK 的 Xcode 或 Command Line Tools。构建脚本会自动选择本机可用的工具链，不依赖固定 SDK 版本，也同时适配 Apple 芯片和 Intel Mac。

```bash
./scripts/build-app.sh
```

构建结果位于 `dist/一日.app`。首次保存提醒时，macOS 会请求通知权限。

构建产物适用于执行脚本的当前 Mac 架构，并使用本地临时签名，适合个人试用。

如果提示“没有找到可用的 macOS SDK”，请安装或更新 Xcode，然后执行：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

应用数据保存在 `~/Library/Application Support/YiRi/data.json`。

如果数据无法解析，原文件会备份为同目录下的 `data-corrupt-<时间戳>.json`，应用会展示恢复提示，不再静默覆盖。

## 测试

```bash
./scripts/run-tests.sh
```

当前 9 项回归检查覆盖计时任务切换、活动任务提醒重排、看板任务可见性、完成日期分组与最近 20 条、完成后恢复、零计时文案、损坏数据恢复、首次启动数据和自动估时中位数。

## 制作 DMG 安装盘

```bash
./scripts/create-dmg.sh
```

脚本会先重新构建 App，再在 `dist/` 中生成对应当前 Mac 架构的 DMG。打开安装盘后，将“一日”拖到“Applications”即可安装。

当前版本采用本地临时签名，适合内部试用。未经过 Apple Developer ID 签名和公证时，其他 Mac 第一次打开可能需要右键点击“一日”，选择“打开”。
