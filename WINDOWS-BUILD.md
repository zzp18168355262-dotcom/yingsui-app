# 英语角 / English Corner —— Windows 构建与发布指南

---

## 零、先看这条：Windows 包只能在 Windows 上编

**Flutter 不支持交叉编译桌面端。** 在 macOS 上执行 `flutter build windows`
会被直接拒绝（本机实测的原话）：

```
"build windows" only supported on Windows hosts.
```

所以本机（Mac）**不可能**产出 `.exe`，`scripts/build-all.sh` 也刻意没有
把 windows 列进去。有两条路：

| 路线 | 做法 | 适合 |
|---|---|---|
| **A. 自己的 Windows 电脑** | 跑 `scripts/build-windows.ps1`（本文档主体） | 手边有 Windows 机器，想立刻拿到包 |
| **B. GitHub Actions** | 推一个 `v*` tag，`.github/workflows/release.yaml` 里现成的 `windows` job 自动产出 zip | 仓库已推到 GitHub，想长期自动化 |

> 路线 B 的 workflow **已经写好并且是完整的**（编 ffmpeg → 冒烟测试 →
> `flutter build windows` → 补 ffmpeg → 打 zip → 发 Release）。
> 唯一前提是仓库得有个 GitHub 远端 —— 目前 `git remote -v` 是空的。

---

## 一、环境准备（Windows 机器，只需一次）

| 组件 | 版本 | 说明 |
|---|---|---|
| Flutter | **3.44.4** | 必须与其他平台一致，否则 Dart/引擎行为可能有差异 |
| Visual Studio 2022 | 17.x | 必须勾选「**使用 C++ 的桌面开发**」工作负载 |
| MSYS2 + MINGW64 | 最新 | **只用来编内置 ffmpeg**，不装也能编主程序 |

装完 Flutter 后新开一个 PowerShell，确认：

```powershell
flutter --version     # 应显示 3.44.4
flutter doctor        # Windows 那一节应是 [√]
```

`flutter doctor` 里应看到类似：

```
[√] Visual Studio - develop Windows apps (Visual Studio Community 2022 17.x)
```

---

## 二、内置 ffmpeg（最容易漏的一步）

应用在 Windows 上靠一个**内置的裁剪版 ffmpeg** 做音频提取与分段，
查找路径固定为：

```
<exe 所在目录>\ffmpeg\ffmpeg.exe
```

（见 `lib/features/player/presentation/desktop_ffmpeg.dart` 第 16 行）

**`flutter build` 不会自动打包它。** 缺了的话，应用不会崩，但用户一点
AI 字幕就会看到：

> 应用内置音频组件缺失或无法运行，请重新安装最新版本

### 编译它

安装 MSYS2（<https://www.msys2.org/>）后，打开 **MSYS2 MINGW64** 终端：

```bash
pacman -S --needed make diffutils nasm mingw-w64-x86_64-gcc
```

然后回到**仓库根目录**：

```bash
bash tool/ffmpeg/build_ffmpeg.sh windows-x64 build/ffmpeg-bundle/windows-x64
```

约 3–8 分钟。**验证**：

```bash
build/ffmpeg-bundle/windows-x64/ffmpeg.exe -version
```

`build-windows.ps1` 会自动把它复制进发布目录，并实测一次
`ffmpeg.exe -version`；跑不起来会直接报错，而不是等用户在应用里发现。

> **音轨兼容性**：ffmpeg 是裁剪编译的，已覆盖 AAC / AC3 / EAC3 /
> **DTS（dca）** / TrueHD / FLAC / MP3 / Opus / Vorbis / WMA / ALAC /
> 各种 PCM 与 ADPCM。影视资源常见的 DTS 5.1 音轨必须支持，
> 详见 `BUILD.md` 第二节。

---

## 三、一键构建

在仓库根目录的 **Windows PowerShell** 里：

```powershell
.\scripts\build-windows.ps1
```

它会依次：检查 Flutter → 打印版本 → 校验内置 ffmpeg → `flutter pub get`
→ `flutter build windows --release` → 把 ffmpeg 补进发布目录并实测
→ 打包 zip → 打印 SHA256。

产物：

```
dist\EnglishCorner-<版本>-windows-x64.zip
```

### 参数

