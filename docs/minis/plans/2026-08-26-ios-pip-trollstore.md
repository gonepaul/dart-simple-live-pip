# iOS 原生 PiP 与 TrollStore IPA 交付计划

日期：2026-08-26

分支：`pip/ios-trollstore`

上游：`upstream` → `https://github.com/GH4NG/dart_simple_live.git`

## 目标、边界与完成口径

目标是先建立不依赖 Apple 开发者证书的 iOS IPA 基线，再逐步接入原生直播画中画。Android、桌面、MPV 和 MDK 的既有行为必须保持不变；iOS 首版仅要求默认的 MPV/media-kit 播放路径。

本计划中的“可重复”分两层：给定同一个已构建的 `.app`，打包脚本应生成成员顺序、时间戳和 ZIP 元数据均稳定的 IPA；GitHub Actions 则固定 Flutter 版本并记录提交与运行编号，提供可重复执行的构建步骤。当前 `pubspec.yaml` 中若干 Git 依赖仍跟随 `main`，且 `pubspec.lock` 被上游忽略，因此现阶段不能承诺跨时间、逐字节一致的 Flutter 构建输出。

完成口径严格分开：

1. 第一阶段只有 GitHub Actions 的 macOS job 成功并上传 IPA 后，才能称为“iOS 构建基线成功”。
2. 第二、三阶段的 macOS 编译成功只能证明原生代码可构建，不能证明设备 PiP 正常。
3. 只有用户在 TrollStore 安装的构建上确认启动、播放、进入/退出 PiP、回前台恢复均正常后，才能称为“PiP 运行正确”。

当前工作树已完成基线之后的部分 PiP 控制与 Dart 生命周期接入，但完成口径仍以上述构建和真机验证为准；当前没有新的 macOS 构建或 TrollStore 真机结果，因此不声称 iOS 构建或 PiP 运行正确。

### 当前 media-kit 固定版本与 channel API

- `media_kit`、`media_kit_video` 及各平台 `media_kit_libs_*` 当前固定到 `gonepaul/media-kit` 提交 `44fedda7914d4bb4f5bcc403a783bbca2925f388`，不使用浮动分支。
- Dart 使用 method channel `com.alexmercerind/media_kit_video`，调用 `VideoOutputManager.PiPIsAvailable`、`VideoOutputManager.PiPStart`、`VideoOutputManager.PiPStop`；三个方法均传递 `{handle: <media-kit player handle 字符串>}`。
- PiP 状态通过 event channel `com.alexmercerind/media_kit_video/pip_events` 返回，事件包含对应的 `handle` 和 `state`；当前 Dart 状态集合为 `unavailable`、`inactive`、`starting`、`active`、`stopping`、`failed`。
- 当前应用层实现仅支持 iOS 默认 MPV/media-kit 路径；MDK 不声明原生 PiP 能力，Android 继续使用既有 `floating` 路径，桌面行为不变。

## 总体架构

```text
workflow_dispatch
  → Flutter 3.41.4 / macOS runner
  → flutter build ios --release --no-codesign
  → build/ios/iphoneos/Runner.app
  → 保存输入签名中已有 entitlements（若输入未签名，则使用显式声明文件）
  → 逐个 ad-hoc 签名 Mach-O
  → 按目录深度签名 framework / appex / xpc / 内嵌 app
  → 最后签名 Runner.app
  → codesign --verify
  → Payload/Runner.app + 固定顺序/时间戳/ZIP 元数据
  → Simple-Live-iOS-TrollStore-<version>-<run>.ipa
  → GitHub Actions artifact
```

签名身份固定为 `-`，并禁用时间戳。脚本不创建或导入 keychain、证书、provisioning profile，不设置 `DEVELOPMENT_TEAM`、bundle identifier，也不生成 team/application identifier entitlement。`Info.plist` 与应用内容来自原 `.app`。如果输入 `.app` 已签名，先提取其 entitlements 后原样用于外层重签；如果输入未签名且调用者提供 `--entitlements`，使用该现有 plist。仓库当前没有 `ios/Runner/Runner.entitlements`，workflow 只在未来该文件真实存在时传入，绝不凭空生成标识。

## 阶段一：无证书 TrollStore IPA 基线

### 行为与不变量

