import AppKit
import CoreText

// Measured from the live Mubu UI: outline 34/54.4, rows 16/25.6 + 6,
// 28-point nesting, and map text 24/16/14. These tokens affect overview only.
enum OverviewAppearance: Int { case system, light, dark }
enum OverviewMapStyle: Int { case ink, focus }
enum OverviewMapStructure: Int { case balanced, right }

@MainActor enum OverviewTypography {
    private static let registeredFonts: Void = {
        var directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts/SourceSansPro", isDirectory: true)
        #if DEBUG
        if directory.map({ !FileManager.default.fileExists(atPath: $0.appendingPathComponent("SourceSansPro-Regular.otf").path) }) ?? true {
            directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("assets/fonts/SourceSansPro", isDirectory: true)
        }
        #endif
        guard let directory else { return }
        for name in ["SourceSansPro-Regular.otf", "SourceSansPro-Semibold.otf"] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular, map: Bool = false) -> NSFont {
        if map, let font = NSFont(name: weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size) { return font }
        _ = registeredFonts
        return NSFont(name: weight == .semibold ? "SourceSansPro-Semibold" : "SourceSansPro-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, map: Bool = false) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font(size, weight: weight, map: map)]).width)
    }
    static func detailHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return textHeight(text, width: width, size: 14, lineHeight: 24)
    }
    static func textHeight(_ text: String, width: CGFloat, size: CGFloat, lineHeight: CGFloat,
                           weight: NSFont.Weight = .regular, map: Bool = false) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        let selectedFont = font(size, weight: weight, map: map)
        if !text.contains("\n"), !text.contains("\r"),
           (text as NSString).size(withAttributes: [.font: selectedFont]).width <= max(1, width) { return lineHeight }
        let storage = NSTextStorage(string: text, attributes: [.font: selectedFont, .paragraphStyle: paragraph])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, _, _ in lines += 1 }
        if manager.extraLineFragmentTextContainer === container { lines += 1 }
        return CGFloat(max(1, lines)) * lineHeight
    }
}

@MainActor struct OverviewColors {
    var dark: Bool
    var mapStyle: OverviewMapStyle
    var outlineBackground: NSColor { dark ? Self.rgb(28, 28, 30) : .white }
    var text: NSColor { dark ? Self.rgb(212, 212, 212) : Self.rgb(46, 46, 46) }
    var title: NSColor { dark ? .white : Self.rgb(46, 46, 46) }
    var detail: NSColor { Self.rgb(143, 149, 158) }
    var guide: NSColor { dark ? Self.rgb(55, 60, 67) : .black.withAlphaComponent(0.1) }
    var bullet: NSColor { Self.rgb(148, 148, 148) }
    var mapBackground: NSColor { mapStyle == .ink ? .white : Self.rgb(23, 23, 23) }
    var mapRoot: NSColor { mapStyle == .ink ? Self.rgb(10, 10, 10) : Self.rgb(212, 212, 212) }
    var mapRootText: NSColor { mapStyle == .ink ? .white : Self.rgb(10, 10, 10) }
    var mapTopic: NSColor { mapStyle == .ink ? Self.rgb(241, 241, 241) : Self.rgb(68, 68, 68) }
    var mapText: NSColor { mapStyle == .ink ? Self.rgb(10, 10, 10) : Self.rgb(212, 212, 212) }
    var mapLine: NSColor { mapStyle == .ink ? Self.rgb(184, 184, 184) : Self.rgb(102, 102, 102) }
    var mapDetail: NSColor { mapStyle == .ink ? Self.rgb(128, 128, 128) : Self.rgb(180, 180, 180) }
    static let accent = rgb(88, 86, 213)
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}
