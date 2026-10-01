import AppKit
import CoreText

/// 对比画布：每个字符一列，两个字体的同一字符从同一条原点起画（原点对齐）。
/// 列宽由两者中较宽的那个决定，所以宽的紧贴自身宽度、窄的自然留出空白。
final class CompareView: NSView {

    // MARK: - 输入

    var fontA: FontItem? { didSet { rebuild() } }
    var fontB: FontItem? { didSet { rebuild() } }
    var characters: [String] = [] { didSet { rebuild() } }

    var pointSize: CGFloat = 72 { didSet { rebuild() } }

    /// 叠加模式：两个字体重叠在同一基线上画，看轮廓差异。
    var overlayMode: Bool = false {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    /// 参考线：标出每个字符的原点竖线与基线。
    var showGuides: Bool = true { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    /// 拖字体文件到画布上时回调，按拖入顺序给出。
    var onDropFonts: (([FontItem]) -> Void)?

    private var isTargeted = false {
        didSet {
            layer?.borderWidth = isTargeted ? 3 : 0
            layer?.borderColor = isTargeted ? NSColor.controlAccentColor.cgColor : nil
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - 拖放

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !draggedFontURLs(sender).isEmpty else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !draggedFontURLs(sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        let items = draggedFontURLs(sender).compactMap { FontItem.load(url: $0) }
        guard !items.isEmpty else { return false }
        onDropFonts?(items)
        return true
    }

    private func draggedFontURLs(_ info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                             options: options) as? [URL] else { return [] }
        return urls.filter { FontItem.isFontFile($0) }
    }

    // MARK: - 布局常量

    private let outerMargin: CGFloat = 16
    private let cellPaddingH: CGFloat = 6    // 字符之间靠这两份 padding 加 columnGap 拉开
    private let cellPaddingV: CGFloat = 10
    private let rowGap: CGFloat = 14         // A 行与 B 行之间的间隙
    private let columnGap: CGFloat = 10      // 字符列之间的间隙
    private let minGlyphWidth: CGFloat = 12

    // MARK: - 配色（固定浅色，字体对比需要白底黑字）

    private let colorA = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).cgColor
    private let colorB = NSColor(calibratedRed: 0.88, green: 0.20, blue: 0.17, alpha: 1).cgColor
    private let guideColor = NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.95, alpha: 0.30)

    // MARK: - 计算缓存

    private struct Line {
        let ctLine: CTLine?
        let missing: Bool
    }

    private struct Cell {
        let text: String
        /// nil 表示这个槽还没选字体。
        let a: Line?
        let b: Line?
        /// 墨迹宽度（含向左溢出部分），不含左右 padding。
        let contentWidth: CGFloat
    }

    private struct Placed {
        let cell: Cell
        let rect: NSRect
    }

    private var cells: [Cell] = []
    private var maxAscender: CGFloat = 0
    private var maxDescender: CGFloat = 0
    private var maxLeftOverflow: CGFloat = 0
    private var unitHeight: CGFloat = 0

    /// 选了字体才占一行，只选一个字体时就只画一行。
    private var lineCount: Int {
        var count = 0
        if fontA != nil { count += 1 }
        if fontB != nil { count += 1 }
        return max(count, 1)
    }

    private var cellHeight: CGFloat {
        if overlayMode { return unitHeight + cellPaddingV * 2 }
        let rows = CGFloat(lineCount)
        return unitHeight * rows + rowGap * (rows - 1) + cellPaddingV * 2
    }

    private func cellWidth(_ cell: Cell) -> CGFloat {
        maxLeftOverflow + cell.contentWidth + cellPaddingH * 2
    }

    // MARK: - 构建

    private func rebuild() {
        cells.removeAll()
        maxLeftOverflow = 0

        let ctA = fontA?.font(size: pointSize)
        let ctB = fontB?.font(size: pointSize)

        guard ctA != nil || ctB != nil, !characters.isEmpty else {
            unitHeight = 0
            invalidateIntrinsicContentSize()
            needsDisplay = true
            return
        }

        // 上下边界同时参考字体的 ascent/descent 与每个字形的实际墨迹，
        // 变形字体常有超出字身框的笔画。
        var ascender: CGFloat = 0
        var descender: CGFloat = 0
        if let ctA {
            ascender = max(ascender, CTFontGetAscent(ctA))
            descender = max(descender, CTFontGetDescent(ctA))
        }
        if let ctB {
            ascender = max(ascender, CTFontGetAscent(ctB))
            descender = max(descender, CTFontGetDescent(ctB))
        }

        var maxLeft: CGFloat = 0
        var built: [Cell] = []

        for ch in characters {
            let la = ctA.map { makeLine(ch, font: $0) }
            let lb = ctB.map { makeLine(ch, font: $0) }

            let inkA = la?.ctLine.map(inkBounds) ?? .zero
            let inkB = lb?.ctLine.map(inkBounds) ?? .zero
            let advA = la?.ctLine.map(lineWidth) ?? 0
            let advB = lb?.ctLine.map(lineWidth) ?? 0

            ascender = max(ascender, inkA.maxY, inkB.maxY)
            descender = max(descender, -inkA.minY, -inkB.minY)

            // 原点左侧可能有负 LSB，所有列共用同一份左侧余量，原点才对得齐。
            let left = max(0, -inkA.minX, -inkB.minX)
            let right = max(advA, advB, inkA.maxX, inkB.maxX, minGlyphWidth)
            maxLeft = max(maxLeft, left)

            built.append(Cell(text: ch, a: la, b: lb, contentWidth: left + right))
        }

        maxAscender = ceil(ascender)
        maxDescender = ceil(descender)
        unitHeight = maxAscender + maxDescender
        maxLeftOverflow = ceil(maxLeft)
        cells = built

        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func makeLine(_ s: String, font: CTFont) -> Line {
        guard hasGlyph(s, font: font) else {
            return Line(ctLine: nil, missing: true)
        }
        // 颜色交给 context，叠加模式才能随时改透明度而不用重建。
        let attrs: [String: Any] = [
            kCTFontAttributeName as String: font,
            kCTForegroundColorFromContextAttributeName as String: true,
        ]
        guard let attributed = CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary) else {
            return Line(ctLine: nil, missing: true)
        }
        return Line(ctLine: CTLineCreateWithAttributedString(attributed), missing: false)
    }

    private func lineWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func inkBounds(_ line: CTLine) -> CGRect {
        CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    }

    /// 字体里是否有这个字形（逐字符查，覆盖 BMP）。
    private func hasGlyph(_ s: String, font: CTFont) -> Bool {
        let utf16 = Array(s.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let ok = CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count)
        return ok && !glyphs.contains(0)
    }

    // MARK: - 排布

    /// 从左到右依次摆放，放不下就换行。每列宽度随字符宽度变化。
    private func layoutCells(in width: CGFloat) -> ([Placed], CGFloat) {
        guard !cells.isEmpty, cellHeight > 0 else { return ([], 200) }
        let limitX = max(width - outerMargin, outerMargin + 1)

        var placed: [Placed] = []
        var x = outerMargin
        var y = outerMargin

        for cell in cells {
            let w = cellWidth(cell)
            if x + w > limitX && x > outerMargin {
                x = outerMargin
                y += cellHeight + columnGap
            }
            placed.append(Placed(cell: cell, rect: NSRect(x: x, y: y, width: w, height: cellHeight)))
            x += w + columnGap
        }

        return (placed, y + cellHeight + outerMargin)
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 0 ? bounds.width : 900
        let (_, height) = layoutCells(in: width)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 200))
    }

    private var lastLayoutWidth: CGFloat = -1

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(newSize.width - lastLayoutWidth) > 1 {
            lastLayoutWidth = newSize.width
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let ctA = fontA?.font(size: pointSize)
        let ctB = fontB?.font(size: pointSize)

        guard ctA != nil || ctB != nil, !cells.isEmpty else {
            drawPlaceholder()
            return
        }

        let (placed, _) = layoutCells(in: bounds.width)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // flipped 视图里画 CoreText 需要再翻一次，否则字形上下颠倒。
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        for item in placed {
            drawGlyphs(item, fontA: ctA, fontB: ctB, context: ctx)
        }
    }

    private func drawGlyphs(_ item: Placed, fontA: CTFont?, fontB: CTFont?, context ctx: CGContext) {
        let rect = item.rect
        let originX = rect.minX + cellPaddingH + maxLeftOverflow
        let top = rect.minY + cellPaddingV

        if overlayMode {
            let baseline = top + maxAscender
            drawGuides(at: originX, baseline: baseline, in: rect, context: ctx)
            if let a = item.cell.a {
                draw(line: a, at: CGPoint(x: originX, y: baseline), color: colorA, alpha: 1, context: ctx)
            }
            if let b = item.cell.b {
                // 下面没有 A 垫着就不用半透明了。
                let alpha: CGFloat = item.cell.a == nil ? 1 : 0.6
                draw(line: b, at: CGPoint(x: originX, y: baseline), color: colorB, alpha: alpha, context: ctx)
            }
            return
        }

        var row = 0
        for (line, color) in [(item.cell.a, colorA), (item.cell.b, colorB)] {
            guard let line else { continue }
            let baseline = top + maxAscender + CGFloat(row) * (unitHeight + rowGap)
            drawGuides(at: originX, baseline: baseline, in: rect, context: ctx)
            draw(line: line, at: CGPoint(x: originX, y: baseline), color: color, alpha: 1, context: ctx)
            row += 1
        }
    }

    private func drawGuides(at x: CGFloat, baseline: CGFloat, in rect: NSRect, context ctx: CGContext) {
        guard showGuides else { return }
        ctx.saveGState()
        ctx.setStrokeColor(guideColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [2, 3])

        ctx.move(to: CGPoint(x: x, y: rect.minY + 3))
        ctx.addLine(to: CGPoint(x: x, y: rect.maxY - 3))
        ctx.strokePath()

        ctx.move(to: CGPoint(x: rect.minX + 3, y: baseline))
        ctx.addLine(to: CGPoint(x: rect.maxX - 3, y: baseline))
        ctx.strokePath()

        ctx.restoreGState()
    }

    private func draw(line: Line, at origin: CGPoint, color: CGColor, alpha: CGFloat, context ctx: CGContext) {
        guard let ctLine = line.ctLine else {
            // 该字体缺这个字形：画个虚线空框占位。
            let side = pointSize * 0.42
            let box = CGRect(x: origin.x, y: origin.y - side * 0.75, width: side, height: side)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.stroke(box)
            ctx.restoreGState()
            return
        }
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.setAlpha(alpha)
        ctx.textPosition = origin
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
    }

    private func drawPlaceholder() {
        let text: String
        if fontA == nil && fontB == nil {
            text = "拖字体文件进来，或点上方的方框选择"
        } else {
            text = "输入要对比的字符"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: max(outerMargin, (bounds.width - size.width) / 2),
                            y: max(outerMargin, (bounds.height - size.height) / 2))
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