- 新 workflow 只有 `workflow_dispatch`，权限为 `contents: read`，不改变 `.github/workflows/build.yaml`。
- 使用 `.fvmrc` 中的精确 Flutter 版本，并直接产出 release `Runner.app`。
- `--no-codesign` 阶段不要求 Apple 账号；随后仅使用 macOS 自带 `codesign --sign -`。
- 所有嵌套 Mach-O 先签；代码 bundle 按 `find -depth` 从内到外签；`Runner.app` 最后签。
- 重签之前提取已有 entitlements；不使用 `codesign --deep` 代替显式签名。
- IPA 必须是标准 `Payload/<name>.app` 结构，文件名和 artifact 名均含 `TrollStore`。
- 对相同签名后应用输入，ZIP 使用排序后的成员列表、1980-01-01 时间戳、保留符号链接并移除额外 ZIP 元数据。
- 任一步失败都不上传空产物，打包脚本不覆盖已有 IPA。

### 文件清单

- `.github/workflows/ios-trollstore.yaml`：独立手动构建、解包验签、上传 artifact。
- `scripts/package_ios_trollstore.sh`：entitlements 保存、内到外 ad-hoc 签名、验签与确定性 IPA 封装。
- `scripts/verify_ios_trollstore_baseline.sh`：可在 Linux 运行的关键不变量静态检查。
- `docs/minis/plans/2026-08-26-ios-pip-trollstore.md`：本计划和交付验证说明。
- `.github/workflows/build.yaml`：明确保持不变。

### 精确验证命令

Linux 静态验证：

```bash
cd /root/projects/dart-simple-live-pip
bash -n scripts/package_ios_trollstore.sh
bash -n scripts/verify_ios_trollstore_baseline.sh
scripts/verify_ios_trollstore_baseline.sh
ruby -e "require 'yaml'; YAML.parse_file('.github/workflows/ios-trollstore.yaml')"
test -z "$(git diff --name-only -- .github/workflows/build.yaml)"
git diff --check
```

macOS 本地构建与打包：

```bash
cd /path/to/dart-simple-live-pip
export FLUTTER_VERSION="$(jq -r '.flutter' .fvmrc)"
flutter --version
dart run scripts/prebuild.dart ios
flutter build ios --release --no-codesign
scripts/package_ios_trollstore.sh \
  build/ios/iphoneos/Runner.app \
  dist/Simple-Live-iOS-TrollStore-local.ipa
unzip -t dist/Simple-Live-iOS-TrollStore-local.ipa
VERIFY_DIR="$(mktemp -d)"
unzip -q dist/Simple-Live-iOS-TrollStore-local.ipa -d "$VERIFY_DIR"
codesign --verify --strict --verbose=2 "$VERIFY_DIR/Payload/Runner.app"
rm -rf "$VERIFY_DIR"
```

若以后仓库新增了真实的应用 entitlements 文件，打包命令必须显式传入：

```bash
scripts/package_ios_trollstore.sh \
  build/ios/iphoneos/Runner.app \
  dist/Simple-Live-iOS-TrollStore-local.ipa \
  --entitlements ios/Runner/Runner.entitlements
```

相同 `.app` 输入的封装稳定性检查：

```bash
scripts/package_ios_trollstore.sh build/ios/iphoneos/Runner.app /tmp/Simple-Live-iOS-TrollStore-a.ipa
scripts/package_ios_trollstore.sh build/ios/iphoneos/Runner.app /tmp/Simple-Live-iOS-TrollStore-b.ipa
shasum -a 256 /tmp/Simple-Live-iOS-TrollStore-a.ipa /tmp/Simple-Live-iOS-TrollStore-b.ipa
cmp /tmp/Simple-Live-iOS-TrollStore-a.ipa /tmp/Simple-Live-iOS-TrollStore-b.ipa
```

GitHub Actions 验证（推送前不执行）：

```bash
gh workflow run ios-trollstore.yaml --ref pip/ios-trollstore
RUN_ID="$(gh run list --workflow ios-trollstore.yaml --branch pip/ios-trollstore --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID" --exit-status
gh run download "$RUN_ID" --dir /tmp/simple-live-ios-artifact
find /tmp/simple-live-ios-artifact -name '*TrollStore*.ipa' -print
```

## 阶段二：原生 PiP 控制面与 Dart 状态管理

在改代码前，先读取 `floating` 的 iOS 实现、当前解析到的 `media_kit`/`media_kit_video` 源码及 iOS plugin 注册方式，并把依赖提交 SHA 记录在阶段文档中。控制面采用单一 method channel 和原生事件回调，Dart 状态机至少包含 `unavailable`、`idle`、`starting`、`active`、`stopping`、`restoring`、`failed`；重复 start/stop/dispose 必须幂等。

计划文件：

