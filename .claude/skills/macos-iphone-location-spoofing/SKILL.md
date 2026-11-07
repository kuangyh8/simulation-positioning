---
name: macos-iphone-location-spoofing
description: "Use when building a macOS native desktop app that drives an iPhone over USB via libimobiledevice (location spoofing or other device control), or when building a polished AppKit + MapKit desktop app. Covers the CLI commands, AppKit custom-drawn dynamic-color views, Auto Layout gotchas, a draggable-pin MapKit map, icon generation, and ad-hoc codesign packaging."
---

# macOS iPhone Location Spoofing App

构建「给 USB 连接的 iPhone 写假定位」的 macOS 桌面 App，或任何用 libimobiledevice 驱动 iPhone 的 GUI，以及 AppKit + MapKit 桌面 App 的通用套路。

## 核心命令（libimobiledevice）

```bash
brew install libimobiledevice
idevice_id -l                                        # 列出 UDID
idevice_id <UDID>                                     # 设备名
idevicesetlocation -u <UDID> -- <lat> <lon>           # 写坐标
idevicesetlocation -u <UDID> reset                    # 恢复真实定位
```

- 坐标是 WGS-84，与地图/GPS 同一坐标系，无需换算。
- 开启后每 5 秒重写一次以保持锁定（Timer 驱动）。
- iPhone 必须：USB 连接 + 信任电脑 + 开发者模式，否则系统拒绝写入。
- 只对物理连接的设备生效，无法远程。

## 打包成 App

```bash
swiftc -O -framework AppKit -framework CoreLocation -framework MapKit main.swift -o NAME
# 组装 NAME.app（Contents/MacOS + Contents/Resources + Info.plist）
codesign --force --deep --sign - NAME.app   # ad-hoc 签名即可
```

- 非沙盒命令行工具 App，MapKit 瓦片联网加载正常。

## 关键决策 / 常见坑

1. **Dock 桌面 App vs 菜单栏 App**：菜单栏用 `LSUIElement=true` + `NSApp.setActivationPolicy(.accessory)`；Dock App 则删掉 `LSUIElement`、用 `.regular`、并在 `applicationShouldHandleReopen` 里重开窗口。
2. **深浅色自定义视图**：自定义 `draw(_:)` 里解析动态 `NSColor`，不要在 layer 上用静态 `CGColor`（切换深浅色不自动更新）。
3. **Auto Layout**：
   - `addSubview` 后必须 `translatesAutoresizingMaskIntoConstraints = false`。
   - 无 intrinsic size 的自定义 `NSView` 放进 `NSStackView` 会塌陷到 0，要显式 width/height。
   - 垂直 stack 里做全宽行用 `widthAnchor == root.widthAnchor`。
4. **MapKit 地图 + 可拖动图钉**：`MKMarkerAnnotationView` 设 `isDraggable=true`；拖完（`didChange .ending`）回填坐标；反向用 `annotation.coordinate = …` + `setRegion`。不开启 `showsUserLocation`（避免暴露真实位置）。
5. **地名搜索**：优先 `MKLocalSearch`（坐标用 `MKMapItem.location.coordinate`，简称地址用 `item.address?.shortAddress`）；`MKMapItem.placemark` 与 `CLGeocoder` 在 macOS 26 已弃用。
6. **图标**：CoreGraphics 画 → `sips` 出多尺寸 → `iconutil -c icns`。
7. **验证布局**：`DEBUG_LAYOUT=1` 环境变量触发打印视图 frame，确认无塌陷/约束冲突（无法截图时）。

## 参考实现

同仓库 `main.swift`（App）、`build.sh`（构建）、`make_icon.swift`（图标）、`design-preview.html`（设计预览）。
