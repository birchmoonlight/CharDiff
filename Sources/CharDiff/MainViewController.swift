import AppKit
import UniformTypeIdentifiers

final class MainViewController: NSViewController {

    private let compareView = CompareView()
    private var itemA: FontItem?
    private var itemB: FontItem?

    private let slotA = FontSlotView(title: "字体 A")
    private let slotB = FontSlotView(title: "字体 B")
    private let sizeField = ScrollNumberField()
    private let overlayCheck = NSButton(checkboxWithTitle: "叠加", target: nil, action: nil)
    private let guidesCheck = NSButton(checkboxWithTitle: "参考线", target: nil, action: nil)
    private let newlineCheck = NSButton(checkboxWithTitle: "换行", target: nil, action: nil)
    private let dedupeCheck = NSButton(checkboxWithTitle: "去重", target: nil, action: nil)
    private let writeLabel = ClickableLabel(title: "写txt时")

    /// 挑目标 txt 的窗口，给「新建」按钮留着用来关掉它。
    private weak var activePanel: NSSavePanel?
    private var wantsNewTargetFile = false

    private let charTextView = NSTextView()
    private let charScrollView = NSScrollView()
    private var charHeightConstraint: NSLayoutConstraint!

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
        scrollView.backgroundColor = .textBackgroundColor
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
            // 画布保底高度，输入框再高也压不没它
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            // documentView 宽度跟随可视区，高度靠 intrinsicContentSize
            compareView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            compareView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            compareView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        view = root

        compareView.onDropFonts = { [weak self] items in
            self?.acceptDroppedFonts(items)
        }
        compareView.onMagnify = { [weak self] factor in
            guard let self else { return }
            self.applySize(self.compareView.pointSize * factor, persist: false)
            self.scheduleSave()
        }
        sizeField.onScroll = { [weak self] delta in
            guard let self else { return }
            self.scrollAccumulator += delta
            let steps = (self.scrollAccumulator / 4).rounded(.towardZero)
            guard steps != 0 else { return }
            self.scrollAccumulator -= steps * 4
            self.applySize(self.compareView.pointSize + steps, persist: false)
            self.scheduleSave()
        }
        compareView.onAppendCharacter = { [weak self] text in
            self?.appendPick(text)
        }
        compareView.onCopyCharacter = { [weak self] text in
            self?.copyToPasteboard(text)
        }
        setupSlots()