- 新增 `lib/services/ios_live_pip_service.dart`：平台守卫、method channel、状态流和错误映射。
- 新增 `lib/services/ios_live_pip_state.dart`：不可变状态与错误类型。
- 新增 `ios/Runner/LivePip/LivePipPlugin.swift`：Flutter channel 注册与参数校验。
- 新增 `ios/Runner/LivePip/LivePipController.swift`：`AVPictureInPictureController` 生命周期骨架；此阶段只建立控制面，不声称已有视频画面。
- 修改 `ios/Runner/AppDelegate.swift`：在隐式 Flutter engine 初始化后注册本地 plugin。
- 修改 `ios/Runner.xcodeproj/project.pbxproj`：纳入新增 Swift 文件；不更改既有 team/bundle identifier。
- 修改 `lib/modules/live_room/player/base_player.dart`：增加仅由支持方实现的 PiP 能力接口，默认不改变其他后端。
- 修改 `lib/modules/live_room/player/lib_mpv.dart`：仅 iOS 默认 MPV 路径连接 service；MDK 保持原行为。
- 修改 `lib/modules/live_room/player/player_controller.dart` 与 `player_controls.dart`：iOS 能力判断、按钮和状态反馈；Android 继续走 `floating`。
- 新增 `test/services/ios_live_pip_service_test.dart`：mock channel 下的状态迁移、幂等和错误测试。
- 新增 `test/modules/live_room/player/player_controller_pip_test.dart`：平台分流与非 iOS 回归测试。

验证：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/services/ios_live_pip_service_test.dart
flutter test test/modules/live_room/player/player_controller_pip_test.dart
flutter build ios --release --no-codesign
git diff --check
```

## 阶段三：解码帧到 `AVSampleBufferDisplayLayer`

先对当前解析到的 Predidit media-kit iOS 默认输出链路做源码审计，确认 libmpv 帧回调、像素格式、线程和所有权。不得直接修改 pub cache。若必须改 plugin，建立项目可审计的 fork/固定提交并在 `pubspec.yaml` 的 iOS 相关 override 中引用确定的提交；在审计完成前不虚构 native callback API。

目标数据流为：解码线程提供带时间信息的帧 → 有界队列与格式转换 → `CVPixelBuffer` → `CMVideoFormatDescription` → 单调 PTS 的 `CMSampleBuffer` → 主队列/专用串行队列上的 `AVSampleBufferDisplayLayer.enqueue`。队列必须有背压并优先丢旧直播帧，格式、分辨率或时间基变化时刷新 format description；stop/dispose 后禁止回调访问已释放对象。

计划文件：

- 新增 `ios/Runner/LivePip/SampleBufferVideoRenderer.swift`：display layer、format description、sample timing、flush 与背压。
- 新增 `ios/Runner/LivePip/DecodedFrame.swift`：明确像素缓冲区、尺寸、色彩信息、PTS 和所有权。
- 修改 `ios/Runner/LivePip/LivePipController.swift`：用 sample-buffer content source 创建 PiP controller。
- 修改 `ios/Runner/LivePip/LivePipPlugin.swift`：绑定/解绑当前播放器会话，不传输像素数据到 Dart。
- 修改 `lib/modules/live_room/player/lib_mpv.dart`：传递稳定的原生 player/texture handle，并在 load/stop/dispose 时同步 native 会话。
- 修改 `pubspec.yaml`：仅在源码审计证明必须 fork media-kit 时，改为固定提交；不得使用新的浮动分支。
- 可能新增 `packages/media_kit_ios_live_pip/`：仅当 app 层无法取得帧时承载经过审计的原生适配；最终文件路径以被固定的 plugin 结构为准。
- 新增 `ios/RunnerTests/SampleBufferVideoRendererTests.swift`：单调 PTS、格式变化、队列上限、flush/dispose 测试。
- 新增 `scripts/verify_ios_pip_native.sh`：静态检查 iOS deployment target、framework 使用、channel 名和非 iOS 隔离。

验证：

```bash
flutter analyze
flutter test
scripts/verify_ios_pip_native.sh
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO
flutter build ios --release --no-codesign
git diff --check
```

此阶段必须用真实直播流验证横屏、竖屏、分辨率切换和断流重连；模拟器测试不能代替 TrollStore 真机确认。

## 阶段四：自动后台 PiP、恢复、错误处理与设备验证

自动策略只在“用户允许 + 正在播放 + 原生能力可用 + 当前不是 PiP”时响应后台事件。系统 restore completion handler 必须且只能调用一次；前台恢复、用户关闭、播放失败和 app 销毁都收敛到同一状态机。进入 PiP 失败不得中断主播放器，连续错误需回传可诊断原因。

### 当前任务 C 实现范围

- 新增默认开启并持久化的 iOS 自动 PiP 设置；开关仅在 iOS 播放设置中显示。
- `inactive` 与 `paused` 共同触发 Dart 自动 PiP 策略，并以布尔闩锁合并为一次请求；`resumed` 重置闩锁。原有 `paused` 时暂停弹幕/标记后台、`resumed` 时恢复弹幕/清除后台标记的语义保持不变。
- 自动请求仅在 iOS、设置开启、直播状态有效、播放器已初始化且 `supportsNativePip` 为真时进入现有 media-kit iOS PiP 启动流程；不可用或启动异常只写日志，不显示 toast，也不中断主播放器。
- 纯 Dart 策略测试覆盖设置、平台、直播有效性、原生能力以及 `inactive + paused` 去重和 `resumed` 后重新允许请求。
- 本任务不新增或宣称完成原生 restore completion handler、系统恢复 UI、额外 background mode、macOS 构建或 TrollStore 真机验证；这些仍属于后续原生实现和设备验收范围。

计划文件：

- 修改 `ios/Runner/LivePip/LivePipController.swift`：自动启动、delegate 回调、restore completion、错误收敛。
- 修改 `ios/Runner/Info.plist`：仅按 Apple API 的实际要求调整 background modes；保留现有 `audio`，不添加虚构 capability。
- 修改 `lib/modules/live_room/live_room_controller.dart`：把现有 `WidgetsBindingObserver` 生命周期与 iOS PiP 状态机协调。
- 修改 `lib/modules/live_room/player/player_controller.dart`：自动 PiP 策略、前后台恢复和 UI 状态。
- 修改 `lib/app/controller/app_settings_controller.dart` 与 `lib/modules/settings/play_settings_page.dart`：iOS 自动 PiP 用户开关及持久化。
- 修改 `lib/modules/live_room/live_room_page.dart`：Android `PiPSwitcher` 保持不变，iOS 使用原生状态显示恢复结果。
- 扩展 `test/services/ios_live_pip_service_test.dart` 与 player/controller tests：生命周期竞态、重复回调、失败回退。
- 新增 `docs/minis/ios-trollstore-device-validation.md`：设备/iOS 版本、安装方式、直播源类别、进入/退出路径、音画/恢复/失败结果矩阵，不记录 UDID。

验证：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
scripts/verify_ios_trollstore_baseline.sh
scripts/verify_ios_pip_native.sh
flutter build ios --release --no-codesign
git diff --check
```

