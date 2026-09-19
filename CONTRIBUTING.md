# 参与贡献

欢迎小而清晰的修复、文档改进和功能提案。较大的行为调整请先说明具体使用场景，避免围绕未经确认的接口假设大幅改动。

## 本地开发

macOS 14+、Swift 5.9+，安装 Command Line Tools 或 Xcode，无第三方运行依赖。

```sh
./Scripts/test.sh
./Scripts/build.sh
open dist/szElectricityMeter.app --args --demo --show
```

- `Sources/MeterCore`：月份、阶梯、预算、电费计算和响应解析。
- `Sources/szElectricityMeter`：SwiftUI、AppKit、请求、钥匙串和本机缓存。
- `Tests/MeterCoreTests`：独立断言运行器；计算与解析修改应增加能复现问题的用例。
- `Scripts`：本机架构构建、打包与图标生成。

UI 改动请附演示模式截图，并检查浅色、深色、空数据和设置页面。请导出实际界面的原生 PNG，不要用真实账户截图充当示例。

高清演示截图：

```sh
open dist/szElectricityMeter.app --args --demo --show --screenshot-directory "$PWD/docs/screenshots"
```

在需要的窗口按 `⌘⇧S`，导出该窗口内容的 2× PNG；`⌘⇧M` 打开摘要演示窗口，`⌘⇧P` 打开包含菜单栏圆环与浮窗的完整场景。完整场景复用实际界面组件，背景为演示渐变。文件名自动包含时间戳，提交前按页面内容重命名。导出仅在演示模式可用，不读取屏幕上其他 App 的内容。

## Pull Request

说明问题、修改后的行为和验证结果。提交前运行 `./Scripts/test.sh`、`./Scripts/build.sh`。检查 `git diff --cached`，确保没有凭证、真实电表 ID、个人路径、原始响应或抓包文件。CI 只能检查其覆盖的情形，不能替代这一步。

不提交绕过鉴权、批量代查、共享 Token 或收集用户凭证的实现。不把接口请求或用户数据发送到额外服务。

所有贡献按本仓库 MIT 许可证提供；提交的素材应有可用的许可。涉及第三方 API 时，请说明依据，不把“请求成功”等同于“获得公开集成授权”。

[返回首页](README.md)
