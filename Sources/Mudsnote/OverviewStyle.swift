import AppKit
import CoreText

// Measured from the live Mubu UI: outline 34/54.4, rows 16/25.6 + 6,
// 28-point nesting, and map text 24/16/14. These tokens affect overview only.
enum OverviewAppearance: Int { case system, light, dark }
enum OverviewMapStyle: Int { case ink, focus }
enum OverviewMapStructure: Int { case balanced, right }

@MainActor enum OverviewTypography {
    private struct HeightCacheKey: Hashable {
        let text: String
        let widthBucket: Int
        let sizeTenths: Int
        let lineHeightTenths: Int
        let weightRaw: CGFloat
        let map: Bool
    }

    private static var heightCache: [HeightCacheKey: CGFloat] = [:]
    private static var symbolCache: [String: NSImage] = [:]
    private static let sharedStorage = NSTextStorage()
    private static let sharedTextContainer: NSTextContainer = {
        let container = NSTextContainer(size: NSSize(width: CGFloat(100), height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        return container
    }()
    private static let sharedLayoutManager: NSLayoutManager = {
        let manager = NSLayoutManager()
        sharedStorage.addLayoutManager(manager)
        manager.addTextContainer(sharedTextContainer)
        return manager
    }()

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

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(weight.rawValue)"
        if let cached = symbolCache[key] { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) else {
            return nil
        }
        symbolCache[key] = image
        return image
    }

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
        let clampedWidth = max(1, width)
        let key = HeightCacheKey(
            text: text,
            widthBucket: Int(clampedWidth.rounded()),
            sizeTenths: Int((size * 10).rounded()),
            lineHeightTenths: Int((lineHeight * 10).rounded()),
            weightRaw: weight.rawValue,
            map: map
        )
        if let cached = heightCache[key] { return cached }

        let selectedFont = font(size, weight: weight, map: map)
        let result: CGFloat
        if !text.contains("\n"), !text.contains("\r"),
           (text as NSString).size(withAttributes: [.font: selectedFont]).width <= clampedWidth {
            result = lineHeight
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.lineBreakMode = .byWordWrapping
            sharedTextContainer.containerSize = NSSize(width: clampedWidth, height: .greatestFiniteMagnitude)
            sharedStorage.setAttributedString(NSAttributedString(
                string: text,
                attributes: [.font: selectedFont, .paragraphStyle: paragraph]
            ))
            sharedLayoutManager.ensureLayout(for: sharedTextContainer)
            var lines = 0
            let glyphRange = sharedLayoutManager.glyphRange(for: sharedTextContainer)
            sharedLayoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in lines += 1 }
            if sharedLayoutManager.extraLineFragmentTextContainer === sharedTextContainer { lines += 1 }
            result = CGFloat(max(1, lines)) * lineHeight
        }
        if heightCache.count >= 1024 { heightCache.removeAll(keepingCapacity: true) }
        heightCache[key] = result
        return result
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