| 参数 | 作用 |
|---|---|
| `-SkipPackage` | 只构建，不打包。产物留在 `build\windows\x64\runner\Release\` |
| `-SkipFfmpeg` | 允许缺少内置 ffmpeg（只想先看界面时用；AI 字幕会不可用） |

---

## 四、产物形态与分发（重要）

`build\windows\x64\runner\Release\` 里是**一整个目录**：

```
yingsui.exe                 ← 主程序
*.dll                       ← Flutter 引擎 + 各插件
data\                       ← Dart AOT 快照、图标、资源
ffmpeg\ffmpeg.exe           ← 本脚本补进去的内置音频组件
```

**必须整包分发。** 只把 `yingsui.exe` 单独拷给别人，双击会报缺 DLL。

用户侧：解压整个 zip，双击 `yingsui.exe` 即可。免安装。

---

## 五、已知坑位速查

| 现象 | 原因 | 解决 |
|---|---|---|
| `"windows" is not a supported build target` | 在 macOS/Linux 上执行 | 只能在 Windows 上编 |
| CMake 报 `Unable to find suitable Visual Studio toolchain` | 缺「使用 C++ 的桌面开发」 | VS Installer → 修改 → 勾上该工作负载 |
| `flutter pub get` 卡住 / 超时 | 国内网络访问 pub.dev 慢 | 设置 `PUB_HOSTED_URL` 与 `FLUTTER_STORAGE_BASE_URL` 镜像 |
| 应用内报「内置音频组件缺失」 | 没把 ffmpeg 放进 `ffmpeg\` | 见第二节 |
| 双击 exe 报缺 DLL | 只拷了 exe | 解压整个 zip |
| 跟读/听写录不了音 | Windows 麦克风权限 | 设置 → 隐私和安全性 → 麦克风 → 允许桌面应用访问 |
| SmartScreen「已保护你的电脑」 | 未做代码签名 | 用户点「更多信息 → 仍要运行」；正式分发建议买代码签名证书 |
| AI 字幕转写失败 | 没配翻译/转写 API | 应用内设置里填 API Key |

---

## 六、两个可以顺手改进的点

1. **exe 名字**。现在是 `yingsui.exe`（`windows/CMakeLists.txt` 里
   `set(BINARY_NAME "yingsui")`），而 macOS 产物叫 `EnglishCorner.app`。
   想统一的话改成 `EnglishCorner` 即可，但 `windows/runner/Runner.rc` 的
   `OriginalFilename` 也要跟着改。
2. **安装包**。zip 是免安装版。要开始菜单/桌面快捷方式，可用
   [Inno Setup](https://jrsoftware.org/isinfo.php) 或 MSIX 打包 —— 目前 CI
   和本脚本都只出 zip。

---

## 七、发布前检查清单（Windows 部分）

- [ ] `flutter --version` 是 3.44.4
- [ ] `flutter doctor` 的 Visual Studio 一节为 `[√]`
- [ ] `build\ffmpeg-bundle\windows-x64\ffmpeg.exe` 存在且能运行
- [ ] `flutter analyze` 无问题、`flutter test` 全过
- [ ] 版本号已在 `pubspec.yaml` 提升
- [ ] 解压 zip 后**双击 yingsui.exe 实测能启动**，并试一次 AI 字幕
- [ ] 应用图标已是最终版（`python3 tool/brand/generate_icons.py --concept C --out .`）

---

## 八、附：不用脚本的手动步骤（脚本出问题时的退路）

`build-windows.ps1` 是在 macOS 上写的，**没有在 Windows 上实测过**
（本机没有 PowerShell，也没有 Windows）。它做的事很简单，真出问题的话
把下面四条逐条执行，效果完全一样：

```powershell
# 1) 拉依赖
flutter pub get

# 2) 构建
flutter build windows --release

# 3) 把内置 ffmpeg 补进发布目录（路径必须正好是 Release\ffmpeg\ffmpeg.exe）
Copy-Item build\ffmpeg-bundle\windows-x64 build\windows\x64\runner\Release\ffmpeg -Recurse

# 4) 看一眼产物
dir build\windows\x64\runner\Release
```

应该能看到 `yingsui.exe`、若干 `.dll`、`data\`、`ffmpeg\`。确认无误后，
把 `Release\` 里的**全部内容**（不是 Release 文件夹本身）压成一个 zip
就是成品。

`build-windows.ps1` 相比上面这几条，多的只是：读版本号自动命名 zip、
实测一次 `ffmpeg.exe -version`、算 SHA256 并打印分发提醒。
