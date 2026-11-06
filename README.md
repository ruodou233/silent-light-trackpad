# Silent Light Trackpad

**Turn off the MacBook trackpad's click vibration (haptic feedback) on macOS.**

> 苹果官方点击又重，线性马达还震得手指难受，用久了真有种要得滑膜炎、腱鞘炎的感觉。

Silent Light Trackpad is a small, local menu bar app that turns off the built-in trackpad's haptic actuator, so a physical click no longer kicks back into your fingertip. Clicks keep working, just without the buzz. For a lighter touch, pair it with macOS's own **Light** click and **Tap to click**.

Apple’s stock click takes too much force, and the linear actuator keeps kicking back into the fingertip—after a long session, it honestly feels like a fast track to synovitis or tenosynovitis.

[中文说明](#中文说明)

## 0.6 is the slim version

Up to 0.5.1 the app also had its own light-pressure click engine: it read raw trackpad pressure through [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) and generated a click below the system's Light threshold. **0.6.0 removes the engine and keeps only the haptics switch.** The last version with the engine is commit `4332153` (0.5.1); it stays in the git history.

Why:

- In September 2026 a rebuild silently invalidated the engine's Accessibility permission, and the engine did not run for about seven weeks. Nobody noticed: macOS Light click + Tap to click + this app's haptics switch were already enough.
- The engine needed Accessibility permission (lost on every ad-hoc rebuild), its synthetic clicks had open problems (double click, drag release, right click), and it had to take over the system Tap to click setting.
- OpenMultitouchSupport opens the raw touch stream after every wake, even when nothing listens. On macOS 27 that stream is reported to break three- and four-finger gestures ([issue #13](https://github.com/Kyome22/OpenMultitouchSupport/issues/13)). Without the engine and the library, this cannot happen.

The app no longer needs Accessibility permission. If an older version is still listed under **System Settings → Privacy & Security → Accessibility**, you can remove it.

## Features

- Turns off the built-in trackpad's haptic actuator (the click vibration).
- Re-applies your choice after wake, when the login session becomes active, and whenever the menu opens (macOS turns haptics back on after sleep).
- The menu bar icon shows the real state: a plain hand means haptics are off; a dimmed hand means you turned them back on; a hand with an exclamation badge means turning them off failed or the state cannot be read. Hover over the icon for the state in words.
- Four menu items: **Disable Haptics**, **Open at Login**, **Restore Haptics and Quit…**, **Quit**. Only when something is wrong does the menu gain a status line, and **Disable Haptics** becomes **Retry Turning Off Haptics**.
- Opens at login by default. English or Chinese menu, following the system language.
- Runs locally with no analytics, network service, or account. No third-party code.

### Recommended system settings

This app does not change any of these; set them in **System Settings → Trackpad** if you like:

- **Click**: Light.
- **Tap to click**: on. A tap clicks with no pressure at all, and tapping with two fingers right-clicks.
- **Force Click and haptic feedback**: off.
- Optional: **three-finger drag** (System Settings → Accessibility → Pointer Control → Trackpad Options) for dragging without pressing.

## Requirements

- A MacBook with a built-in Force Touch trackpad
- macOS 15 or newer
- Swift 6.2 or newer to build from source

0.7.0 passes its offline self-tests on a MacBook Air (Mac17,4) running macOS 26.5.2; checks on the real trackpad are still pending.

## Download

[Download the Apple Silicon app](https://github.com/ruodou233/silent-light-trackpad/releases/latest/download/Silent-Light-Trackpad-macOS-arm64-unnotarized.zip)

After extracting the ZIP, move the app to **Applications** before opening it. The package is ad-hoc signed and not notarized, so macOS may require **System Settings → Privacy & Security → Open Anyway** on first launch. Open at Login may also require approval in **System Settings → General → Login Items**.

## Build from source

```bash
git clone https://github.com/ruodou233/silent-light-trackpad.git
cd silent-light-trackpad
./build-app.sh
ditto "dist/Silent Light Trackpad.app" "/Applications/Silent Light Trackpad.app"
open "/Applications/Silent Light Trackpad.app"
```

The hand icon in the menu bar opens all controls. The app icon is drawn by `assets/make-icon.swift`.

Two read-only checks exit before any window or menu is created:

```bash
app="/Applications/Silent Light Trackpad.app/Contents/MacOS/SilentLightTrackpad"
"$app" --self-test   # pure state checks
"$app" --status      # JSON, see below
```

`--status` prints what the running app reported about itself (`instance.status`: `off`, `on`, `failed` or `unknown`; `instance.running`; `instance.reportedAt`), the login item status, and a direct read of the actuator (`haptics.isEnabled`) for cross-checking. It changes nothing.

## Restore behavior

- **Quit** leaves haptics as they are. If they were off, they stay off until the next sleep/wake or restart without the app, when macOS turns them back on.
- Unchecking **Disable Haptics** turns haptics back on while the app keeps running; the choice is remembered across launches.
- **Restore Haptics and Quit…** turns haptics back on, turns off Open at Login, and quits. Tap to click is not touched. Each step is checked; if one fails, the app stays open, names the failed item and offers **Retry**. Opening the app again later turns haptics off again.

### Upgrading from 0.5.x

- Quit the old version with plain **Quit (keep settings)**, not **Restore everything and quit…**: the old restore turns haptics back on and turns off launch at login, and the new version will not turn launch at login back on by itself.
- If you already used the old **Restore everything and quit…**, **Open at Login** stays off in the new version until you click it in the menu.
- Delete the old app from Applications first, then copy the new one. Copying over it with `ditto` keeps the old `Contents/Frameworks` folder inside the new app, which breaks its signature.
- On its first launch the new version clears the old version's preference keys (pressure preset, engine switch, Tap to click snapshot). It never changes Tap to click. The old engine only turned Tap to click off while it was running; if that happened to you, turn it back on in System Settings → Trackpad.

## Important limitations

- This project uses Apple’s private `MultitouchSupport.framework` to control the actuator. It cannot be distributed through the Mac App Store and a macOS update may break it.
- The current implementation targets the built-in/default trackpad, not an external Magic Trackpad.
- Haptics come back after sleep/wake by design of macOS; the app turns them off again on wake, so it needs to keep running.

## How it works

The app loads Apple’s private `MultitouchSupport.framework` with `dlopen`, gets the default device's actuator, and calls `MTActuatorSetSystemActuationsEnabled(0)`, then reads the value back with `MTActuatorGetSystemActuationsEnabled`. It repeats this after wake, on session activation, and when the menu opens. It does not read touches, install event taps, or post mouse events.

This project is released under the [MIT License](LICENSE).

---

## 中文说明

**关闭 MacBook 触控板的点击震动（触感反馈）。**

Silent Light Trackpad 是一个纯本地的 macOS 菜单栏工具。它关掉内置 Force Touch 触控板的触感马达，按下去照样能点击，只是不再震手。想要更轻，配合系统自带的“轻”点按力度和“轻点来点按”。

### 0.6 是收缩版

0.5.1 及以前还带一个自制的“轻压点击”引擎：通过 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport)（读取触控板原始触摸数据的开源库）读压力，在低于系统“轻”档的力度上生成点击。**0.6.0 删掉了这个引擎，只保留关闭触感马达。** 带引擎的最后一版是提交 `4332153`（0.5.1），留在 git 历史里，随时能找回。

为什么收缩：

- 2026 年 9 月一次重新编译后，引擎的辅助功能授权悄悄失效，引擎约 7 周没有运行，用的人也没察觉。说明“系统轻档 + 轻点来点按 + 本工具关马达”已经够用。
- 引擎要辅助功能权限（临时签名每次重新编译都会失效），合成点击还有双击、拖拽松开、右键等问题没解决，并且要接管系统的“轻点来点按”设置。
- OpenMultitouchSupport 每次唤醒都会打开触摸流，不管有没有人在读。据报告，在 macOS 27 上这个触摸流会让三指、四指手势失灵（[issue #13](https://github.com/Kyome22/OpenMultitouchSupport/issues/13)）。引擎和这个库都删掉后，这个风险也就没有了。

现在不再需要辅助功能权限。如果“系统设置 → 隐私与安全性 → 辅助功能”里还留着旧版的条目，可以删掉。

### 主要功能

- 关闭内置触控板的触感马达（点击震动）。
- 唤醒、登录会话恢复以及每次打开菜单时，按你的选择重新设置一次马达（系统睡眠唤醒后会把触感打开）。
- 菜单栏图标显示真实状态：普通的手 = 触感已关闭；变暗的手 = 你选择了打开触感；手带感叹号 = 没关上或无法读取。悬停在图标上能看到文字状态。
- 菜单只有四项：**关闭触感**、**登录时打开**、**恢复触感并退出…**、**退出**。只有出问题时才多一行状态，同时 **关闭触感** 换成 **重试关闭触感**。
- 默认登录时打开。菜单随系统语言显示中文或英文。
- 无账号、无遥测、不联网，没有第三方代码。

#### 建议的系统设置

本工具不改这些设置，需要的话在 **系统设置 → 触控板** 里自己设：

- **点按**：轻。
- **轻点来点按**：开。轻点一下就点击，完全不用压；双指轻点是右键。
- **用力点按和触觉反馈**：关。
- 可选：**三指拖移**（系统设置 → 辅助功能 → 指针控制 → 触控板选项），拖拽时不用按住。

### 下载安装

[下载 Apple Silicon 安装包](https://github.com/ruodou233/silent-light-trackpad/releases/latest/download/Silent-Light-Trackpad-macOS-arm64-unnotarized.zip)

解压后请先把应用移到 **应用程序** 文件夹再打开。安装包使用临时签名、未经 Apple 公证；第一次打开如果被阻止，请前往 **系统设置 → 隐私与安全性 → 仍要打开**。登录时打开可能需要在 **系统设置 → 通用 → 登录项** 中批准。

### 从源码构建

```bash
git clone https://github.com/ruodou233/silent-light-trackpad.git
cd silent-light-trackpad
./build-app.sh
ditto "dist/Silent Light Trackpad.app" "/Applications/Silent Light Trackpad.app"
open "/Applications/Silent Light Trackpad.app"
```

`--self-test`（纯状态自测）和 `--status`（只读状态）都在创建菜单之前就退出，什么都不改。`--status` 输出运行中的实例自己报告的状态（`instance.status`：`off` 已关闭、`on` 已打开、`failed` 未能关闭、`unknown` 无法读取；`instance.running` 实例是否还在运行），登录项状态，以及直接读马达得到的 `haptics.isEnabled`，用来交叉核对。

### 恢复

- **退出**：触感保持原样。如果是关着的，会一直关到下次睡眠唤醒或重启（那时本工具没在运行，系统会把触感打开）。
- 取消勾选 **关闭触感**：应用继续运行，触感恢复；这个选择重启后仍然有效。
- **恢复触感并退出…**：恢复触感，关闭“登录时打开”，然后退出。不碰“轻点来点按”。每一步都会回读检查；有一步失败，应用不退出，写明哪一项没恢复，并可以点 **重试**。之后再打开应用，触感又会关上。

#### 从 0.5.x 升级

- 旧版用普通的 **退出（保留当前设置）** 退出，不要用 **一切还原并退出…**：旧版的还原会打开触感、关掉登录自启，新版不会自己把登录项开回来。
- 如果已经在旧版里用过 **一切还原并退出…**，新版的 **登录时打开** 会一直关着，要在菜单里点一下才会打开。
- 先把旧的 app 从“应用程序”里删掉，再复制新的。用 `ditto` 直接覆盖会把旧的 `Contents/Frameworks` 目录留在新 app 里，签名就坏了。
- 新版第一次启动会清掉旧版留下的偏好（力度档、引擎开关、“轻点来点按”快照），但从不改“轻点来点按”。旧版只在引擎运行时关过“轻点来点按”；如果你遇到过，请在 系统设置 → 触控板 里把它打开。

### 注意

- 本项目使用 Apple 私有框架 `MultitouchSupport.framework` 控制马达，不能上架 Mac App Store，macOS 大版本更新也可能导致失效。
- 只针对 MacBook 内置触控板，不保证支持外接妙控板。
- 系统睡眠唤醒后会把触感重新打开，本工具在唤醒时再关一次，所以需要保持运行。
