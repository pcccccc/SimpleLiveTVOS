# 插件 API 凭据宿主接入

## 声明与登录方式

生效 manifest 的 `auth.credentialKinds` 包含 `token` 时，FullUI 提供手动 Access Token 配置；包含 `client_credentials` 时，iOS FullUI 另外提供“Client ID 与 Client Secret”。两种方式均不要求声明 `loginFlow`，不新增虚构的 `loginFlow.kind` 或 HTTP `authMode`。应用凭据入口本轮仅在 iOS 开放，其他宿主不展示该方式。

`LoginPlatformEntry.methods(for:)` 统一生成三端入口：API 凭据、受当前宿主支持的扫码挑战，以及 iOS/macOS 网页登录或 tvOS 手动 Cookie。iOS/macOS 在账号列表点击平台后，两种及以上方式先选择，单一方式直接进入。iOS 使用紧凑的原生 sheet 选择面板，按方式数量与动态字体调整高度，提供带图标的整行选项与独立取消按钮；macOS 保持系统选择菜单。选定后先完成选择界面的关闭，再创建对应登录页面，不自动启动默认方式，也不在登录页内切换方式；取消选择不会启动登录流程。tvOS 保持先展示独立方式按钮的入口。未知登录方式不展示。

API 凭据输入在 iOS 使用普通文本框；应用凭据分别填写 Client ID 与 Client Secret，两项都有内容才允许校验。macOS/tvOS 的 Token 输入保持原生密文控件。手动 Token 支持原始值及 Bearer/OAuth 前缀，前缀规范化由插件处理。API 状态独立于 `PlatformCredentialSyncService.isLoggedIn`，不会赋予个人账号权限。

## 存储与校验

`PlatformAPITokenVault` 使用独立 Keychain service，每个插件仅保存一份当前 API 配置：手动 Token，或完整的 Client ID / Client Secret。继续使用旧存储项并兼容旧 Token 记录，成功切换时原子替换整份配置，不保留两种同时生效的凭据。凭据与校验元数据均在 Keychain 中，设置为本机保存；不进入 UserDefaults、Cookie session、iCloud 或局域网凭据同步。清除只删除该插件的 API 配置，旧 Cookie 同步不能回填。

候选校验租用生效插件版本，在一次性 runtime 内调用 `validateCredential({apiToken})` 或 `validateCredential({clientId, clientSecret})`，限时 30 秒；插件必须声明候选的凭据种类。候选 runtime 的 Cookie session 为空，正式业务 runtime 不可见候选值。只有返回 `state=valid`、与候选一致的 `credentialKind`、`authorizationType=api` 且未过期时才提交；应用凭据还要求返回的 `clientId` 与配置一致。取消、无效响应、网络或 Keychain 失败保留原记录。

每次业务调用读取 Keychain 并登记当前凭据代次。替换/清除在同一 actor 操作中写入存储、推进代次并驱逐缓存 runtime；随后取消旧 runtime 的 Promise 和 HTTP 工作，禁止迟到的脚本再发起 HTTP。返回值交付前再次核对代次，旧结果不能通过。候选提交也核对代次，避免清除后被迟到校验覆盖。

API 凭据功能由三端 FullUI 生命周期启用。ShellUI 不安装该生命周期，也没有 API 输入入口。

## 调用与状态

宿主只在以下方法中注入当前配置对应的 `payload.apiToken` 或 `payload.clientId` 与 `payload.clientSecret`，忽略普通调用者试图覆盖这三个字段的值：

- `validateCredential`、`getCredentialStatus`
- `getCategories`、`getRooms`、`search`
- `getRoomDetail`、`getLiveState`、`resolveShare`

其他函数（包括播放和弹幕）移除这三个字段。API 凭据不通过 `setCredential` 或 Cookie 注入。插件必须在每次请求中读取业务参数，不能依赖上次校验残留的内存值。

