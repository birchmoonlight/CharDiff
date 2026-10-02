import AppKit

/// 数字输入框：键盘输入回车生效，鼠标停在上面滚轮也能调。
final class ScrollNumberField: NSTextField {

    /// 滚轮回调，参数是本次的滚动增量。
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        // 不调 super，免得事件冒到父视图去。
        onScroll?(event.scrollingDeltaY)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}