        restoreSettings()
        applyCharacters()
        refreshFonts()
    }

    // MARK: - 设置记忆

    /// 用固定 suite，命令行版和 .app 版共用同一份设置。
    private let settings: UserDefaults = .appSettings

    private var scrollAccumulator: CGFloat = 0

    /// 最近用过的字体，最新的排最前。
    private var recentFontPaths: [String] {
        settings.stringArray(forKey: "recentFonts") ?? []
    }

    private func rememberFont(_ url: URL) {
        var list = recentFontPaths.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        settings.set(Array(list.prefix(10)), forKey: "recentFonts")
    }

    private func setFont(_ item: FontItem?, forA: Bool) {
        if forA { itemA = item } else { itemB = item }
        if let item { rememberFont(item.url) }
        refreshFonts()
    }

    // MARK: - 最近用过的字体

    private func showRecentFonts(anchor: FontSlotView, forA: Bool) {
        let menu = NSMenu()
        let paths = recentFontPaths
        let current = forA ? itemA?.url.path : itemB?.url.path

        if paths.isEmpty {
            let empty = NSMenuItem(title: "还没有最近用过的字体", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                let entry = NSMenuItem(title: url.deletingPathExtension().lastPathComponent,
                                       action: #selector(chooseRecentFont(_:)),
                                       keyEquivalent: "")
                entry.representedObject = path
                entry.tag = forA ? 0 : 1
                entry.state = (path == current) ? .on : .off
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let browse = NSMenuItem(title: "从文件选择…",
                                action: #selector(browseForFont(_:)),
                                keyEquivalent: "")
        browse.tag = forA ? 0 : 1
        menu.addItem(browse)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: anchor.bounds.height + 4),
                   in: anchor)
    }

    @objc private func chooseRecentFont(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let item = FontItem.load(url: URL(fileURLWithPath: path)) else { return }
        setFont(item, forA: sender.tag == 0)
    }

    @objc private func browseForFont(_ sender: NSMenuItem) {
        let forA = sender.tag == 0
        pickFont { [weak self] item in
            self?.setFont(item, forA: forA)
        }
    }

    private func restoreSettings() {
        if let text = settings.string(forKey: "characters"), !text.isEmpty {
            charTextView.string = text
        } else {
            charTextView.string = defaultCharacters
        }

        if let path = settings.string(forKey: "fontA") {
            itemA = FontItem.load(url: URL(fileURLWithPath: path))
        }
        if let path = settings.string(forKey: "fontB") {
            itemB = FontItem.load(url: URL(fileURLWithPath: path))
        }

        let size = settings.double(forKey: "pointSize")
        if size >= Double(Self.minPointSize), size <= Double(Self.maxPointSize) {
            applySize(CGFloat(size), persist: false)
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

        if settings.object(forKey: "writeNewline") != nil {
            newlineCheck.state = settings.bool(forKey: "writeNewline") ? .on : .off
        }
        if settings.object(forKey: "writeDedupe") != nil {
            dedupeCheck.state = settings.bool(forKey: "writeDedupe") ? .on : .off
        }
    }

    private func saveSettings() {
        settings.set(charTextView.string, forKey: "characters")
        settings.set(itemA?.url.path, forKey: "fontA")
        settings.set(itemB?.url.path, forKey: "fontB")
        settings.set(Double(compareView.pointSize), forKey: "pointSize")
        settings.set(compareView.overlayMode, forKey: "overlay")
        settings.set(compareView.showGuides, forKey: "guides")
        settings.set(newlineCheck.state == .on, forKey: "writeNewline")
        settings.set(dedupeCheck.state == .on, forKey: "writeDedupe")
    }

    private func makeToolbar() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        let swapButton = NSButton(title: "⇄", target: self, action: #selector(swapFonts))
        swapButton.bezelStyle = .rounded
        swapButton.toolTip = "交换 A / B"

        for slot in [slotA, slotB] {
            slot.widthAnchor.constraint(equalToConstant: 230).isActive = true
            slot.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let sizeLabel = NSTextField(labelWithString: "字号")
        sizeLabel.textColor = .secondaryLabelColor

        sizeField.stringValue = "72"
        sizeField.alignment = .center
        sizeField.font = .systemFont(ofSize: 13)
        sizeField.target = self
        sizeField.action = #selector(sizeFieldChanged)
        sizeField.toolTip = "回车生效，鼠标停在上面滚滚轮也行"
        sizeField.widthAnchor.constraint(equalToConstant: 54).isActive = true

        overlayCheck.target = self
        overlayCheck.action = #selector(toggleOverlay)
        overlayCheck.toolTip = "两个字体重叠在同一基线上"
        overlayCheck.font = .systemFont(ofSize: 12)

        guidesCheck.target = self
        guidesCheck.action = #selector(toggleGuides)
        guidesCheck.state = .on
        guidesCheck.toolTip = "标出每个字符的原点与基线"
        guidesCheck.font = .systemFont(ofSize: 12)

        writeLabel.textColor = .tertiaryLabelColor
        writeLabel.font = .systemFont(ofSize: 11)
        writeLabel.onClick = { [weak self] in self?.changeTargetFile() }
        updateWriteLabelHint()

        newlineCheck.target = self
        newlineCheck.action = #selector(toggleWriteOptions)
        newlineCheck.toolTip = "一个字符占一行"
        newlineCheck.font = .systemFont(ofSize: 12)

        dedupeCheck.target = self
        dedupeCheck.action = #selector(toggleWriteOptions)
        dedupeCheck.toolTip = "同一个字只记一次"
        dedupeCheck.font = .systemFont(ofSize: 12)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(slotA)
        stack.addArrangedSubview(swapButton)
        stack.addArrangedSubview(slotB)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(sizeLabel)
        stack.addArrangedSubview(sizeField)
        stack.addArrangedSubview(overlayCheck)
        stack.addArrangedSubview(guidesCheck)
        stack.addArrangedSubview(writeLabel)
        stack.addArrangedSubview(newlineCheck)
        stack.addArrangedSubview(dedupeCheck)

        return stack
    }

    private func makeCharRow() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        // 输入框会长高，「字符」两个字跟着居中，不吊在顶上。
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        let title = ClickableLabel(title: "字符")
        title.textColor = .secondaryLabelColor
        title.toolTip = "点一下：从 txt 文件读取字符"
        title.onClick = { [weak self] in self?.loadCharactersFromFile() }
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        charTextView.isRichText = false
        charTextView.font = .systemFont(ofSize: 14)
        charTextView.delegate = self
        charTextView.allowsUndo = true
        charTextView.isAutomaticQuoteSubstitutionEnabled = false
        charTextView.isAutomaticDashSubstitutionEnabled = false
        charTextView.isAutomaticTextReplacementEnabled = false
        charTextView.drawsBackground = false
        charTextView.textContainerInset = NSSize(width: 4, height: 5)
        charTextView.isVerticallyResizable = true
        charTextView.isHorizontallyResizable = false
        charTextView.autoresizingMask = [.width]
        charTextView.textContainer?.widthTracksTextView = true
        charTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        // 长 txt 不必一次排完，用到哪排到哪。
        charTextView.layoutManager?.allowsNonContiguousLayout = true

        charScrollView.documentView = charTextView
        charScrollView.translatesAutoresizingMaskIntoConstraints = false
        charScrollView.hasVerticalScroller = true
        charScrollView.hasHorizontalScroller = false
        charScrollView.autohidesScrollers = true
        charScrollView.drawsBackground = true
        charScrollView.backgroundColor = .textBackgroundColor
        charScrollView.borderType = .bezelBorder
        charScrollView.toolTip = "粘贴要对比的字符，顺序随意，重复的会照样显示"
        charScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        charScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        charHeightConstraint = charScrollView.heightAnchor.constraint(equalToConstant: 28)
        charHeightConstraint.isActive = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(charScrollView)
        return stack
    }

    @objc private func toggleWriteOptions() {
        saveSettings()
    }

    // MARK: - 挑字写文件

    /// 左键把字符追加到文本文件；第一次用时让用户选文件，之后一直写它。
    private func appendPick(_ text: String) {
        guard let url = pickFileURL() else { return }

        let newline = newlineCheck.state == .on
        let dedupe = dedupeCheck.state == .on

        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        if dedupe {
            let exists = newline
                ? content.split(separator: "\n", omittingEmptySubsequences: false).contains { $0 == Substring(text) }
                : content.contains(text)
            if exists { return }
        }

        if newline {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += text + "\n"
        } else {
            content += text
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "写入失败"
            alert.informativeText = "写不进这个文件：\(url.path)"
            alert.runModal()
        }
    }

    /// 左键点字符写到哪个 txt。定过一次就一直用它，除非用户自己点「写txt时」换。
    private func pickFileURL(changing: Bool = false) -> URL? {
        if !changing, let path = settings.string(forKey: "pickFile") {
            return URL(fileURLWithPath: path)
        }
        guard let url = promptForTargetFile() else { return nil }
        settings.set(url.path, forKey: "pickFile")
        updateWriteLabelHint()
        return url
    }

    /// 挑一个已有的 txt，或者当场新建一个——手上还没 txt 的人也得走得下去。
    private func promptForTargetFile() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "挑一个 txt，左键点的字会追加到它后面"
        panel.prompt = "就用它"
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = targetDirectory
        panel.accessoryView = makeNewFileAccessory()
        // 不点开会话里的「显示选项」也得看得见，不然没人找得到新建按钮。
        panel.isAccessoryViewDisclosed = true

        activePanel = panel
        wantsNewTargetFile = false
        let response = panel.runModal()
        activePanel = nil

        if wantsNewTargetFile { return promptForNewTargetFile(in: panel.directoryURL) }
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }

    /// 选择窗口右下角那个「新建一个 txt」。
    private func makeNewFileAccessory() -> NSView {
        let button = NSButton(title: "新建一个 txt…", target: self, action: #selector(newTargetFileTapped))
        button.bezelStyle = .rounded
        button.sizeToFit()
        let holder = NSView(frame: NSRect(x: 0, y: 0,
                                          width: button.frame.width + 20,
                                          height: button.frame.height + 16))
        button.setFrameOrigin(NSPoint(x: 10, y: 8))
        holder.addSubview(button)
        return holder
    }

    @objc private func newTargetFileTapped() {
        wantsNewTargetFile = true
        activePanel?.cancel(nil)
    }

    private func promptForNewTargetFile(in directory: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.message = "新建一个 txt。碰到同名文件不会清空它，字是接着后面写的。"
        panel.prompt = "新建"
        panel.nameFieldStringValue = "挑字.txt"
        panel.canCreateDirectories = true
        panel.directoryURL = directory ?? targetDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// 默认落在字体 A 的文件夹，没有 A 就退到 B。
    private var targetDirectory: URL? {
        if let path = settings.string(forKey: "pickFile") {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return itemA?.url.deletingLastPathComponent() ?? itemB?.url.deletingLastPathComponent()
    }

    private func updateWriteLabelHint() {
        if let path = settings.string(forKey: "pickFile") {
            writeLabel.toolTip = "点一下换一个 txt。现在写到：\(path)"
        } else {
            writeLabel.toolTip = "点一下挑一个 txt，左键点的字都写进去"
        }
    }

    private func changeTargetFile() {
        _ = pickFileURL(changing: true)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 输入框随内容长高，但最多 4 行，再多就在框内滚动，画布不会被挤没。
    private func updateCharFieldHeight() {
        guard let layoutManager = charTextView.layoutManager,
              let textContainer = charTextView.textContainer,
              let font = charTextView.font else { return }

        let inset = charTextView.textContainerInset.height * 2
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let chrome: CGFloat = 5   // 边框占的高度

        let minHeight = ceil(lineHeight + inset + chrome)
        let maxHeight = ceil(lineHeight * 4 + inset + chrome)

        // 量高度要先让 TextKit 把整篇排一遍。长 txt 有几千上万字，这一下就得等很久，
        // 所以字多到肯定超过 4 行时直接按最高算，不量了。
        let target: CGFloat
        if (charTextView.string as NSString).length > Self.measureLimit {
            target = maxHeight
        } else {
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer).height
            target = min(max(ceil(used + inset + chrome), minHeight), maxHeight)
        }

        if abs(charHeightConstraint.constant - target) > 0.5 {
            charHeightConstraint.constant = target
        }
    }

    /// 超过这个字数就懒得量了——4 行怎么都装不下。
    private static let measureLimit = 400

    override func viewDidLayout() {
        super.viewDidLayout()
        // 宽度变了换行就变，高度得跟着重算。
        updateCharFieldHeight()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 一进来焦点给字符框，别落在字号框上。
        view.window?.makeFirstResponder(charTextView)
    }

    // MARK: - 动作

    private func setupSlots() {
        slotA.onPick = { [weak self] in
            self?.pickFont { [weak self] item in self?.setFont(item, forA: true) }
        }
        slotB.onPick = { [weak self] in
            self?.pickFont { [weak self] item in self?.setFont(item, forA: false) }
        }
        slotA.onDrop = { [weak self] item in self?.setFont(item, forA: true) }
        slotB.onDrop = { [weak self] item in self?.setFont(item, forA: false) }
        slotA.onClear = { [weak self] in
            self?.itemA = nil
            self?.refreshFonts()
        }
        slotB.onClear = { [weak self] in
            self?.itemB = nil
            self?.refreshFonts()
        }
        slotA.onShowRecent = { [weak self] slot in
            self?.showRecentFonts(anchor: slot, forA: true)
        }
        slotB.onShowRecent = { [weak self] slot in
            self?.showRecentFonts(anchor: slot, forA: false)
        }
    }

    /// 拖到画布上：两个文件按顺序填 A、B；一个文件优先填空槽，都满了就换掉 B。
    private func acceptDroppedFonts(_ items: [FontItem]) {
        if items.count >= 2 {
            setFont(items[0], forA: true)
            setFont(items[1], forA: false)
        } else if let dropped = items.first {
            setFont(dropped, forA: itemA == nil)
        } else {
            refreshFonts()
        }
    }

    @objc private func swapFonts() {
        swap(&itemA, &itemB)
        refreshFonts()
    }

    private static let minPointSize: CGFloat = 8
    private static let maxPointSize: CGFloat = 400

    @objc private func sizeFieldChanged() {
        let value = Double(sizeField.stringValue) ?? Double(compareView.pointSize)
        applySize(CGFloat(value), persist: true)
    }

    /// 字号不取整，双指缩放和滚轮才跟手；显示时再取整。
    private func applySize(_ size: CGFloat, persist: Bool) {
        let clamped = min(max(size, Self.minPointSize), Self.maxPointSize)
        sizeField.stringValue = String(Int(clamped.rounded()))
        compareView.pointSize = clamped
        if persist { saveSettings() }
    }

    /// 缩放过程中每次落盘太费，停手后再存。
    private var saveTimer: Timer?

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.saveSettings()
        }
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
    /// 画布是否已经排完版，导出前用它等一等长文本。
    var isCompareIdle: Bool { !compareView.isBuilding }

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
        if let text { charTextView.string = text }
        overlayCheck.state = overlay ? .on : .off
        compareView.overlayMode = overlay
        applyCharacters()
        refreshFonts()
    }

    // MARK: - 从 txt 读取字符

    /// 点「字符」这两个字：选一个 txt，把里面的字读进输入框（整份替换）。
    private func loadCharactersFromFile() {
        let panel = NSOpenPanel()
        panel.message = "选一个 txt 文件，里面的字会读进输入框"
        panel.prompt = "读取"
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // 上次读过的文件夹优先，其次跟着字体 A 走。
        if let dir = settings.string(forKey: "charFileDir") {
            panel.directoryURL = URL(fileURLWithPath: dir)
        } else {
            panel.directoryURL = itemA?.url.deletingLastPathComponent()
                ?? itemB?.url.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 中文 txt 未必是 UTF-8，让系统自己去猜编码。
        var encoding: UInt = 0
        guard let text = try? NSString(contentsOf: url, usedEncoding: &encoding) else {
            let alert = NSAlert()
            alert.messageText = "读不了这个文件"
            alert.informativeText = "\(url.lastPathComponent) 不是纯文本，或者编码认不出来。"
            alert.runModal()
            return
        }

        settings.set(url.deletingLastPathComponent().path, forKey: "charFileDir")
        charTextView.string = text as String
        applyCharacters()
        updateCharFieldHeight()
    }

    /// 保留重复字符——重复本身可能就是有意的分组，换行和制表符不算字符。
    private func applyCharacters() {
        var list: [String] = []
        for character in charTextView.string {
            let s = String(character)
            if s == "\n" || s == "\r" || s == "\t" { continue }
            list.append(s)
        }
        compareView.characters = list
        // 整串字存一次要写盘，长 txt 下每敲一个字都写会卡，攒一下再写。
        scheduleSave()
    }
}

extension MainViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === charTextView else { return }
        applyCharacters()
        updateCharFieldHeight()
    }
}
