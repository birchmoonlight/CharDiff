import AppKit

/// 看着是普通文字标签，其实能点：鼠标移上去变手型，按一下回调。
final class ClickableLabel: NSTextField {

    var onClick: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        stringValue = title
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
