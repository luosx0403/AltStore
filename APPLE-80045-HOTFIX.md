此临时补丁针对 macOS 27 上的本地 AltServer，依据 AltStore #1828 的成功实验与 isideload 的实际源码。

- 父仓库：官方 classic 的 fafd76ee1a8a19c723146de278660aacce9ded5d。
- 本地分支：hotfix/apple-80045；原 marketplace 分支保留。
- AltSign 基线：0d3c1a3cac608e724ca0c8d7404253cd5fee9495。
- 运行时代码：Dependencies/AltSign/AltSign/Sources/ALTAppleAPI+Authentication.swift。

macOS 27 的 AltServer 使用 AnisetteKit 的 Android CoreADI 数据。仅发送到 GrandSlam GsService2 的 init、complete、apptokens 请求改用已在 AltServer 成功实验中使用的 Pixel 5 / Android 11 client info。现有 User-Agent、每次请求创建新的 ephemeral session、HTTP 5xx 检查均保留。macOS 27 之前及 iOS 的 GrandSlam 身份行为保留。

complete 返回 hsc=409 且 au 缺失或为空时，进入可信设备验证码输入，并跳过再次发送验证码。明确返回 trustedDeviceSecondaryAuth 时仍按原流程请求验证码；明确返回 secondaryAuth 时仍走原 SMS 流程。验证成功后仍通过原有流程重新认证。

AnisetteKit lookup/provisioning、ALTAnisetteData.deviceDescription、短信请求和 Developer APIs 均保留原身份。此次未修改 iOS Remote AltServer，也没有生成替换 iPhone 上 AltStore 的 IPA；旧 iOS App 的 Refresh All 仍需另行验证。

已完成验证：

- 实际 AltSign Swift target 与完整 AltSign-Static 静态库均编译成功，包含修改过的认证源码。CLT 编译时用临时 include 路径提供 OpenSSL 头文件。
- `python3 Tests/Apple80045/run.py`：11 个离线用例全部通过，覆盖身份范围、已推送验证码、原可信设备流程、SMS、无需 2FA、无 UI、用户取消、错误验证码、HTTP 503、Apple API 错误和错误密码。
- 对照：原始源码在 GrandSlam 身份检查失败；只改身份的源码在 hsc=409 验证码提示检查失败。
- 测试执行实际认证源码，替换 CAltSign 模型/密码学依赖和 URLSession transport 为离线 fixtures；不测试真实 SRP、真实 Apple 服务或设备安装。
- 未执行 Apple 账号登录、证书创建或 IPA 安装，未读取用户账号凭据。

本机构建限制：本机尚未安装完整 Xcode，不能本地执行完整 xcodebuild。已通过 GitHub Actions 完成整个 AltServer App 的构建、ad-hoc 签名、深度签名验证及 ZIP 打包，无需本机安装 Xcode。

成功构建记录：

- https://github.com/luosx0403/AltStore/actions/runs/38623380907
- 实际编译 commit：216266fa5b53e97915469ad5082d665cef19bc23。
- 产物：AltServer-80045-arm64.zip，Apple Silicon，最低 macOS 27.0。
- 源工程版本标签：AltServer 1.8，build 97；未伪造版本号。
- ZIP SHA-256：adcc7b20c75e4cef35f37b55174e0712ec79e92fd09448c10304ea42dec10676。
- 已下载产物核对校验和、arm64 架构、嵌入的 Pixel 5 身份及全部嵌套代码签名。
- 真实 Apple 登录、2FA、签名和设备安装尚未测试；未替换本机原版 AltServer。

安装完整 Xcode 并完成首次启动后，可从此 clone 执行以下构建尝试；若 Xcode 不在 /Applications，请调整 DEVELOPER_DIR：

```sh
cd "$HOME/Downloads/AltStore"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace AltStore.xcworkspace \
  -scheme AltServer -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/hotfix \
  ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=27.0 \
  BUILD_VARIANTS=normal RUN_CLANG_STATIC_ANALYZER=NO \
  CODE_SIGNING_ALLOWED=NO build
```

该命令是后续构建入口，尚未在完整 Xcode 下执行。成功产物位于 build/hotfix/Build/Products/Release/AltServer.app。运行前需完成本地代码签名；建议先使用独立副本测试，再决定是否替换 /Applications/AltServer.app。修复效果须通过本地 AltServer 实际登录、2FA、签名和安装确认。

AltSign 是子模块，父仓库只会显示 dirty，直接提交父仓库不会保存子模块源码差异。为避免引用无法拉取的本地 submodule commit，已将完整差异保存为 Patches/apple-80045-altsign.patch。新 clone 或恢复基线后执行 `sh scripts/apply-apple-80045-hotfix.sh` 可重放；脚本检测已应用状态，并在不匹配时停止。

已增加 GitHub Actions 构建入口：`.github/workflows/altserver-hotfix.yml`。推送到 hotfix/apple-80045 后自动运行，采用 GitHub 预装 Xcode 27 的 macOS 27 / arm64 runner。Actions 会递归检出固定版本依赖、重放子模块补丁、运行离线回归、构建 AltServer，再对嵌套代码和 App 逐层执行 ad-hoc 签名，上传 ZIP、校验和与日志。无需在本机安装完整 Xcode，也无需上传 Apple ID 或签名证书。该产物供个人测试，未做 Developer ID 签名或 Apple 公证。iOS IPA 不在此次构建范围内。

CI 使用显式 bash / pipefail，保证 tee 不会掩盖 xcodebuild 失败。此个人 arm64 构建针对用户的 macOS 27，统一以 MACOSX_DEPLOYMENT_TARGET=27.0 构建；无需修改 AltJIT 使用的较新 API 来兼容旧系统。此 App 只构建 normal 变体，关闭 CoreCrypto 默认启用的 deep static analyzer，避免生成 trace/noasm 变体和重复分析。源工程和依赖原有部署配置保留。

`Patches/xcode-27-altsign-build.patch` 将名为 AltSign-Static 的 SwiftPM 产品明确声明为 static；同时移除 AltServer 及其 AltJIT 辅助程序中未使用的 AltSign-Dynamic 产品依赖。实际链接阶段使用 Static，但旧目标列表仍额外要求 Dynamic，导致 Xcode 27 生成中间 ldid.framework 并因无法解析父工程链接的 OpenSSL 符号失败。此次只保留 App 使用的静态产品，使用源工程已有的 OpenSSL/CoreCrypto 链接关系。AltJIT 还移除了指向已不存在的 macOS 14 SDK 的旧私有 CoreCrypto stub，保留自建 corecrypto_static.a。测试目标的 Dynamic 产品依赖保留。应用脚本同时重放认证补丁和 SwiftPM 构建补丁；这是构建方式修正，不涉及认证协议。

只撤回本补丁时，在确认没有后续重叠修改后执行：

```sh
git -C Dependencies/AltSign apply --reverse --check ../../Patches/apple-80045-altsign.patch
git -C Dependencies/AltSign apply --reverse ../../Patches/apple-80045-altsign.patch
```

来源：

- https://github.com/altstoreio/AltStore/issues/1828 （akseltorgerson 的成功实验）
- https://github.com/nab138/iloader/commit/a104a8f
- https://github.com/nab138/isideload/commit/fdb178814103dd7d3163dfd88f289ff0f76e8d47
- https://github.com/nab138/isideload/issues/27
