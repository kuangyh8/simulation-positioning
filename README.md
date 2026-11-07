# Simulation Positioning · 模拟定位

macOS 桌面 App：给 **USB 连接的 iPhone** 写入假定位。原生 **Swift + AppKit + MapKit**，通过 **libimobiledevice** 驱动设备。

无论你人在哪里，打开它、设定一个坐标（搜索地名 / 拖地图图钉 / 填经纬度 / 点常用位置），iPhone 上所有 App 就会认为你在那个位置。

---

## ⚠️ 用途与免责声明

- 本工具用于**你自己拥有并物理连接的 iPhone**，适用场景：App 开发与测试、隐私保护、位置相关功能调试。
- **请勿**用于任何欺诈、作弊、虚假打卡、伪造行踪等用途。
- 需要**物理 USB 连接 + 设备信任 + 开发者模式**，无法远程或对他人设备生效。

---

## 功能特性

- 🌍 地名搜索（MapKit 本地搜索，多候选时弹列表选择）
- 🗺️ 迷你地图 + 可拖动图钉，与坐标框**双向同步**；标准 / 卫星 / 混合样式切换
- ⭐ 常用位置收藏（本地持久化）
- 🔁 开启后每 5 秒重写一次，保持锁定；一键重置恢复真实定位
- 🎨 深浅色自适应、原生视觉（毛玻璃背景、自定义渐变按钮、圆角卡片）

---

## 技术栈

| 层 | 技术 |
|---|---|
| 语言 | Swift |
| UI | AppKit（NSStackView / NSVisualEffectView / 自定义 draw） |
| 地图 | MapKit（MKMapView / MKLocalSearch / MKMarkerAnnotationView） |
| 定位 | CoreLocation（坐标类型） |
| 设备驱动 | libimobiledevice（idevicesetlocation / idevice_id） |
| 图标 | CoreGraphics + sips + iconutil |
| 打包 | swiftc + Info.plist + ad-hoc codesign |

---

## 前置要求

- macOS 11+（实测 macOS 26/27）
- Xcode Command Line Tools（提供 `swiftc`、`sips`、`iconutil`）
- Homebrew
- `libimobiledevice`

```bash
brew install libimobiledevice
```

---

## 快速开始

```bash
# 1. 构建（自动生成图标 → 编译 → 组装 .app → 签名）
./build.sh

# 2. 打开（或把 SimulationPositioning.app 拖进 /Applications）
open SimulationPositioning.app
```

iPhone 侧（必须）：
1. USB 连上 Mac
2. 在 iPhone 上「信任此电脑」
3. 开启**开发者模式**：设置 → 隐私与安全性 → 开发者模式（否则系统会拒绝写入）

---

## 工作原理（工作流）

### 核心机制：libimobiledevice

App 本身不碰定位 API，而是调用两个命令行工具：

```bash
idevice_id -l                                   # 列出已连接设备 UDID
idevicesetlocation -u <UDID> -- <lat> <lon>     # 写假坐标
idevicesetlocation -u <UDID> reset              # 恢复真实定位
```

- 开启后每 5 秒重写一次，防止系统/App 恢复真实定位。
- 写入的是 WGS-84 经纬度，与地图、GPS 同一坐标系，**无需换算**。

### App 架构

- 从「菜单栏 App（LSUIElement）」演进为「Dock 桌面 App」：删除 `LSUIElement`、`NSApp.setActivationPolicy(.regular)`、`applicationShouldHandleReopen` 在点 Dock 时重开窗口。
- `LocationController` 用 5s Timer 驱动；通过 `onUpdate` 回调刷新 UI。

### UI 关键技术

- **自定义绘制解决深浅色**：`RoundedView` / `GradientButton` 在 `draw(_:)` 里解析动态 `NSColor`，而不是设置 layer 的 `CGColor`（后者在深浅色切换时不自动更新）。
- **Auto Layout 的坑**：
  - `addSubview` 后必须设 `translatesAutoresizingMaskIntoConstraints = false`，否则约束冲突。
  - 自定义 `NSView` 没有 intrinsic content size，放进 `NSStackView` 会塌陷到 0 —— 要给它显式 width/height 约束。
  - 垂直 `NSStackView` 里做全宽行：`v.widthAnchor == root.widthAnchor`（而非 leading+trailing 双约束）。

### 地图（MapKit）

- `MKMapView` + `MKPointAnnotation` + `MKMarkerAnnotationView(isDraggable: true)`。
- 拖动结束（`didChange .ending`）→ 回填坐标框；输入坐标/搜索/点收藏 → `applyCoordinate` 移动图钉并居中。
- `MKLocalSearch` 搜地名，多候选时 `NSAlert` 弹列表选择。
- 地图瓦片需联网加载；刻意不开启 `showsUserLocation`，只显示设定的假坐标，不泄露真实位置。

### 图标生成

`make_icon.swift` 用 CoreGraphics 画 indigo→cyan 渐变色 squircle + 白色定位图钉；`build.sh` 用 `sips` 出多尺寸、`iconutil` 转 `.icns`。

### 打包与签名

`swiftc -O -framework AppKit -framework CoreLocation -framework MapKit main.swift` → 组装 `.app`（Info.plist）→ `codesign --force --deep --sign -`（ad-hoc）。

### 验证方法

`DEBUG_LAYOUT=1` 运行时打印每个视图的 frame，用于确认布局无塌陷、无约束冲突（GUI 无法直接截图时很实用）。

---

## 目录结构

```
.
├── main.swift            # App 全部源码
├── make_icon.swift       # 图标生成器（CoreGraphics）
├── build.sh              # 一键构建脚本
├── design-preview.html   # 界面设计阶段的 HTML 预览
├── .claude/skills/…      # 内嵌的 Claude Code skill
└── README.md
```

---

## 内嵌 Claude Code skill

仓库内置了一个 skill（`.claude/skills/macos-iphone-location-spoofing/SKILL.md`），把上面的工作流沉淀成可复用指南。在 Claude Code 里打开本仓库会自动识别；想全局使用：

```bash
cp -r .claude/skills/macos-iphone-location-spoofing ~/.claude/skills/
```

---

## License

MIT
