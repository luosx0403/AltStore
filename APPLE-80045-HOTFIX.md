此临时补丁针对 macOS 27 本地 AltServer 提供 Anisette 数据时，iPhone AltStore 登录／Refresh All 返回 Apple GrandSlam `-80045` 的路径。

用户已确认：第一阶段 Mac 补丁的菜单「Install AltStore」安装成功，但旧 iPhone AltStore 内登录／Refresh All 仍失败。安装中的 Mac 二进制与第一阶段云端产物一致。v2 因此同时构建 Mac AltServer 和 iPhone AltStore；只更换 Mac 不会修改旧 iPhone App 的认证代码。

父仓库基于官方 classic `fafd76ee1a8a19c723146de278660aacce9ded5d`，分支 `hotfix/apple-80045`，AltSign 基线 `0d3c1a3cac608e724ca0c8d7404253cd5fee9495`。原 marketplace 分支保留。

运行时改动：

- `ALTAnisetteData` 增加可选 `authenticationDeviceDescription`；Mac 本地 Android CoreADI 提供方设置 Pixel 5 / Android 11 身份，经现有 ServerProtocol JSON 传到 iPhone。复制、JSON、NSSecureCoding 均保留该字段；缺少字段的旧数据仍可解码。
- 实际 AltSign 认证源码的 GrandSlam GsService2 init、complete、apptokens 使用此字段；未收到字段时沿用原身份，macOS 27 保留第一阶段 fallback。未全局替换 `deviceDescription`，AnisetteKit provisioning、短信及 Developer API 的身份不变。
- complete 返回 hsc=409 且 au 缺失或为空时，提示输入已推送的可信设备验证码，跳过重复发送。明确的 trustedDeviceSecondaryAuth 与 secondaryAuth/SMS 保留原流程。
- 保留现有 User-Agent、每次请求新建 ephemeral session 和 HTTP 5xx 处理。没有修改 Remote AltServer v3 路径；本次验证范围是本地 Mac 提供方。

验证：

- 12 个 macOS 认证用例、12 个 iOS 身份路由用例、8 个原生 Objective-C 传输／归档用例全部通过。认证用例执行实际 Swift 源码，替换密码学和网络依赖；iOS 路由用例在 Mac 上禁用 macOS fallback，不代替真机测试。
- 完整 AltSign-Static 在本机 CLT 编译成功。无需本机安装完整 Xcode，完整 App 构建使用 GitHub 的 Xcode 27 runner。
- Mac 第一阶段真实安装已由用户确认成功；v2 真机登录、Refresh All 与后续安装效果仍须用户验证。未读取用户账号凭据或改变 Anisette provisioning。

v2 云端构建成功：

- Actions：https://github.com/luosx0403/AltStore/actions/runs/38628576135
- 实际编译 commit：cdf7ae021f4cf28ce7a5df1dfe86b442df2b68ad。
- Mac：AltServer-80045-v2-arm64.zip，1.8 / build 97，最低 macOS 27.0，arm64，9,992,471 字节。SHA-256：fb00c93a99e8f2dcc8561b2a085c5f9021496af060f7da60ff89990873433f75。
- iPhone：AltStore-80045-v2.ipa，2.3 / build 64，最低 iOS 17.4，arm64，41,638,496 字节。SHA-256：fbe51095bd319f668955916039fe6d50c9368a5e5e1c887fd484e18469d2d94e。
- 已下载核对两份校验和、架构和 LC_BUILD_VERSION。Mac 全部嵌套代码严格签名验证通过，确认嵌入 Pixel 5 身份及传输字段；IPA ZIP 完整性检查通过，确认是 iPhoneOS 构建，AltStoreCore.framework 含新增身份字段。v2 真机 Refresh All 尚未测试。
- Mac 使用个人 ad-hoc 签名，未做 Developer ID 签名或公证；iOS IPA 由 AltServer 重新签名。版本号保留源工程标签。

安装顺序：

1. 退出旧 Mac AltServer，将 v2 ZIP 中的 AltServer.app 替换到 /Applications 后启动。
2. 连接 iPhone，按住 Option 点击 Mac 菜单栏 AltServer，选择「Sideload .ipa…」和目标手机，选择 v2 IPA，用原来的 Apple ID 签名并覆盖安装现有 AltStore。
3. 打开 iPhone AltStore，重试登录／Refresh All；如收到验证码，按提示输入。

v2 IPA 是未签名的构建产物，由 AltServer 为用户签名安装。安装本次补丁须选择此 IPA；普通「Install AltStore」入口下载官方 IPA。覆盖安装时保留原 App，使用相同 Apple ID。AltServer 的安装代码会重写 ALTDeviceID／ALTServerID，并附带该设备的证书／配对文件。

可重放的源码与构建入口：

- AltSign 是子模块；父仓库通过 `Patches/apple-80045-altsign.patch` 保存认证及模型修改，通过 `Patches/xcode-27-altsign-build.patch` 保存 Static 产品声明。未引用不可拉取的本地 submodule commit。
- 新 clone 递归检出依赖后，执行 `sh scripts/apply-apple-80045-hotfix.sh`；脚本可重复运行，基线不匹配时停止。
- `.github/workflows/altserver-hotfix.yml` 在分支 push 或手动 dispatch 时，分别构建 Mac arm64（最低 macOS 27）与 iPhone arm64（最低 iOS 17.4）。Mac 逐层 ad-hoc 签名并执行严格签名验证；iOS 以关闭签名方式构建并打包 Payload/AltStore.app。无需上传 Apple ID、证书或密钥。
- bash / pipefail 防止 tee 掩盖构建错误；只构建 normal 变体，关闭旧 CoreCrypto 的重复静态分析。
- AltServer 与 AltJIT 移除未使用的 AltSign-Dynamic 产品依赖，保留实际链接的静态产品；AltJIT 移除指向已不存在 macOS 14 SDK 的私有 CoreCrypto stub，保留自建静态库。
- Xcode 27 移除了 ld_classic，故移除 AltStore 旧链接器参数。旧 libcurl 的 115 个对象及 fragmentzip 的 1 个对象由 `scripts/normalize-ios-static-libraries.py` 在 CI 重新归档为 arm64；脚本逐一验证对象代码字节不变、成员不丢失和 8 字节对齐。仓库原预编译二进制保留。

来源：

- https://github.com/altstoreio/AltStore/issues/1828 （AltServer Android 身份成功实验）
- https://github.com/nab138/iloader/commit/a104a8f
- https://github.com/nab138/isideload/commit/fdb178814103dd7d3163dfd88f289ff0f76e8d47
- https://github.com/nab138/isideload/issues/27
