import AppKit

/// 工具栏上的字体投放区：点一下选文件，也可以把字体直接拖上来。
/// 选好之后标题让位给字体名，右边留一个清除和一下拉。
final class FontSlotView: NSView {

    private let title: String
    private(set) var item: FontItem?

    var onPick: (() -> Void)?
    var onClear: (() -> Void)?
    var onDrop: ((FontItem) -> Void)?
    /// 点下拉箭头：弹最近用过的字体列表。参数是自己，方便调用方分辨是哪个槽。
    var onShowRecent: ((FontSlotView) -> Void)?

    private let nameLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private let pickButton = NSButton()

    private var isTargeted = false {
        didSet { needsDisplay = true }
    }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])
        setupSubviews()
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func setupSubviews() {
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "清除")
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.toolTip = "清除这个字体"

        pickButton.translatesAutoresizingMaskIntoConstraints = false
        pickButton.isBordered = false
        pickButton.image = NSImage(systemSymbolName: "chevron.down",
                                   accessibilityDescription: "选择字体")
        pickButton.contentTintColor = .secondaryLabelColor
        pickButton.target = self
        pickButton.action = #selector(pickTapped)
        pickButton.toolTip = "最近用过的字体"

        addSubview(nameLabel)
        addSubview(clearButton)
        addSubview(pickButton)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pickButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pickButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pickButton.widthAnchor.constraint(equalToConstant: 20),
            pickButton.heightAnchor.constraint(equalToConstant: 20),

            clearButton.trailingAnchor.constraint(equalTo: pickButton.leadingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -6),
        ])
    }

    func setItem(_ newItem: FontItem?) {
        item = newItem
        updateContent()
    }

    private func updateContent() {
        if let item {
            nameLabel.stringValue = item.fullName
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            nameLabel.textColor = .labelColor
            toolTip = item.url.path
        } else {
            // 没选字体时这行显示槽位名，选了就让位给字体名。
            nameLabel.stringValue = title
            nameLabel.font = .systemFont(ofSize: 12)
            nameLabel.textColor = .tertiaryLabelColor
            toolTip = "把字体文件拖到这里，或点击选择"
        }
        clearButton.isHidden = item == nil
        needsDisplay = true
    }

    @objc private func pickTapped() { onShowRecent?(self) }

    @objc private func clearTapped() { onClear?() }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        if isTargeted {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        if isTargeted {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.setLineDash([5, 3], count: 2, phase: 0)
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - 点击

    override func mouseDown(with event: NSEvent) {
        onPick?()
    }

    // MARK: - 拖放

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedFontURL(sender) != nil else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedFontURL(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        guard let url = draggedFontURL(sender), let loaded = FontItem.load(url: url) else { return false }
        onDrop?(loaded)
        return true
    }

    private func draggedFontURL(_ info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                             options: options) as? [URL] else { return nil }
        return urls.first { FontItem.isFontFile($0) }
    }
}
