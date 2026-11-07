import AppKit
import CoreLocation
import MapKit

// MARK: - 命令执行辅助

func findBin(_ name: String) -> String? {
    for dir in ["/opt/homebrew/bin/", "/usr/local/bin/", "/opt/local/bin/"] {
        let p = dir + name
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

@discardableResult
func runCmd(_ path: String, _ args: [String]) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "无法启动 \(path)：\(error.localizedDescription)") }
    p.waitUntilExit()
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
}

// MARK: - 品牌色

extension NSColor {
    static let brandIndigo = NSColor(srgbRed: 0.388, green: 0.400, blue: 0.945, alpha: 1) // #6366F1
    static let brandCyan   = NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 1) // #22D3EE
}

// MARK: - 圆角容器视图（draw 绘制，动态颜色在绘制时正确解析，自动适配深浅色）

final class RoundedView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var borderColor: NSColor? { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 10 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        if let c = borderColor {
            c.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

// MARK: - 渐变按钮（主按钮）

final class GradientButton: NSButton {
    var colors: [NSColor] = [.brandIndigo, .brandCyan] { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 11 { didSet { needsDisplay = true } }
    var titleFont: NSFont = .boldSystemFont(ofSize: 14)

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        if let grad = NSGradient(colors: colors.count >= 2 ? colors : [colors[0], colors[0]]) {
            grad.draw(in: path, angle: -45)
        }
        let alpha: CGFloat = isHighlighted ? 0.82 : 1.0
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: para
        ]
        let size = title.size(withAttributes: attrs)
        let r = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        title.draw(in: r, withAttributes: attrs)
    }
}

// MARK: - 收藏项

struct Favorite {
    let name: String
    let lat: Double
    let lon: Double
}

// MARK: - 定位控制器

final class LocationController {
    var onUpdate: (() -> Void)?

    private(set) var isActive = false
    private(set) var lat: Double?
    private(set) var lon: Double?
    private(set) var connected = false
    private(set) var deviceName: String?
    private(set) var deviceLabel = "未检测到设备"
    private(set) var lastError: String?

    private var udid: String?
    private var timer: Timer?

    let setBin: String? = findBin("idevicesetlocation")
    let idBin: String? = findBin("idevice_id")

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if isActive, let lat = lat, let lon = lon, let udid = udid, let setBin = setBin {
            _ = runCmd(setBin, ["-u", udid, "--", String(lat), String(lon)])
        } else if !isActive {
            refreshDevice()
        }
    }

    func statusSummary() -> String {
        if isActive, let lat = lat, let lon = lon {
            return String(format: "正在模拟 (%.5f, %.5f) · %@", lat, lon, deviceName ?? "iPhone")
        }
        if let e = lastError, !e.isEmpty { return "⚠️ \(e)" }
        return deviceLabel
    }

    func refreshDevice() {
        guard let idBin = idBin else {
            udid = nil; connected = false
            deviceLabel = "未找到 idevice_id，请先安装 libimobiledevice"
            onUpdate?()
            return
        }
        let r = runCmd(idBin, ["-l"])
        let lines = r.out.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.isEmpty {
            udid = nil; connected = false; deviceName = nil
            deviceLabel = "未检测到 iPhone（插入 USB → 信任 → 开发者模式）"
        } else {
            udid = lines[0]; connected = true
            let nr = runCmd(idBin, [lines[0]])
            let name = nr.out.trimmingCharacters(in: .whitespacesAndNewlines)
            deviceName = name.isEmpty ? "iPhone" : name
            deviceLabel = "已连接：\(deviceName ?? "iPhone")"
        }
        onUpdate?()
    }

