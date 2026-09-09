# 插件 API 凭据宿主接入

更新时间：2026-09-09。设备码授权扩展见下节；原有手动 Token、应用凭据与 Cookie 协议继续独立生效。

## 设备码授权

manifest 的 `auth.credentialKinds` 显式包含 `oauth_device_code` 时，三端 FullUI 把“登录（插件显示名）”列为首个登录方式；多方式插件保留选择入口及原有高级凭据方式。设备码无需声明 `loginFlow` 或 `loginChallenge`，不新增 HTTP `authMode`，也不复用 Cookie 二维码的 `login_transaction` / `confirmed` 提升逻辑。宿主不配置具体平台的应用 ID、域名或接口。

账号入口先判断已有凭据：iOS/macOS 存在 API 安全记录时打开账号管理页（包括过期或失效记录），提供状态、重新校验、更换登录方式和退出操作；Cookie 已登录时进入原有账号验证页。没有已有账号时才直接选择登录方式。tvOS 保留平台详情入口，并提供 API 账号信息与凭证验证。重新打开账号页不会发起新的设备授权；主动更换登录方式后取消也不会删除已有凭据。上述入口仅用于 FullUI。

| 插件函数 | 入参 | 返回与宿主行为 |
| --- | --- | --- |
| `startDeviceLogin` | `{ loginId }`，每次由宿主生成新的 UUID | `state=waiting`、同一 `loginId`、`userCode`、`verificationUri`、`expiresAt`、`interval` / `retryAfter`；使用插件默认 Public Client ID |
| `pollDeviceLogin` | `{ loginId }` | `waiting` 按新的退避间隔继续；`authorized` 带敏感候选 `credential`，此时尚未连接；`denied` / `expired` / `failed` 停止轮询 |
| `cancelDeviceLogin` | `{ loginId }` | 仅清理匹配尝试，不能删除已保存账号或取消新尝试 |
| `refreshDeviceCredential` | `{ credential }`，完整安全记录 | 返回新的 `{ credential }`；先持久化新 Token 对，再校验或继续浏览 |
| `resetDeviceAuth` | `{}` | 清理授权、刷新与分页内存；退出或切换时与 runtime 淘汰及宿主代次失效配合 |

时间戳均为 Unix 秒，轮询间隔为秒。页面原样显示 `userCode`，用本机 Core Image 将 HTTPS `verificationUri` 编成二维码；iOS/macOS 同时可打开授权页面。二维码及设备码只存在于当前页面内存；关闭页面取消该尝试，过期后由用户重新生成。页面不接收 Token，也不收集密码或 Client Secret。

授权成功后显示独立的确认内容：成功图标、“登录成功”、一条平台连接状态，以及全宽“完成”主按钮。退出登录收进“账号选项”菜单，不与完成操作争夺视觉重点。iOS 成功状态使用可展开的紧凑弹层，无障碍大字体保留大弹层与滚动；二维码阶段保持原有布局。macOS 同步缩小成功状态的最小内容高度，tvOS 使用相同结果内容。

`PlatformDeviceAuthCoordinator` 由 API vault 持有，同一安全记录只对应一个协调者。每插件的任务链串行执行跨 `await` 的登录与刷新操作。一次设备登录租用同一版本的独立 runtime，start、poll、validate、cancel 共用该实例；未提交候选不影响已登录账号的业务 runtime。插件 reload、pin 或版本更新不改变在途尝试的版本。

设备凭据结构为 `{schemaVersion:1, kind:"oauth_device_code", clientId, accessToken, refreshToken, expireAt, userId?, userName?}`。只接受完整且未过期的候选，调用 `validateCredential({credentialKind, clientId, apiToken})` 验证 `state=valid`、匹配的 Client ID、非空用户身份、`authorizationType=api`、`tokenType=user_access_token` 和有效期。校验成功后将用户身份加入记录，再原子替换当前 API 配置。候选失败、网络或存储失败、提交前取消均保留旧账号。原子保存已开始时，取消等待提交结果；保存成功后的取消返回已连接语义，删除账号必须使用退出操作。

设备 Token 对与身份元数据仅进入原有本机 Keychain service，不进入 Cookie session、UserDefaults、Host.storage、iCloud 或 Bonjour。旧手动 Token / 应用凭据记录继续可读。不能给缺少 Client ID 的旧设备记录套用插件默认 ID，也不能将已存 Token 改绑到其他应用。每台设备独立授权和刷新。

启动、前台恢复、活跃期间每小时及每次浏览前确保授权有效。剩余有效期不超过 60 秒时刷新；并发请求共用串行协调后的最新记录。新 Token 对先写 Keychain，再校验身份；校验网络失败保留新记录。若轮换写入失败，vault 在内存中保留新值，下次只重试写入，禁止回读旧磁盘 Refresh Token 再次刷新；此时若进程退出，新值可能丢失并需要重新登录。

