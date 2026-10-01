# 影随 / YingSui —— 构建与发布指南

本文档记录三平台构建的完整流程，以及**已经踩过的坑**。
下次构建遇到问题，优先查这里。

---

## 一、环境准备（只需一次）

本机工具链装在仓库同级目录 `.toolchain/` 下，不污染系统。
**每开一个新终端都要先加载环境：**

```bash
source /Users/Admin/Documents/deepseek-harness/toolchain-env.sh
```

加载后应看到 Flutter / CocoaPods / JDK / Android SDK 四项都已就绪。

工具链构成：

| 组件 | 版本 | 位置 | 说明 |
|---|---|---|---|
| Flutter | 3.44.4 | `.toolchain/flutter` | Dart 3.12.2 |
| Ruby | 3.4.11 | `.toolchain/ruby` | 便携版，**系统 Ruby 2.6 装不了新版 CocoaPods** |
| CocoaPods | 1.17.0 | `.toolchain/ruby-gems` | iOS/macOS 插件依赖 |
| JDK | 17.0.13 | `.toolchain/jdk-current` | Android 构建 |
| Android SDK | 36.0.0 | `.toolchain/android-sdk` | 命令行版，无需 Android Studio |
| Xcode | 27.0 | `/Applications/Xcode.app` | **必须在 App Store 单独安装** |

**关键环境变量**（`toolchain-env.sh` 已包含）：

```bash
export HOME=.toolchain/home      # 必须！Flutter/Xcode/Java 都要写用户目录
export JAVA_OPTS="-Duser.home=$HOME"   # Java 不认 HOME，必须显式覆盖
export PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

## 二、ffmpeg：AI 字幕的必需组件

**这是最容易漏掉、也最容易误判的一步。**

应用在 macOS/iOS 上靠一个**内置的精简版 ffmpeg** 做音频提取与分段，
查找路径固定为 `Contents/Resources/ffmpeg/ffmpeg`。

**`flutter build` 不会自动打包它**，缺少时应用内会报：

> 应用内置音频组件缺失或无法运行，请重新安装最新版本

首次构建前先编译一次：

```bash
# macOS（本机编译）
bash tool/ffmpeg/build_ffmpeg.sh macos-arm64 build/ffmpeg-bundle/macos-arm64

# iOS（交叉编译，用 iphoneos SDK）
bash tool/ffmpeg/build_ffmpeg.sh ios-arm64 build/ffmpeg-bundle/ios-arm64
```

约 3–8 分钟，产物约 2.6 MB。构建脚本会自动把它嵌入应用包。

### 音轨兼容性

ffmpeg 是裁剪编译的，只保留必要编解码器。
**曾漏掉 DTS**，导致大量 1080p/4K 影视资源（常见 DTS 5.1 音轨）报
`no decoder found for: dts`。

当前已覆盖：AAC / AC3 / EAC3 / **DTS（dca）** / TrueHD / MLP / FLAC /
MP3 / MP2 / Opus / Vorbis / WMA / ALAC / Cook / 各种 PCM 与 ADPCM。

**对照验证**（用真实影视文件测试音频分段）：

```bash
build/ffmpeg-bundle/macos-arm64/ffmpeg -y -t 30 -i "你的视频.mkv" \
  -vn -ac 1 -ar 16000 -b:a 24k -f segment -segment_time 10 \
  -reset_timestamps 1 /tmp/chunk_%05d.m4a