    func start(lat: Double, lon: Double) -> Bool {
        guard let setBin = setBin else {
            lastError = "未找到 idevicesetlocation，请先安装 libimobiledevice"
            onUpdate?()
            return false
        }
        refreshDevice()
        guard let udid = udid else {
            lastError = "没有检测到 iPhone，无法开始"
            onUpdate?()
            return false
        }
        let r = runCmd(setBin, ["-u", udid, "--", String(lat), String(lon)])
        if r.code != 0 {
            let msg = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            lastError = msg.isEmpty ? "写入失败（未知错误）" : "写入失败：\(msg)"
            isActive = false
            onUpdate?()
            return false
        }
        self.lat = lat; self.lon = lon
        lastError = nil
        isActive = true
        onUpdate?()
        return true
    }

    func stop() {
        isActive = false
        if let setBin = setBin, let udid = udid {
            _ = runCmd(setBin, ["-u", udid, "reset"])
        }
        lastError = nil
        onUpdate?()
    }
}

// MARK: - App 代理

final class AppDelegate: NSObject, NSApplicationDelegate, MKMapViewDelegate {
    let controller = LocationController()

    var window: NSWindow!
    var mapView: MKMapView!
    var annotation: MKPointAnnotation!
    var latField: NSTextField!
    var lonField: NSTextField!
    var searchField: NSTextField!
    var statusLine: NSTextField!
    var deviceValue: NSTextField!
    var toggleButton: GradientButton!

    var pillDot: RoundedView!
    var pillLabel: NSTextField!

    var chipStack: NSStackView!
    var chips: [NSButton] = []
    var chipItems: [Favorite] = []
    var savedFavorites: [Favorite] = []

