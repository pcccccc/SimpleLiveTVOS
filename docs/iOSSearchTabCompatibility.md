# iPhone 搜索标签兼容

FullUI 的搜索入口在 iOS 27 使用 `TabRole.prominent`，明确保持与主标签组分离的系统外观；iOS 26 继续使用 `TabRole.search`。iPad、旧系统与没有可用插件的 ShellUI 不改变。

Apple 的 `TabRole.prominent` 文档说明，每个 TabView 只能有一个 prominent 标签；没有显式指定时，搜索标签仅可能获得默认突出样式。`tabViewSearchActivation` 控制搜索激活与选择联动，不保证标签分离。

当前搜索框属于搜索页内部的 NavigationStack，使用 `navigationBarDrawer`，没有在 TabView 上配置 searchable。因此此调整保留现有的搜索输入、提交和结果导航，不引入选中标签即弹出键盘的行为。

参考：[TabRole.prominent](https://developer.apple.com/documentation/swiftui/tabrole/prominent)、[TabSearchActivation.searchTabSelection](https://developer.apple.com/documentation/swiftui/tabsearchactivation/searchtabselection)。

## 验证（2026-09-09）

- 最后源码修改后的 iOS workspace MCP 构建通过，Navigator error 为 0。
- iPhone 17 Pro / iOS 27.0 完成新的 `DeviceInteractionInstallAndRun`：搜索呈现为主标签组右侧的独立圆形按钮，点击进入带搜索框的页面，切换设置正常，Session 已结束。
- iOS 26.5 destination 存在，但 Device Hub 拒绝该系统版本（要求 iOS Simulator 27.0 及以上）；未安装、未运行，不作为兼容性实测通过。iPad、深色及大字体未进行本轮设备验收。本轮未新增或运行单元测试。