真机验收至少覆盖：手动进入/退出、Home 键自动进入、PiP 点回应用、系统关闭 PiP、来电/音频中断、断流重连、横竖屏源、锁屏/解锁、应用强制退出，以及 Android/桌面回归。结果必须来自下载的 GitHub Actions TrollStore artifact。

## 分阶段提交策略

实现时按以下边界分别提交，但本次任务不 commit、不 push：

1. `ci(ios): add TrollStore IPA baseline`
2. `feat(ios): add native PiP control channel`
3. `feat(ios): feed decoded frames to sample buffer display layer`
4. `feat(ios): add automatic PiP lifecycle and restoration`
5. `docs(ios): record TrollStore device validation`

每次 push 前重新运行当阶段全部 Linux 可执行检查、相关 macOS build/test，并执行 `git diff --check`；任何 token、证书、签名身份、provisioning profile 或设备标识都不得进入 Git。

## 已知风险与决策门

- Git 依赖的浮动 `main` 和未跟踪 lockfile 阻止跨时间逐字节构建复现；应在不破坏上游多平台依赖的前提下单独评估固定提交。
- GitHub Action 的大版本标签也可能移动；基线成功后可把 action 固定到审核过的提交 SHA。
- macOS/Xcode 更新可能改变 ad-hoc `codesign` 输出；确定性比较应在同一 runner image 与同一 `.app` 输入上进行。
- TrollStore 是否接受该 IPA、系统是否允许直播 PiP、音频会话是否持续，都必须由用户真机确认。
- media-kit iOS 是否暴露可零拷贝获得的解码帧尚待源码审计；若只能高成本回读画面，需要在阶段三停止并重新评估，而不是以截图轮询冒充帧桥接。
- 仓库 Xcode 工程已有上游 team 与 bundle 设置；本计划不改写它们，`--no-codesign` 使 CI 不需要对应账户。未来也不得凭猜测替换这些值。