    let presets: [Favorite] = [
        Favorite(name: "北京", lat: 39.9042, lon: 116.4074),
        Favorite(name: "上海", lat: 31.2304, lon: 121.4737),
        Favorite(name: "纽约", lat: 40.7128, lon: -74.0060),
        Favorite(name: "东京", lat: 35.6762, lon: 139.6503),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        loadFavorites()
        buildMainMenu()
        buildWindow()

        controller.onUpdate = { [weak self] in self?.refreshUI() }
        controller.refreshDevice()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ProcessInfo.processInfo.environment["DEBUG_LAYOUT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.dumpLayout()
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func dumpLayout() {
        print("=== LAYOUT DUMP ===")
        func rec(_ v: NSView, _ ind: String) {
            let cls = String(describing: type(of: v))
            let frame = NSStringFromRect(v.frame)
            print("\(ind)\(cls) \(frame)")
            for s in v.subviews { rec(s, ind + "  ") }
        }
        if let cv = window.contentView { rec(cv, "") }
        print("annotations: \(mapView.annotations.count)")
    }

    // MARK: 主菜单

    func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 模拟定位", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 模拟定位", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 模拟定位", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let locItem = NSMenuItem()
        mainMenu.addItem(locItem)
        let locMenu = NSMenu(title: "位置")
        locItem.submenu = locMenu
        let toggle = NSMenuItem(title: "开始/停止模拟", action: #selector(toggleAction), keyEquivalent: "s")
        toggle.target = self
        locMenu.addItem(toggle)
        let reset = NSMenuItem(title: "重置位置", action: #selector(resetAction), keyEquivalent: "")
        reset.target = self
        locMenu.addItem(reset)
        locMenu.addItem(.separator())
        let refresh = NSMenuItem(title: "刷新设备", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        locMenu.addItem(refresh)

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        NSApp.mainMenu = mainMenu
    }

    // MARK: 窗口构建

    func buildWindow() {
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(root)

        // 1) 头部
        let brandIcon = NSImageView()
        brandIcon.image = NSApp.applicationIconImage
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.setContentHuggingPriority(.required, for: .horizontal)

        let nameLabel = NSTextField(labelWithString: "模拟定位")
        nameLabel.font = .boldSystemFont(ofSize: 17)
        let subLabel = NSTextField(labelWithString: "Simulation Positioning")
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        let brandText = NSStackView(views: [nameLabel, subLabel])
        brandText.orientation = .vertical
        brandText.alignment = .leading
        brandText.spacing = 1
        brandText.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        pillDot = RoundedView()
        pillDot.cornerRadius = 4
        pillLabel = NSTextField(labelWithString: "未连接")
        pillLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        let pillStack = NSStackView(views: [pillDot, pillLabel])
        pillStack.orientation = .horizontal
        pillStack.spacing = 7
        pillStack.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [brandIcon, brandText, spacer, pillStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 12

        // 2) 设备卡片
        let deviceLabel = NSTextField(labelWithString: "设备")
        deviceLabel.font = .systemFont(ofSize: 12)
        deviceLabel.textColor = .secondaryLabelColor
        deviceLabel.setContentHuggingPriority(.required, for: .horizontal)
        deviceValue = NSTextField(labelWithString: "未检测到设备")
        deviceValue.font = .systemFont(ofSize: 13, weight: .semibold)
        deviceValue.lineBreakMode = .byTruncatingTail
        deviceValue.setContentHuggingPriority(.defaultLow, for: .horizontal)
        deviceValue.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let refreshBtn = NSButton(title: "刷新", target: self, action: #selector(refreshAction))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.setContentHuggingPriority(.required, for: .horizontal)
        let deviceRow = NSStackView(views: [deviceLabel, deviceValue, refreshBtn])
        deviceRow.orientation = .horizontal
        deviceRow.alignment = .centerY
        deviceRow.distribution = .fill
        deviceRow.spacing = 10
        deviceRow.translatesAutoresizingMaskIntoConstraints = false
        let deviceCard = RoundedView()
        deviceCard.fillColor = .controlBackgroundColor
        deviceCard.borderColor = .separatorColor
        deviceCard.cornerRadius = 12
        deviceCard.addSubview(deviceRow)

        // 3) 搜索
        let mag = NSImageView()
        mag.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")
        mag.contentTintColor = .secondaryLabelColor
        mag.setContentHuggingPriority(.required, for: .horizontal)
        searchField = NSTextField()
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 13.5)
        searchField.placeholderString = "搜索地点，如：北京天安门 或 上海外滩"
        searchField.target = self
        searchField.action = #selector(searchAction)
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let searchInner = NSStackView(views: [mag, searchField])
        searchInner.orientation = .horizontal
        searchInner.alignment = .centerY
        searchInner.distribution = .fill
        searchInner.spacing = 8
        searchInner.translatesAutoresizingMaskIntoConstraints = false
        let searchBox = RoundedView()
        searchBox.fillColor = .textBackgroundColor
        searchBox.borderColor = .separatorColor
        searchBox.cornerRadius = 10
        searchBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchBox.addSubview(searchInner)
        let searchBtn = NSButton(title: "搜索", target: self, action: #selector(searchAction))
        searchBtn.bezelStyle = .rounded
        searchBtn.setContentHuggingPriority(.required, for: .horizontal)
        let searchRow = NSStackView(views: [searchBox, searchBtn])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.distribution = .fill
        searchRow.spacing = 8

        // 3.5) 迷你地图
        mapView = MKMapView()
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        annotation = MKPointAnnotation()
        annotation.title = "模拟位置"
        mapView.addAnnotation(annotation)

        let styleControl = NSSegmentedControl(labels: ["标准", "卫星", "混合"], trackingMode: .selectOne, target: self, action: #selector(mapStyleChanged(_:)))
        styleControl.selectedSegment = 0
        styleControl.segmentStyle = .rounded
        styleControl.translatesAutoresizingMaskIntoConstraints = false

        let mapContainer = NSView()
        mapContainer.wantsLayer = true
        mapContainer.layer?.cornerRadius = 12
        mapContainer.layer?.masksToBounds = true
        mapContainer.addSubview(mapView)
        mapContainer.addSubview(styleControl)

        // 4) 坐标行
        latField = makeField(placeholder: "纬度 如 39.9042")
        lonField = makeField(placeholder: "经度 如 116.4074")
        let latBox = makeFieldBox(label: "纬度", field: latField)
        let lonBox = makeFieldBox(label: "经度", field: lonField)
        latBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lonBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let copyBtn = NSButton(title: "复制", target: self, action: #selector(copyAction))
        copyBtn.bezelStyle = .rounded
        copyBtn.setContentHuggingPriority(.required, for: .horizontal)
        let coordRow = NSStackView(views: [latBox, lonBox, copyBtn])
        coordRow.orientation = .horizontal
        coordRow.alignment = .centerY
        coordRow.distribution = .fill
        coordRow.spacing = 10

        // 5) 常用位置
        let favLabel = NSTextField(labelWithString: "常用位置")
        favLabel.font = .systemFont(ofSize: 12)
        favLabel.textColor = .secondaryLabelColor
        favLabel.setContentHuggingPriority(.required, for: .horizontal)
        chipStack = NSStackView()
        chipStack.orientation = .horizontal
        chipStack.spacing = 8
        chipStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let favRow = NSStackView(views: [favLabel, chipStack])
        favRow.orientation = .horizontal
        favRow.alignment = .centerY
        favRow.spacing = 10

        // 6) 操作按钮
        toggleButton = GradientButton()
        toggleButton.isBordered = false
        toggleButton.setButtonType(.momentaryChange)
        toggleButton.title = "▶ 开始模拟"
        toggleButton.titleFont = .boldSystemFont(ofSize: 14)
        toggleButton.target = self
        toggleButton.action = #selector(toggleAction)
        toggleButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let resetBtn = NSButton(title: "重置位置", target: self, action: #selector(resetAction))
        resetBtn.bezelStyle = .rounded
        resetBtn.setContentHuggingPriority(.required, for: .horizontal)
        let actions = NSStackView(views: [toggleButton, resetBtn])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.distribution = .fill
        actions.spacing = 10

        // 7) 状态行
        statusLine = NSTextField(labelWithString: "未检测到 iPhone")
        statusLine.font = .systemFont(ofSize: 12)
        statusLine.textColor = .secondaryLabelColor
        statusLine.alignment = .center

        // 组装
        let rows: [NSView] = [header, deviceCard, searchRow, mapContainer, coordRow, favRow, actions, statusLine]
        for v in rows {
            root.addArrangedSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        // 尺寸约束
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            root.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -16),

            brandIcon.widthAnchor.constraint(equalToConstant: 42),
            brandIcon.heightAnchor.constraint(equalToConstant: 42),
            pillDot.widthAnchor.constraint(equalToConstant: 8),
            pillDot.heightAnchor.constraint(equalToConstant: 8),

            deviceCard.heightAnchor.constraint(equalToConstant: 44),
            deviceRow.topAnchor.constraint(equalTo: deviceCard.topAnchor, constant: 10),
            deviceRow.bottomAnchor.constraint(equalTo: deviceCard.bottomAnchor, constant: -10),
            deviceRow.leadingAnchor.constraint(equalTo: deviceCard.leadingAnchor, constant: 14),
            deviceRow.trailingAnchor.constraint(equalTo: deviceCard.trailingAnchor, constant: -14),

            searchBox.heightAnchor.constraint(equalToConstant: 38),
            searchBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            searchInner.topAnchor.constraint(equalTo: searchBox.topAnchor, constant: 7),
            searchInner.bottomAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: -7),
            searchInner.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 12),
            searchInner.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 22),

            mapContainer.heightAnchor.constraint(equalToConstant: 260),
            mapView.topAnchor.constraint(equalTo: mapContainer.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: mapContainer.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: mapContainer.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor),
            styleControl.topAnchor.constraint(equalTo: mapContainer.topAnchor, constant: 10),
            styleControl.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor, constant: -10),

            latBox.widthAnchor.constraint(equalTo: lonBox.widthAnchor),
            latBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            latBox.heightAnchor.constraint(equalToConstant: 38),
            lonBox.heightAnchor.constraint(equalToConstant: 38),

            toggleButton.heightAnchor.constraint(equalToConstant: 44),
            resetBtn.heightAnchor.constraint(equalToConstant: 44),
        ])

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.contentView = effect
        window.title = "模拟定位"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 632)

        let initial = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        annotation.coordinate = initial
        mapView.setRegion(MKCoordinateRegion(center: initial, latitudinalMeters: 20000, longitudinalMeters: 20000), animated: false)

        rebuildFavorites()
        refreshUI()
    }

    private func makeField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .monospacedDigitSystemFont(ofSize: 13.5, weight: .regular)
        f.placeholderString = placeholder
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    private func makeFieldBox(label: String, field: NSTextField) -> RoundedView {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = .secondaryLabelColor
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        let inner = NSStackView(views: [lbl, field])
        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.distribution = .fill
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        let box = RoundedView()
        box.fillColor = .textBackgroundColor
        box.borderColor = .separatorColor
        box.cornerRadius = 10
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
        ])
        return box
    }

