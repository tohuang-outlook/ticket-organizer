# Ticket Organizer

原生 macOS SwiftUI 工单笔记应用，用来替代目前在 Notes 里维护 RITM / CHG 工单的流程。

## 功能

- 保存 RITM、CHG、笔记标题、操作步骤、优先级和负责人
- 三个流程区：草稿、UCSF ticket send for approve、UCSF ticket example
- 在详情面板中一键移动工单状态
- 搜索 RITM、CHG 和笔记内容
- 数据自动保存到 macOS Application Support
- 示例数据已按当前 UCSF / Panorama 工作流程预置

## 运行

需要 macOS 14+ 和 Xcode 15+：

```bash
swift run
```

生成可双击打开的 macOS App：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Ticket Organizer.app"
```

也可以用 Xcode 打开 `Package.swift` 后运行。