`CredentialStatus` 可解码 `clientId`、`credentialKind`、`authorizationType`、`tokenType`。`expireAt` 使用 Unix 秒，0 表示未知。页面显示“API 已连接 / 未配置 / 已失效 / 已过期”，失败单独提示“校验失败”，保留已有凭据与状态。API 身份不展示个人账号昵称。

FullUI 启动、回到前台及活跃期间每小时检查已配置插件。校验状态写回 Keychain；无效/过期状态触发内容失效，但不自动删除 Token。普通业务调用中的标准 `AUTH_REQUIRED` 错误只在明确的 API 凭据失效原因下更新 API 状态；`UPSTREAM` 等错误保留错误类别，不解释为 Token 过期。

手动 Token 不自动刷新，用户通过“校验并替换”提交新值。应用凭据方式由插件负责授权交换、令牌缓存、到期更新和失效重试；宿主只保存应用凭据和状态元数据，不保存插件换取的 Access Token。切换方式须重新校验，成功后替换当前配置。

## HTTP、日志与缓存

API runtime 从加载起持续隐藏插件控制台与任意响应文本，错误只保留标准错误类别和允许的协议原因；输入值不能进入诊断输出。即使插件在异步回调中输出 Token，也仍处于静默 runtime。

手动 API 凭据校验的一次性 runtime 允许例外诊断：HTTP 4xx/5xx 响应中的通用 `status`、`code`、`error`、`message`、`reason` 等错误字段，在候选 Token、Client Secret 和实际 Authorization 头凭据脱敏后写入 `[JSRuntime][HTTP][LOGIN]` 日志和开发者控制台的 HTTP 响应体。实际请求头也参与脱敏，以覆盖插件刚换取、宿主未持久化的令牌。未知字段、成功响应、请求头及请求体仍隐藏；非 JSON 或过大的响应只记录省略原因。该例外不应用于后台状态检查、普通内容调用或 ShellUI。

API runtime 的 HTTP 请求关闭系统 Cookie 处理、URLCache 和请求合并/响应缓存，并传递 `followRedirects`；`false` 在首个 3xx 停止。宿主不添加 Token header，具体 Authorization 请求头由插件构造。现有跨源凭据头移除规则继续生效。

API 凭据插件的分类数据绕过宿主磁盘缓存，交由插件在校验授权后使用自己的缓存。凭据变更清除该插件首页快照，并重建 FullUI 的首页、分类、房间列表和搜索状态，重新从第一页加载。

## 验证边界

自动测试使用中性插件、内存安全存储替身和模拟 HTTP，覆盖：Token-only / 应用凭据 / 多方式入口、每次注入、跨插件隔离、播放/弹幕无 API 凭据、候选失败/取消、凭据种类切换、旧存储兼容、Client ID 不匹配、存储失败、旧 Promise 取消、清除后的代次保护、状态恢复、网络失败保留凭据、错误脱敏、禁止跳转及 HTTP 缓存隔离。既有 Cookie、扫码挑战与首页缓存测试继续回归。

真实有效凭据的上游正向联调、超过一个分页批次的实际内容、撤销及过期的真实响应，需要配置相应插件并由用户提供自己的测试环境。API 校验成功不能作为播放器画面、声音或受限内容可播放的证明。

### 本次验证记录（2026-09-08）

- Core 相关回归共 92 项测试、6 个 suite 全部通过。
- Xcode 27 workspace MCP 构建 `AngelLive`、`AngelLiveMacOS`、`AngelLiveTVOS` 均成功，构建后的 Issue Navigator error 均为 0。
- iPhone 17 Pro / iOS 27.0 模拟器在最后一次源码修改后重新完成 `DeviceInteractionInstallAndRun`；验证设置 → 平台账号登录 → 点击行中央打开网页登录弹层 → 关闭返回列表。修复了行空白处不能点击的问题，Device Hub session 已结束。
- 初次接入验收时设备仅有网页登录插件，API Token 表单和多方式选择未进行设备操作验证；macOS/tvOS 未进行设备交互验证，真实上游凭据联调未运行。