    // MARK: 收藏

    func loadFavorites() {
        guard let arr = UserDefaults.standard.array(forKey: "favorites") as? [[String]] else { return }
        savedFavorites = arr.compactMap { e in
            guard e.count == 3, let lat = Double(e[1]), let lon = Double(e[2]) else { return nil }
            return Favorite(name: e[0], lat: lat, lon: lon)
        }
    }

    func saveFavorites() {
        let arr = savedFavorites.map { [$0.name, String($0.lat), String($0.lon)] }
        UserDefaults.standard.set(arr, forKey: "favorites")
    }

    func rebuildFavorites() {
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chips.removeAll()
        chipItems = presets + savedFavorites
        for (i, fav) in chipItems.enumerated() {
            let chip = NSButton(title: fav.name, target: self, action: #selector(chipClicked(_:)))
            chip.bezelStyle = .inline
            chip.tag = i
            chipStack.addArrangedSubview(chip)
            chips.append(chip)
        }
        let add = NSButton(title: "＋ 收藏当前", target: self, action: #selector(addFavorite))
        add.bezelStyle = .inline
        add.contentTintColor = .brandIndigo
        chipStack.addArrangedSubview(add)
    }

    @objc func chipClicked(_ sender: NSButton) {
        let fav = chipItems[sender.tag]
        applyCoordinate(fav.lat, fav.lon)
        for (i, c) in chips.enumerated() { c.state = (i == sender.tag) ? .on : .off }
    }

    @objc func addFavorite() {
        let name = askForName(default: "位置 \(savedFavorites.count + 1)")
        guard let n = name, !n.isEmpty else { return }
        guard let lat = Double(latField.stringValue.trimmingCharacters(in: .whitespaces)),
              let lon = Double(lonField.stringValue.trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(lat), (-180...180).contains(lon) else {
            statusLine.stringValue = "请先填入有效坐标，再收藏"
            return
        }
        savedFavorites.append(Favorite(name: n, lat: lat, lon: lon))
        saveFavorites()
        rebuildFavorites()
        statusLine.stringValue = "已收藏「\(n)」"
    }

    func askForName(default def: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "收藏当前位置"
        alert.informativeText = "给这个位置起个名字："
        alert.addButton(withTitle: "收藏")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = def
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            return input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: 动作

    @objc func openSettings() {
        controller.refreshDevice()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refreshAction() {
        controller.refreshDevice()
    }

    @objc func searchAction() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        statusLine.stringValue = "正在搜索「\(query)」…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let items = response?.mapItems, !items.isEmpty {
                    if items.count == 1 {
                        self.applyMapItem(items[0], query: query)
                    } else {
                        self.showSearchCandidates(items, query: query)
                    }
                } else {
                    self.statusLine.stringValue = "搜索失败：\(error?.localizedDescription ?? "未找到该地点")"
                }
            }
        }
    }

    func applyMapItem(_ item: MKMapItem, query: String) {
        let coord = item.location.coordinate
        let name = item.name ?? query
        applyCoordinate(coord.latitude, coord.longitude)
        for c in chips { c.state = .off }
        statusLine.stringValue = "已定位：\(name)"
    }

    func candidateTitle(_ item: MKMapItem) -> String {
        let name = item.name ?? "未知地点"
        if let short = item.address?.shortAddress, !short.isEmpty, short != name {
            return "\(name) · \(short)"
        }
        return name
    }

    func showSearchCandidates(_ items: [MKMapItem], query: String) {
        let shown = Array(items.prefix(8))
        let alert = NSAlert()
        alert.messageText = "「\(query)」找到 \(items.count) 个地点"
        alert.informativeText = "选一个要定位的地点："
        for item in shown {
            alert.addButton(withTitle: candidateTitle(item))
        }
        alert.addButton(withTitle: "取消")
        let resp = alert.runModal()
        let idx = Int(resp.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        if idx >= 0 && idx < shown.count {
            applyMapItem(shown[idx], query: query)
        } else {
            statusLine.stringValue = "已取消搜索"
        }
    }

    func applyCoordinate(_ lat: Double, _ lon: Double, centerMap: Bool = true) {
        latField.stringValue = String(format: "%.6f", lat)
        lonField.stringValue = String(format: "%.6f", lon)
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        annotation.coordinate = coord
        if centerMap {
            mapView.setRegion(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200), animated: true)
        }
    }

    @objc func mapStyleChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: mapView.mapType = .satellite
        case 2: mapView.mapType = .hybrid
        default: mapView.mapType = .standard
        }
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let id = "pin"
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
        if view == nil {
            view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        }
        view?.annotation = annotation
        view?.isDraggable = true
        view?.canShowCallout = true
        return view
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        if newState == .ending, let coord = view.annotation?.coordinate {
            latField.stringValue = String(format: "%.6f", coord.latitude)
            lonField.stringValue = String(format: "%.6f", coord.longitude)
            for c in chips { c.state = .off }
        }
    }

    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        print("[DEBUG] map did finish loading")
    }

    func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
        print("[DEBUG] map load FAILED: \(error.localizedDescription)")
    }

    @objc func copyAction() {
        let s = "\(latField.stringValue), \(lonField.stringValue)"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        flashStatus("已复制坐标")
    }

    @objc func toggleAction() {
        if controller.isActive {
            controller.stop()
            return
        }
        guard let lat = Double(latField.stringValue.trimmingCharacters(in: .whitespaces)),
              let lon = Double(lonField.stringValue.trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(lat), (-180...180).contains(lon) else {
            statusLine.stringValue = "请先输入有效经纬度（或用搜索/常用位置）"
            openSettings()
            return
        }
        let ok = controller.start(lat: lat, lon: lon)
        if !ok {
            statusLine.stringValue = controller.lastError ?? "启动失败"
            openSettings()
        }
    }

    @objc func resetAction() {
        controller.stop()
        latField.stringValue = ""
        lonField.stringValue = ""
        for c in chips { c.state = .off }
        flashStatus("已重置，恢复真实定位")
    }

    private var flashTimer: Timer?
    func flashStatus(_ text: String) {
        statusLine.stringValue = text
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            self?.refreshUI()
        }
    }

    // MARK: 刷新界面

    func refreshUI() {
        let summary = controller.statusSummary()
        if let statusLine = statusLine { statusLine.stringValue = summary }
        if let deviceValue = deviceValue {
            deviceValue.stringValue = controller.connected
                ? (controller.deviceName ?? "iPhone") + " · 已连接"
                : "未检测到设备"
        }
        let active = controller.isActive
        toggleButton?.title = active ? "■ 停止模拟" : "▶ 开始模拟"
        toggleButton?.colors = active ? [.systemRed, .systemRed] : [.brandIndigo, .brandCyan]

        if active {
            setPill(color: .systemGreen, text: "正在模拟")
        } else if controller.lastError != nil {
            setPill(color: .systemRed, text: "错误")
        } else if controller.connected {
            setPill(color: .secondaryLabelColor, text: "已连接")
        } else {
            setPill(color: .systemOrange, text: "未连接")
        }
    }

    func setPill(color: NSColor, text: String) {
        pillDot.fillColor = color
        pillLabel.textColor = color
        pillLabel.stringValue = text
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
