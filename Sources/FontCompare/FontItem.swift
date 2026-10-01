import AppKit
import CoreText

/// 一个已加载的字体。descriptor 常驻，按需以不同字号创建 CTFont。
struct FontItem {
    let url: URL
    let fullName: String
    let postScriptName: String
    let descriptor: CTFontDescriptor

    static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    static func isFontFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func load(url: URL) -> FontItem? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }

        let probe = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let full = (CTFontCopyFullName(probe) as String?) ?? url.deletingPathExtension().lastPathComponent
        let ps = (CTFontCopyPostScriptName(probe) as String?) ?? ""

        return FontItem(url: url, fullName: full, postScriptName: ps, descriptor: descriptor)
    }

    /// 按字号取出可绘制的字体，UPM 不同的字体在 CoreText 里会自动归一到同一 em。
    func font(size: CGFloat) -> CTFont {
        CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
