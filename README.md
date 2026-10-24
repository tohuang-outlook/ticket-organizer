# Ticket Organizer

原生 macOS SwiftUI 工单笔记应用，用来替代目前在 Notes 里维护 RITM / CHG 工单的流程。

## 功能

- 保存 RITM、CHG、笔记标题、操作步骤、优先级和负责人
- 三个流程区：草稿、UCSF ticket send for approve、UCSF ticket example
- 在详情面板中一键移动工单状态
- 搜索 RITM、CHG 和笔记内容
- 数据自动保存到 macOS Application Support
- 示例数据已按当前 UCSF / Panorama 工作流程预置
- 支持 Git tag 触发 GitHub Actions，自动生成 macOS 发布包

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

默认版本为 `1.0.0`。可以通过环境变量设置版本和构建号：

```bash
MARKETING_VERSION=1.0.0 BUILD_NUMBER=1 ./scripts/build-app.sh
```

产物会生成在 `dist/`：App、ZIP 压缩包和 `SHA256SUMS` 校验文件。发布新版本时创建 tag：

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动构建并创建 Release。若要签名，设置 `SIGNING_IDENTITY` 后运行打包脚本；正式分发还需要配置 Apple Developer 证书和 notarization 流程。

也可以用 Xcode 打开 `Package.swift` 后运行。