```

正常应看到 `speed= 200x` 左右并生成若干 `.m4a`。

---

## 三、构建

### 一键构建全部

```bash
./scripts/build-all.sh              # macOS + Android + iOS
./scripts/build-all.sh macos        # 只构建 macOS
./scripts/build-all.sh android ios  # 指定多个
```

### 分平台

| 平台 | 命令 | 产物 |
|---|---|---|
| macOS | `./scripts/build-macos.sh release [dmg]` | `YingSui.app`（已签名） |
| Android | `flutter build apk --release --flavor prod` | `app-prod-release.apk` |
| Android | `flutter build appbundle --release --flavor prod` | `.aab`（上 Google Play 用） |
| iOS | `./scripts/build-ios-ipa.sh` | `YingSui-<版本>-unsigned.ipa` |
| Web | `flutter build web --release` | `build/web` |

---

## 四、签名

### Android（必须配置才能上架）

```bash
./scripts/create-android-keystore.sh
```

生成 `android/yingsui-release.jks` 与 `android/key.properties`。

> **密钥库一旦用于发布就永久不能更换。**
> 丢失 = 无法再更新已发布的应用，只能换包名重来。
> 请立刻备份到密码管理器等安全位置。

`android/.gitignore` 已忽略密钥文件，不会误提交。

**踩坑**：Gradle 的 `file()` 相对 `android/app/` 解析，
因此 `key.properties` 中必须写：

```
storeFile=../yingsui-release.jks
```

写成 `android/yingsui-release.jks` 或 `../android/yingsui-release.jks` 都会失败。

### macOS

脚本使用 ad-hoc 签名（`codesign -s -`）。

**注意**：`~/Documents` 下的目录若受 iCloud 同步影响，会给产物贴上
`com.apple.FinderInfo`，导致 codesign 报
`resource fork, Finder information, or similar detritus not allowed`。
脚本的做法是在 `/tmp` 下 `ditto --norsrc --noextattr` 做干净拷贝后再签名。

**用户侧安装**：未做 Apple 公证，首次打开需
**右键 → 打开**，或在「系统设置 → 隐私与安全性」点「仍要打开」。

### iOS

产出的是**未签名 IPA**，需交第三方签名服务（企业签/超级签）重签，
或用自有 Apple 开发者证书导出：

```bash
xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist <plist>
```

---

## 五、已知坑位速查

| 现象 | 原因 | 解决 |
|---|---|---|
| `Unable to create log store directory` | 沙箱禁止写 `~/Library/Developer/Xcode` | 构建需提权，或把 HOME 指向可写目录 |
| `Could not resolve package dependencies` | SwiftPM 缓存目录不可写 | 同上 |
| `resource fork, Finder information...` | iCloud 目录给产物贴扩展属性 | 用 `/tmp` 干净拷贝后签名（脚本已处理） |
| `There may only be up to 1 unique SWIFT_VERSION per target` | 插件 podspec 的 Swift 版本不一致 | 统一 podspec；移除 Podfile 里空的 RunnerTests 目标 |
| `range of supported deployment target versions is 15.0 to 27.0.x` | Xcode 27 抬高了最低 iOS 版本 | 工程与 Podfile 统一为 15.0 |
| `Automatically assigning platform iOS...` | Podfile 未声明 platform | 取消 `platform :ios, '15.0'` 的注释 |
| `flutter build ios` 报找不到 Xcode 项目 | Flutter 3.44 的 SPM 解析缺陷 | 改用 xcodebuild 直接构建（脚本已处理） |
| `no decoder found for: dts` | ffmpeg 未编译 DTS | 见第二节，重新编译 |
| `SUCCESS_WITH_NO_VALID_FRAGMENT` | 阿里云对静音分片返回 FAILED | 已改为跳过该分片继续（见 asr_subtitle_job.dart） |
| AI 字幕报「音频组件缺失」 | 应用包内没有 ffmpeg | 见第二节 |

---

## 六、发布前检查清单

- [ ] `source toolchain-env.sh` 环境已加载
- [ ] `flutter analyze` 无问题、`flutter test` 全过
- [ ] ffmpeg 已为对应平台编译并嵌入
- [ ] Android 已配置正式密钥（否则无法上架）
- [ ] 版本号已在 `pubspec.yaml` 提升
- [ ] 应用图标已生成（`python3 tool/brand/generate_icons.py --concept C --out .`）
- [ ] 域名已填入 `lib/config/app_links.dart`（如已注册）

---

## 七、macOS release 构建需要给 Flutter 打补丁

**这是 Flutter 3.44.4 自身的 bug，不是本项目的问题。**

### 现象

macOS **release** 构建失败，报：

```
Target release_unpack_macos failed: Exception: Binary .../FlutterMacOS
does not contain architectures "arm64 x86_64".
lipo -info:
Architectures in the fat file: ... are: x86_64 arm64
```

**注意矛盾之处**：`lipo -info` 明确说两个架构都在，却仍报"不包含"。

### 根因

`flutter_tools` 在打包 framework 时执行的是：

```bash
lipo <framework> -verify_arch x86_64 arm64
```

但 **`lipo -verify_arch` 一次只接受一个架构参数**，传多个会把第二个当成
「额外输入文件」：

```
lipo: -verify_arch requires exactly one input file   （退出码 1）
```

于是校验失败。逐字验证：

| 命令 | 结果 |
|---|---|
| `lipo <fw> -verify_arch x86_64 arm64` | ❌ 退出码 1（Flutter 的写法） |
| `lipo <fw> -verify_arch x86_64` | ✅ 退出码 0 |
| `lipo <fw> -verify_arch arm64` | ✅ 退出码 0 |

**关键**：无论 framework 是单架构还是双架构都会失败——问题出在**参数个数**，
不在架构本身。debug 构建恰好只传一个架构（arm64），所以能过。

### 解决

项目内已提供补丁与脚本：

```bash
./scripts/patch-flutter-macos-release.sh
```

它会：
1. 把 flutter_tools 的架构校验改为**逐个验证**（幂等，已打过会跳过）
2. 删除快照与 stamp 并**重新生成 flutter_tools 快照**

> 快照只在 revision 变化时才自动重建，改源码不会生效，必须手动重建——
> 脚本已包含这一步。

**何时需要重跑**：`flutter upgrade` 或 Flutter 升级之后
（快照会被重新生成，覆盖补丁）。

补丁文件保存在 `tool/patches/flutter-lipo-verify-arch.patch`。

打上补丁后，macOS release 产物为**通用二进制（x86_64 + arm64）**，
体积约 121 MB（debug 为 221 MB 且仅 arm64）。