业务注入范围沿用下文白名单，设备模式每次注入 `credentialKind`、`clientId`、`apiToken` 与已校验 `userId`，仅刷新函数收到 Refresh Token。401 对应的标准 `AUTH_REQUIRED` 最多刷新并重试原业务一次，保留原始分页参数；明确 `oauth_reauth_required` 不循环刷新。第二次认证失败提示重新登录。相同应用与用户的 Token 轮换保留 runtime 和分页缓存，切换账号或授权方式则推进代次、淘汰 runtime、清理业务缓存。播放与弹幕不携带设备 API 凭据。API 授权成功不代表已获取网页 Cookie、订阅播放权益或播放校验结果。

设备授权函数统一走 manager 的内部敏感调用路径（仍执行普通插件 JS 函数），不走 `setCredential` / `clearCredential` 拦截路径。runtime 从加载起持续隐藏入参、成功响应、HTTP 内容、控制台和原始错误；不启用手动 Token 校验的 HTTP 错误正文诊断例外。授权调用有 30 秒超时，无效 JSON 返回按失败处理。插件授权 HTTP 必须使用既有域名白名单；设备授权 runtime 由宿主强制禁止 HTTP 重定向。FullUI 生命周期关闭时不启用设备凭据注入，ShellUI 没有新入口。

## 声明与登录方式

下文描述既有手动 Token 与应用凭据方式；设备授权的流程、刷新与状态差异以上节为准。

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

### 设备码宿主接入验证（2026-09-09）

- Core 相关回归 116 项、7 个 suite 通过，覆盖设备码能力发现、默认应用 ID、同 runtime 领取候选、提前轮询、过期、旧尝试取消、候选失败和清除后的代次保护、并发单次刷新、轮换落盘失败保留新值、校验网络失败、无效轮换响应停止复用旧 Token、401 单次重试与再次失败、播放弹幕无凭据及 FullUI 启用边界，同时回归原 API / Cookie / 扫码事务协议。
- 设备 HTTP 重定向测试含允许跳转的非设备对照和强制拒绝的设备模式；模拟 URLProtocol 在拒绝跳转后通过超时结束原响应，断言以目标请求未发生为准。
- 使用 Xcode 27 toolchain，通过可写临时编译缓存运行 Package 测试；测试期间共享首页磁盘缓存写入受沙箱限制产生警告，因此该缓存的真实落盘未由这次 Package 测试验证。没有使用或同步真实凭据。
- 最后宿主源码修改后，MCP workspace 构建 `AngelLive`、`AngelLiveMacOS`、`AngelLiveTVOS` 均成功，三端构建后的 Issue Navigator error 均为 0。
- 全仓平台标识扫描无命中，测试中的 `liveType` / `siteId` 未发现真实编号映射；ShellUI 目录未修改。

### 设备登录成功页优化（2026-09-09）

- 本轮仅调整共享 FullUI 登录页面的成功状态和原有退出操作的呈现；设备码协议、保存与刷新逻辑未改动。
- 最后源码修改后，iOS、macOS、tvOS workspace MCP 构建成功，Issue Navigator error 均为 0。本轮未重复运行协议单元测试。
- Xcode 27 的 `RenderPreview` 在生成的 `__designTimeSelection` thunk 中出现泛型歧义，未生成成功页图像；普通 workspace 构建不受影响。该工具结果不能作为视觉验收通过的证据。
- 随后使用当前 MCP 的 `RunCodeSnippet`，通过 `UIHostingController` 与原生快照渲染同一个成功组件（中性示例平台，390×400 点、3 倍比例）；原尺寸检查确认图标、标题、单一连接状态、完成按钮及账号选项完整显示，无裁切或重叠。未重新授权或退出已有账号。
- iPhone 17 Pro / iOS 27.0 在最后源码修改及快照运行后重新完成 `DeviceInteractionInstallAndRun`。确认账号列表显示已有 API 连接状态，方式选择中设备登录与两种原有手动凭据入口均可见；未再次发起真实授权，成功页以中性组件快照验收。macOS/tvOS 本轮仅完成构建，未进行设备交互验收。

### 恢复已有账号验证入口（2026-09-09）

- iOS/macOS 恢复已有账号优先进入管理页，API 验证 UI 复用共享凭据服务，tvOS 详情增加同一管理入口；不改变登录协议或 ShellUI。
- 三端最后源码修改后的 MCP workspace 构建成功，Navigator error 均为 0。本轮仅调整 UI，未重复运行协议单元测试。
- iPhone 17 Pro / iOS 27.0 在最后修改后完成新的 `DeviceInteractionInstallAndRun`：已有 API 账号直达管理页、重新校验完成且仍连接、更换方式后取消、再次打开仍进入管理页、完成返回均通过。Device Hub 已结束，没有退出或重新授权。
- macOS/tvOS 仅构建验证；Cookie 已登录分支、退出、失效凭据及深色/大字体未进行本轮设备验收。

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