### 登录方式选择前移后的复验（2026-09-08）

- iOS/macOS 登录入口调整后重新完成对应 workspace MCP 构建，均成功，Issue Navigator error 均为 0。共享凭据逻辑与 tvOS 本轮未修改，未重复运行 Core 测试或 tvOS 构建。
- 最后编辑后重新完成 iPhone 17 Pro / iOS 27.0 模拟器 `DeviceInteractionInstallAndRun`。使用设备已有的双方式插件，验证先展示系统选择菜单、取消后留在列表、选择网页登录后打开网页弹层、选择扫码后打开二维码页面，以及关闭返回列表。
- 单方式插件仍直接进入对应登录页；登录页面不再展示方式 Picker 或相互切换按钮。上述路径均通过，Device Hub session 已结束。
- 未输入真实凭据或完成账号登录；API Token 表单尚无设备插件覆盖，macOS 仅完成构建验证。

### iOS 底部选择面板（2026-09-08）

- 本轮仅调整 iOS FullUI：替换登录方式的 `confirmationDialog`，使用带整行选项与独立取消按钮的紧凑 sheet；其他平台未修改。
- 最终 iOS workspace MCP 构建成功，Issue Navigator error 为 0，并在最后编辑后重新完成 `DeviceInteractionInstallAndRun`。
- iPhone 17 Pro / iOS 27.0 截图确认面板位于屏幕底部，标题、两种登录方式及取消按钮均完整可见；取消、分别选择网页登录和扫码登录、关闭后返回列表、单方式直达均通过，Device Hub session 已结束。
- API Token 表单、iPad 外观、深色外观、真实账号登录及其他平台本轮未验证。

### iOS 普通文本输入（2026-09-08）

- iOS Access Token 输入改为普通 `TextField`，其他平台保留原控件；安全存储、校验和清空逻辑不变。
- iOS workspace MCP 构建成功，Issue Navigator error 为 0。最后编辑后重新安装运行，在 iPhone 17 Pro / iOS 27.0 模拟器验证占位测试文本完整可见，关闭重开后输入为空、保存按钮禁用。
- 未提交测试文本或使用真实凭据；本轮不验证上游授权结果。

### 登录 HTTP 错误诊断（2026-09-08）

- API 凭据、登录注册表和登录事务相关回归共 61 项测试、3 个 suite 通过，包含错误原因可见、凭据脱敏，以及成功响应/非 JSON/超大响应不公开。
- iOS workspace MCP 构建成功、Issue Navigator error 为 0；最后编辑后重新安装运行并确认首页正常，Device Hub session 已结束。
- 未输入 Token 或重现真实授权请求；macOS/tvOS 宿主本轮未构建。

### iOS 应用凭据方式（2026-09-08）

- Core 相关回归共 99 项测试、6 个 suite 通过，新增应用凭据注入、切换、状态恢复、旧记录兼容与诊断脱敏覆盖。
- Xcode 27 workspace MCP 构建 `AngelLive`、`AngelLiveMacOS`、`AngelLiveTVOS` 均成功；各次 `GetBuildLog` error 结果为 0。当前 MCP 工具清单未提供 Issue Navigator 查询，未将构建日志检查表述为 Navigator 检查。
- 最后源码编辑后，于 12:16:49 发起新的 `DeviceInteractionInstallAndRun`，12:17:26 前返回安装运行成功；设备为 iPhone 17 Pro / iOS 27.0。两方式底部面板标签完整可见，取消返回账号列表；两个应用凭据输入框显示普通文本，填齐可校验、缺项禁用，关闭重开清空输入。
- 手动 Access Token 入口、普通文本显示与关闭重开清空同样通过；验收后返回账号列表并结束 Device Hub session。
- 设备目标插件与指定订阅源已是当前版本且健康，未重复安装插件。未提交测试凭据，真实上游授权及自动续期未运行；macOS/tvOS 本轮仅验证构建，未开放应用凭据入口或执行设备交互验收。
