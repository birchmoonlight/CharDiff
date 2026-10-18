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

    // MARK: - 点击反馈

    private enum FlashStyle { case append, copy }

    private var highlightedIndex: Int?
    private var flashStyle: FlashStyle = .append
    private var highlightTimer: Timer?

    private func flash(_ index: Int, style: FlashStyle) {
        highlightedIndex = index
        flashStyle = style
        needsDisplay = true
        highlightTimer?.invalidate()
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.highlightedIndex = nil
            self?.needsDisplay = true
        }
    }

    /// 只有真的能点的字符列才显示手型。
    override func resetCursorRects() {
        let (placed, _) = layout()
        for item in placed {
            addCursorRect(item.rect, cursor: .pointingHand)
        }
    }

    /// 左键：把字符追加到指定文件。
    var onAppendCharacter: ((String) -> Void)?

    /// 右键：把字符复制到剪贴板。
    var onCopyCharacter: ((String) -> Void)?

    /// 松手才算一次点击，按下就触发的话拖着鼠标划过会连着一串。
    override func mouseUp(with event: NSEvent) {
        guard let index = characterIndex(at: event) else { return }
        flash(index, style: .append)
        onAppendCharacter?(cells[index].text)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let index = characterIndex(at: event) else { return }
        flash(index, style: .copy)
        onCopyCharacter?(cells[index].text)
    }

    private func characterIndex(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        let (placed, _) = layout()
        return placed.firstIndex { $0.rect.contains(point) }
    }

    /// 触控板双指捏合，回传放大倍数（1.0 表示没变）。
    var onMagnify: ((CGFloat) -> Void)?

    override func magnify(with event: NSEvent) {
        onMagnify?(1 + event.magnification)
    }

    private func draggedFontURLs(_ info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                             options: options) as? [URL] else { return [] }
        return urls.filter { FontItem.isFontFile($0) }
    }

    // MARK: - 布局常量

    private let outerMargin: CGFloat = 16
    private let cellPaddingH: CGFloat = 0    // 列宽就是最宽那个字体的宽度，不留人为间距
    private let cellPaddingV: CGFloat = 6
    private let rowGap: CGFloat = 6          // A 行与 B 行之间的间隙
    private let cellGap: CGFloat = 0         // 列与列、排与排之间的间隙
    private static let minGlyphWidth: CGFloat = 12

    // MARK: - 配色（跟随系统深浅色）

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var canvasColor: NSColor {
        isDark ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white
    }

    private var colorA: CGColor {
        (isDark ? NSColor(calibratedWhite: 0.93, alpha: 1)
                : NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)).cgColor
    }

    private var colorB: CGColor {
        (isDark ? NSColor(calibratedRed: 1.00, green: 0.46, blue: 0.40, alpha: 1)
                : NSColor(calibratedRed: 0.88, green: 0.20, blue: 0.17, alpha: 1)).cgColor
    }

    private var guideColor: CGColor {
        NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.95,
                alpha: isDark ? 0.45 : 0.30).cgColor
    }

    /// 追加和复制用不同颜色闪，一眼能分清刚才那下干了什么。
    private var flashColor: NSColor {
        switch flashStyle {
        case .append:
            return NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.30 : 0.14)
        case .copy:
            return NSColor.systemGreen.withAlphaComponent(isDark ? 0.34 : 0.20)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

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

    /// 同一个字的量度，重复出现时直接复用。
    private struct Metrics {
        let a: Line?
        let b: Line?
        let inkTop: CGFloat
        let inkBottom: CGFloat
        let left: CGFloat
        let right: CGFloat
    }

    /// 字形的墨迹范围，按 1pt 字号归一后按「字体 + 字」记住。
    /// 求这个范围要把字形轮廓整个解出来，中文字形一个就要零点几毫秒，
    /// 长 txt 里这两三秒全花在这儿；而它是随字号等比缩放的，所以存一次就够。
    private struct Ink {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var left: CGFloat = 0
        var right: CGFloat = 0
    }

    private final class InkCache: @unchecked Sendable {
        static let shared = InkCache()
        private var entries: [String: Ink] = [:]
        private let lock = NSLock()
        private let limit = 100_000

        func value(for key: String) -> Ink? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]
        }

        func insert(_ ink: Ink, for key: String) {
            lock.lock(); defer { lock.unlock() }
            if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
            entries[key] = ink
        }
    }

    /// 后台算好搬回主线程的结果，跨线程只读。
    private final class BuildResult: @unchecked Sendable {
        var cells: [Cell] = []
        var maxAscender: CGFloat = 0
        var maxDescender: CGFloat = 0
        var maxLeftOverflow: CGFloat = 0
        var unitHeight: CGFloat = 0
    }

    private var cells: [Cell] = []
    private var maxAscender: CGFloat = 0
    private var maxDescender: CGFloat = 0
    private var maxLeftOverflow: CGFloat = 0
    private var unitHeight: CGFloat = 0

    /// 排布结果缓存：滚动、点选、画手型都来问它，不必每次重排。
    private var layoutCache: (width: CGFloat, placed: [Placed], height: CGFloat)?
    private var lastLayoutWidth: CGFloat = -1

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

    /// 超过这个字数就丢到后台去算，免得载入长 txt 时主线程转圈。
    private static let backgroundThreshold = 300

    private var buildToken = 0
    private var rebuildScheduled = false

    /// 长文本正在后台排版。
    private(set) var isBuilding = false

    /// 排版进度（0…1），画提示用。
    private var buildProgress: Double = 0
    private var buildCount = 0

    /// 慢到值得打扰才盖提示，快的一下就过去了，闪一下反而烦。
    private var showsBuildHint = false
    private var buildHintTimer: Timer?

    private static let hintDelay: TimeInterval = 0.3

    private func beginBuildHint(count: Int) {
        buildProgress = 0
        buildCount = count
        buildHintTimer?.invalidate()
        buildHintTimer = Timer.scheduledTimer(withTimeInterval: Self.hintDelay, repeats: false) { [weak self] _ in
            guard let self, self.isBuilding else { return }
            self.showsBuildHint = true
            self.needsDisplay = true
        }
    }

    private func endBuildHint() {
        buildHintTimer?.invalidate()
        buildHintTimer = nil
        showsBuildHint = false
    }

    /// 连着改字体、字号、字符时（选字体那一下就会改好几样）合并成一次算。
    private func rebuild() {
        buildToken &+= 1
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.rebuildScheduled = false
            self?.startBuild()
        }
    }

    private func startBuild() {
        let token = buildToken

        let chars = characters
        let a = fontA
        let b = fontB
        let size = pointSize

        guard a != nil || b != nil, !chars.isEmpty else {
            apply(BuildResult())
            return
        }

        if chars.count <= Self.backgroundThreshold {
            apply(Self.build(chars, a: a, b: b, size: size))
        } else {
            isBuilding = true
            beginBuildHint(count: chars.count)
            needsDisplay = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Self.build(chars, a: a, b: b, size: size) { done, total in
                    DispatchQueue.main.async {
                        guard let self, self.buildToken == token else { return }
                        self.buildProgress = Double(done) / Double(max(total, 1))
                        if self.showsBuildHint { self.needsDisplay = true }
                    }
                }
                DispatchQueue.main.async {
                    // 算的期间又改了输入就丢掉这次结果。
                    guard let self, self.buildToken == token else { return }
                    self.apply(result)
                }
            }
        }
    }

    private func apply(_ result: BuildResult) {
        isBuilding = false
        endBuildHint()
        cells = result.cells
        maxAscender = result.maxAscender
        maxDescender = result.maxDescender
        maxLeftOverflow = result.maxLeftOverflow
        unitHeight = result.unitHeight
        layoutCache = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private static func build(_ characters: [String],
                              a: FontItem?,
                              b: FontItem?,
                              size: CGFloat,
                              progress: ((Int, Int) -> Void)? = nil) -> BuildResult {
        let result = BuildResult()
        guard size > 0 else { return result }
        let ctA = a?.font(size: size)
        let ctB = b?.font(size: size)
        guard ctA != nil || ctB != nil, !characters.isEmpty else { return result }
        let keyA = a.map(fontKey) ?? ""
        let keyB = b.map(fontKey) ?? ""

        // 行高按实际墨迹算。字体的 ascent/descent 留白很大，中文字形根本用不满，
        // 照那个排上下两行会离得太远。变形字体超出字身框的笔画也一并算进来。
        var inkTop: CGFloat = 0
        var inkBottom: CGFloat = 0
        var maxLeft: CGFloat = 0
        var built: [Cell] = []
        built.reserveCapacity(characters.count)

        // 长 txt 里重字很多，同一个字只量一次。
        var cache: [String: Metrics] = [:]
        cache.reserveCapacity(min(characters.count, 4096))

        for (index, ch) in characters.enumerated() {
            // 别每处理一个字就回一次主线程，隔一段报一次。
            if let progress, index % 1024 == 0 { progress(index, characters.count) }

            let metrics: Metrics
            if let cached = cache[ch] {
                metrics = cached
            } else {
                let la = ctA.map { makeLine(ch, font: $0) }
                let lb = ctB.map { makeLine(ch, font: $0) }

                let inkA = ink(of: la?.ctLine, key: keyA + "|" + ch, size: size)
                let inkB = ink(of: lb?.ctLine, key: keyB + "|" + ch, size: size)
                let advA = la?.ctLine.map(lineWidth) ?? 0
                let advB = lb?.ctLine.map(lineWidth) ?? 0

                // 原点左侧可能有负 LSB，所有列共用同一份左侧余量，原点才对得齐。
                let left = max(0, inkA.left, inkB.left)
                let right = max(advA, advB, inkA.right, inkB.right, minGlyphWidth)

                metrics = Metrics(a: la, b: lb,
                                  inkTop: max(inkA.top, inkB.top),
                                  inkBottom: max(inkA.bottom, inkB.bottom),
                                  left: left, right: right)
                cache[ch] = metrics
            }

            inkTop = max(inkTop, metrics.inkTop)
            inkBottom = max(inkBottom, metrics.inkBottom)
            maxLeft = max(maxLeft, metrics.left)
            built.append(Cell(text: ch, a: metrics.a, b: metrics.b,
                              contentWidth: metrics.left + metrics.right))
        }

        // 全是标点这类矮字符时给个下限，免得行高塌成一条。
        result.maxAscender = ceil(max(inkTop, size * 0.55))
        result.maxDescender = ceil(max(inkBottom, size * 0.10))
        result.unitHeight = result.maxAscender + result.maxDescender
        result.maxLeftOverflow = ceil(maxLeft)
        result.cells = built
        return result
    }

    private static func makeLine(_ s: String, font: CTFont) -> Line {
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

    private static func lineWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 字体身份。同一个字在不同字体里的墨迹范围不一样，缓存得分开存。
    private static func fontKey(_ item: FontItem) -> String {
        item.url.path + "|" + item.postScriptName
    }

    /// 字形墨迹范围，单位是「1pt 字号下的值」，用的时候乘字号。
    private static func ink(of line: CTLine?, key: String, size: CGFloat) -> Ink {
        guard let line else { return Ink() }
        if let cached = InkCache.shared.value(for: key) {
            return Ink(top: cached.top * size, bottom: cached.bottom * size,
                       left: cached.left * size, right: cached.right * size)
        }
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let normalized = Ink(top: bounds.maxY / size, bottom: -bounds.minY / size,
                             left: -bounds.minX / size, right: bounds.maxX / size)
        InkCache.shared.insert(normalized, for: key)
        return Ink(top: bounds.maxY, bottom: -bounds.minY,
                   left: -bounds.minX, right: bounds.maxX)
    }

    /// 字体里是否有这个字形（逐字符查，覆盖 BMP）。
    private static func hasGlyph(_ s: String, font: CTFont) -> Bool {
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
        placed.reserveCapacity(cells.count)
        var x = outerMargin
        var y = outerMargin

        for cell in cells {
            let w = cellWidth(cell)
            if x + w > limitX && x > outerMargin {
                x = outerMargin
                y += cellHeight + cellGap
            }
            placed.append(Placed(cell: cell, rect: NSRect(x: x, y: y, width: w, height: cellHeight)))
            x += w + cellGap
        }

        return (placed, y + cellHeight + outerMargin)
    }

    /// 排布只算一次，宽度没变就一直用。
    private func layout() -> ([Placed], CGFloat) {
        let width = bounds.width > 0 ? bounds.width : 900
        if let cache = layoutCache, abs(cache.width - width) < 0.5 {
            return (cache.placed, cache.height)
        }
        let (placed, height) = layoutCells(in: width)
        layoutCache = (width, placed, height)
        return (placed, height)
    }

    override var intrinsicContentSize: NSSize {
        let (_, height) = layout()
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 200))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(newSize.width - lastLayoutWidth) > 1 {
            lastLayoutWidth = newSize.width
            layoutCache = nil
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        canvasColor.setFill()
        bounds.fill()

        // 排版没完就先盖住，别让人把上一次的字当成这次的结果。
        if showsBuildHint {
            drawBuildHint()
            return
        }

        let ctA = fontA?.font(size: pointSize)
        let ctB = fontB?.font(size: pointSize)

        guard ctA != nil || ctB != nil, !cells.isEmpty else {
            drawPlaceholder()
            return
        }

        let (placed, _) = layout()

        // 点击反馈：给点中的那一列垫个底色
        if let index = highlightedIndex, index < placed.count,
           placed[index].rect.insetBy(dx: -3, dy: -3).intersects(dirtyRect) {
            flashColor.setFill()
            let box = placed[index].rect.insetBy(dx: -3, dy: -3)
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        }

        // 只重画脏区里的列，长文本滚动时才不会整屏重来。
        let visible = placed.filter { $0.rect.intersects(dirtyRect) }
        guard !visible.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }

        if showGuides { strokeGuides(visible, context: ctx) }
        drawGlyphs(visible, context: ctx)
    }

    /// 长文本在后台排版，盖一层说明白在干什么，别让人以为没反应。
    private func drawBuildHint() {
        let text = "正在排版 \(buildCount) 个字…"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        // 画布是滚动视图的 documentView，bounds 是整篇的高度，visibleRect 才是看得见的那块。
        let area = visibleRect.isEmpty ? bounds : visibleRect
        let barWidth: CGFloat = 180
        let barHeight: CGFloat = 4
        let panel = NSRect(x: area.midX - barWidth / 2 - 20,
                           y: area.midY - 34,
                           width: barWidth + 40,
                           height: 68)
        NSColor.controlBackgroundColor.withAlphaComponent(isDark ? 0.82 : 0.9).setFill()
        let path = NSBezierPath(roundedRect: panel, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        (text as NSString).draw(at: NSPoint(x: panel.midX - textSize.width / 2,
                                            y: panel.minY + 14),
                                withAttributes: attrs)

        let track = NSRect(x: panel.midX - barWidth / 2, y: panel.maxY - 22,
                           width: barWidth, height: barHeight)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        let filled = NSRect(x: track.minX, y: track.minY,
                            width: max(barHeight, track.width * CGFloat(min(max(buildProgress, 0), 1))),
                            height: barHeight)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }

    /// 一个格子里每条基线的 y（叠加模式只有一条）。
    private func baselines(in rect: NSRect) -> [CGFloat] {
        let top = rect.minY + cellPaddingV
        if overlayMode { return [top + maxAscender] }
        return (0..<lineCount).map { top + maxAscender + CGFloat($0) * (unitHeight + rowGap) }
    }

    /// 参考线合成一条路径一次描完——逐字符描两次线在长文本下开销非常大。
    private func strokeGuides(_ placed: [Placed], context ctx: CGContext) {
        let path = CGMutablePath()
        for item in placed {
            let rect = item.rect
            let originX = rect.minX + cellPaddingH + maxLeftOverflow

            path.move(to: CGPoint(x: originX, y: rect.minY + 3))
            path.addLine(to: CGPoint(x: originX, y: rect.maxY - 3))

            for baseline in baselines(in: rect) {
                path.move(to: CGPoint(x: rect.minX + 3, y: baseline))
                path.addLine(to: CGPoint(x: rect.maxX - 3, y: baseline))
            }
        }

        ctx.saveGState()
        ctx.setStrokeColor(guideColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [2, 3])
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// 同一批字符：同色同透明度的一次画完，不用每个字存取一次图形状态。
    private struct Batch {
        let color: CGColor
        let alpha: CGFloat
        var lines: [(CTLine, CGPoint)] = []
        var missing: [CGRect] = []
    }

    private func drawGlyphs(_ placed: [Placed], context ctx: CGContext) {
        var a = Batch(color: colorA, alpha: 1)
        var bSolid = Batch(color: colorB, alpha: 1)     // 下面没东西垫着
        var bFaded = Batch(color: colorB, alpha: 0.6)   // 叠加模式下压在 A 上

        for item in placed {
            let rect = item.rect
            let originX = rect.minX + cellPaddingH + maxLeftOverflow
            let top = rect.minY + cellPaddingV

            if overlayMode {
                let baseline = top + maxAscender
                if let line = item.cell.a {
                    append(line, at: CGPoint(x: originX, y: baseline), to: &a)
                }
                if let line = item.cell.b {
                    if item.cell.a == nil {
                        append(line, at: CGPoint(x: originX, y: baseline), to: &bSolid)
                    } else {
                        append(line, at: CGPoint(x: originX, y: baseline), to: &bFaded)
                    }
                }
                continue
            }

            var row = 0
            if let line = item.cell.a {
                append(line, at: CGPoint(x: originX, y: top + maxAscender), to: &a)
                row += 1
            }
            if let line = item.cell.b {
                let baseline = top + maxAscender + CGFloat(row) * (unitHeight + rowGap)
                append(line, at: CGPoint(x: originX, y: baseline), to: &bSolid)
            }
        }

        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for batch in [a, bSolid, bFaded] where !batch.lines.isEmpty || !batch.missing.isEmpty {
            draw(batch, context: ctx)
        }
    }

    private func append(_ line: Line, at origin: CGPoint, to batch: inout Batch) {
        if let ctLine = line.ctLine {
            batch.lines.append((ctLine, origin))
        } else {
            let side = pointSize * 0.42
            batch.missing.append(CGRect(x: origin.x, y: origin.y - side * 0.75,
                                        width: side, height: side))
        }
    }

    private func draw(_ batch: Batch, context ctx: CGContext) {
        if !batch.lines.isEmpty {
            ctx.saveGState()
            ctx.setFillColor(batch.color)
            ctx.setAlpha(batch.alpha)
            for (line, origin) in batch.lines {
                ctx.textPosition = origin
                CTLineDraw(line, ctx)
            }
            ctx.restoreGState()
        }

        // 缺字形的画个虚线空框占位，同样合成一条路径。
        if !batch.missing.isEmpty {
            let path = CGMutablePath()
            for box in batch.missing { path.addRect(box) }
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }
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
