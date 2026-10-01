import AppKit

/// 工具栏上的字体投放区：点一下选文件，也可以把字体直接拖上来。
final class FontSlotView: NSView {

    private let title: String
    private(set) var item: FontItem?

    var onPick: (() -> Void)?
    var onDrop: ((FontItem) -> Void)?

    private var isTargeted = false

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])
        toolTip = "把字体文件拖到这里，或点击选择"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func setItem(_ newItem: FontItem?) {
        item = newItem
        toolTip = newItem.map { $0.url.path } ?? "把字体文件拖到这里，或点击选择"
        needsDisplay = true
    }

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

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        (title as NSString).draw(at: NSPoint(x: 12, y: 7), withAttributes: titleAttrs)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle

        let name = item?.fullName ?? "拖入字体文件，或点击选择"
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: item == nil ? .regular : .medium),
            .foregroundColor: item == nil ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        (name as NSString).draw(in: NSRect(x: 12, y: 23, width: bounds.width - 24, height: 18),
                                withAttributes: nameAttrs)
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
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedFontURL(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        needsDisplay = true
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
