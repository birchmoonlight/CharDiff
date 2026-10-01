import AppKit
import UniformTypeIdentifiers

final class MainViewController: NSViewController {

    private let compareView = CompareView()
    private var itemA: FontItem?
    private var itemB: FontItem?

    private let slotA = FontSlotView(title: "字体 A")
    private let slotB = FontSlotView(title: "字体 B")
    private let sizeSlider = NSSlider(value: 72, minValue: 16, maxValue: 200, target: nil, action: nil)
    private let sizeValueLabel = NSTextField(labelWithString: "72")
    private let overlayCheck = NSButton(checkboxWithTitle: "叠加", target: nil, action: nil)
    private let guidesCheck = NSButton(checkboxWithTitle: "参考线", target: nil, action: nil)
    private let charField = NSTextField(string: "")

    private let defaultCharacters = "永国这们的一是不了在人有我他大来以个中上水火山石田日月天地"
        + "AaGgRrQq0123&?@"

    // MARK: - 构建界面

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 820))

        let toolbar = makeToolbar()
        let charRow = makeCharRow()

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.autohidesScrollers = true

        compareView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = compareView

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator

        root.addSubview(toolbar)
        root.addSubview(charRow)
        root.addSubview(divider)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            charRow.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            charRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            charRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            divider.topAnchor.constraint(equalTo: charRow.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            // documentView 宽度跟随可视区，高度靠 intrinsicContentSize
            compareView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            compareView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            compareView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        view = root

        compareView.onDropFonts = { [weak self] items in
            self?.acceptDroppedFonts(items)
        }
        setupSlots()

        restoreSettings()
        applyCharacters()
        refreshFonts()
    }

    // MARK: - 设置记忆

    /// 用固定 suite，命令行版和 .app 版共用同一份设置。
    private let settings = UserDefaults(suiteName: "local.fontcompare") ?? .standard

    private func restoreSettings() {
        if let text = settings.string(forKey: "characters"), !text.isEmpty {
            charField.stringValue = text
        } else {
            charField.stringValue = defaultCharacters
        }

        if let path = settings.string(forKey: "fontA") {
            itemA = FontItem.load(url: URL(fileURLWithPath: path))
        }
        if let path = settings.string(forKey: "fontB") {
            itemB = FontItem.load(url: URL(fileURLWithPath: path))
        }

        let size = settings.double(forKey: "pointSize")
        if size >= sizeSlider.minValue, size <= sizeSlider.maxValue {
            sizeSlider.doubleValue = size
            sizeValueLabel.stringValue = String(Int(size))
            compareView.pointSize = CGFloat(size)
        }

        if settings.object(forKey: "overlay") != nil {
            let on = settings.bool(forKey: "overlay")
            overlayCheck.state = on ? .on : .off
            compareView.overlayMode = on
        }

        if settings.object(forKey: "guides") != nil {
            let on = settings.bool(forKey: "guides")
            guidesCheck.state = on ? .on : .off
            compareView.showGuides = on
        }
    }

    private func saveSettings() {
        settings.set(charField.stringValue, forKey: "characters")
        settings.set(itemA?.url.path, forKey: "fontA")
        settings.set(itemB?.url.path, forKey: "fontB")
        settings.set(Double(compareView.pointSize), forKey: "pointSize")
        settings.set(compareView.overlayMode, forKey: "overlay")
        settings.set(compareView.showGuides, forKey: "guides")
    }

    private func makeToolbar() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let swapButton = NSButton(title: "⇄", target: self, action: #selector(swapFonts))
        swapButton.bezelStyle = .rounded
        swapButton.toolTip = "交换 A / B"

        for slot in [slotA, slotB] {
            slot.widthAnchor.constraint(equalToConstant: 250).isActive = true
            slot.heightAnchor.constraint(equalToConstant: 46).isActive = true
        }

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true

        sizeValueLabel.textColor = .secondaryLabelColor
        sizeValueLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true

        overlayCheck.target = self
        overlayCheck.action = #selector(toggleOverlay)
        overlayCheck.toolTip = "两个字体重叠在同一基线上"

        guidesCheck.target = self
        guidesCheck.action = #selector(toggleGuides)
        guidesCheck.state = .on
        guidesCheck.toolTip = "标出每个字符的原点与基线"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(slotA)
        stack.addArrangedSubview(swapButton)
        stack.addArrangedSubview(slotB)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(NSTextField(labelWithString: "字号"))
        stack.addArrangedSubview(sizeSlider)
        stack.addArrangedSubview(sizeValueLabel)
        stack.addArrangedSubview(overlayCheck)
        stack.addArrangedSubview(guidesCheck)

        return stack
    }

    private func makeCharRow() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        let title = NSTextField(labelWithString: "字符")
        title.textColor = .secondaryLabelColor

        charField.delegate = self
        charField.placeholderString = "在这里粘贴要对比的字符，顺序随意，重复的会自动去掉"
        charField.font = .systemFont(ofSize: 14)
        charField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        charField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(charField)
        return stack
    }

    // MARK: - 动作

    private func setupSlots() {
        slotA.onPick = { [weak self] in
            self?.pickFont { [weak self] item in
                self?.itemA = item
                self?.refreshFonts()
            }
        }
        slotB.onPick = { [weak self] in
            self?.pickFont { [weak self] item in
                self?.itemB = item
                self?.refreshFonts()
            }
        }
        slotA.onDrop = { [weak self] item in
            self?.itemA = item
            self?.refreshFonts()
        }
        slotB.onDrop = { [weak self] item in
            self?.itemB = item
            self?.refreshFonts()
        }
    }

    /// 拖到画布上：两个文件按顺序填 A、B；一个文件优先填空槽，都满了就换掉 B。
    private func acceptDroppedFonts(_ items: [FontItem]) {
        if items.count >= 2 {
            itemA = items[0]
            itemB = items[1]
        } else if let dropped = items.first {
            if itemA == nil { itemA = dropped } else { itemB = dropped }
        }
        refreshFonts()
    }

    @objc private func swapFonts() {
        swap(&itemA, &itemB)
        refreshFonts()
    }

    @objc private func sizeChanged() {
        let size = CGFloat(sizeSlider.doubleValue.rounded())
        sizeValueLabel.stringValue = String(Int(size))
        compareView.pointSize = size
        saveSettings()
    }

    @objc private func toggleOverlay() {
        compareView.overlayMode = overlayCheck.state == .on
        saveSettings()
    }

    @objc private func toggleGuides() {
        compareView.showGuides = guidesCheck.state == .on
        saveSettings()
    }

    private func pickFont(assign: @escaping (FontItem) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选一个字体文件（ttf / otf / ttc）"

        var types: [UTType] = []
        for ext in ["ttf", "otf", "ttc", "otc"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        if !types.isEmpty { panel.allowedContentTypes = types }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let item = FontItem.load(url: url) else {
                let alert = NSAlert()
                alert.messageText = "加载失败"
                alert.informativeText = "读不出这个字体文件：\(url.lastPathComponent)"
                alert.runModal()
                return
            }
            assign(item)
        }
    }

    private func refreshFonts() {
        slotA.setItem(itemA)
        slotB.setItem(itemB)
        compareView.fontA = itemA
        compareView.fontB = itemB
        saveSettings()
    }

    /// 把当前画布整幅渲染成 PNG。
    func exportSnapshot(to url: URL) {
        view.layoutSubtreeIfNeeded()
        let height = compareView.intrinsicContentSize.height
        compareView.frame = NSRect(x: 0, y: 0, width: compareView.frame.width, height: height)
        compareView.layoutSubtreeIfNeeded()

        guard let rep = compareView.bitmapImageRepForCachingDisplay(in: compareView.bounds) else { return }
        compareView.cacheDisplay(in: compareView.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    /// 启动参数直接带字体和字符：--a 路径 --b 路径 --text 字符
    func applyLaunchOptions(fontA: URL?, fontB: URL?, text: String?, overlay: Bool = false) {
        if let fontA, let item = FontItem.load(url: fontA) { itemA = item }
        if let fontB, let item = FontItem.load(url: fontB) { itemB = item }
        if let text { charField.stringValue = text }
        overlayCheck.state = overlay ? .on : .off
        compareView.overlayMode = overlay
        applyCharacters()
        refreshFonts()
    }

    private func applyCharacters() {
        var seen = Set<String>()
        var list: [String] = []
        for character in charField.stringValue {
            let s = String(character)
            if s == "\n" || s == "\r" || s == "\t" { continue }
            if seen.insert(s).inserted { list.append(s) }
        }
        compareView.characters = list
        saveSettings()
    }
}

extension MainViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === charField else { return }
        applyCharacters()
    }
}
