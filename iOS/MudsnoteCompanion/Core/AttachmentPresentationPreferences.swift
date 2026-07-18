import Foundation

enum AttachmentPresentationMode: String, CaseIterable, Codable, Equatable {
    case small
    case large
    case plainLink
}

struct AttachmentPresentationPreferences {
    static let defaultsKey = "mudsnote.ios.attachmentPresentation"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func mode(notePath: String, attachmentPath: String) -> AttachmentPresentationMode {
        let values = storedValues
        if let rawValue = values[attachmentKey(notePath: notePath, attachmentPath: attachmentPath)],
           let mode = AttachmentPresentationMode(rawValue: rawValue) {
            return mode
        }
        if let rawValue = values[noteKey(notePath)],
           let mode = AttachmentPresentationMode(rawValue: rawValue) {
            return mode
        }
        return .large
    }

    func set(
        _ mode: AttachmentPresentationMode,
        notePath: String,
        attachmentPath: String
    ) {
        var values = storedValues
        values[attachmentKey(notePath: notePath, attachmentPath: attachmentPath)] = mode.rawValue
        store(values)
    }

    func setAll(_ mode: AttachmentPresentationMode, notePath: String) {
        var values = storedValues
        let prefix = attachmentPrefix(notePath)
        values.keys.filter { $0.hasPrefix(prefix) }.forEach { values.removeValue(forKey: $0) }
        values[noteKey(notePath)] = mode.rawValue
        store(values)
    }

    func moveNote(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        var values = storedValues
        let oldNoteKey = noteKey(oldPath)
        if let mode = values.removeValue(forKey: oldNoteKey) {
            values[noteKey(newPath)] = mode
        }

        let oldPrefix = attachmentPrefix(oldPath)
        let newPrefix = attachmentPrefix(newPath)
        for key in values.keys.filter({ $0.hasPrefix(oldPrefix) }) {
            guard let mode = values.removeValue(forKey: key) else { continue }
            values[newPrefix + key.dropFirst(oldPrefix.count)] = mode
        }
        store(values)
    }

    func moveFolder(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        var values = storedValues
        for key in Array(values.keys) {
            guard let replacement = migratedKey(
                key,
                fromFolder: oldPath,
                toFolder: newPath
            ),
            let mode = values.removeValue(forKey: key) else { continue }
            values[replacement] = mode
        }
        store(values)
    }

    func moveAttachment(
        notePath: String,
        from oldPath: String,
        to newPath: String
    ) {
        guard oldPath != newPath else { return }
        var values = storedValues
        let oldKey = attachmentKey(notePath: notePath, attachmentPath: oldPath)
        guard let mode = values.removeValue(forKey: oldKey) else { return }
        values[attachmentKey(notePath: notePath, attachmentPath: newPath)] = mode
        store(values)
    }

    func removeAttachment(notePath: String, attachmentPath: String) {
        var values = storedValues
        values.removeValue(
            forKey: attachmentKey(notePath: notePath, attachmentPath: attachmentPath)
        )
        store(values)
    }

    func removeNote(_ notePath: String) {
        var values = storedValues
        values.removeValue(forKey: noteKey(notePath))
        let prefix = attachmentPrefix(notePath)
        values.keys.filter { $0.hasPrefix(prefix) }.forEach { values.removeValue(forKey: $0) }
        store(values)
    }

    private var storedValues: [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    private func store(_ values: [String: String]) {
        if values.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(values, forKey: Self.defaultsKey)
        }
    }

    private func noteKey(_ notePath: String) -> String {
        "note|\(encoded(notePath))"
    }

    private func attachmentPrefix(_ notePath: String) -> String {
        "attachment|\(encoded(notePath))|"
    }

    private func attachmentKey(notePath: String, attachmentPath: String) -> String {
        attachmentPrefix(notePath) + encoded(attachmentPath)
    }

    private func encoded(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func migratedKey(
        _ key: String,
        fromFolder oldPath: String,
        toFolder newPath: String
    ) -> String? {
        var components = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2,
              let data = Data(base64Encoded: components[1]),
              let notePath = String(data: data, encoding: .utf8),
              notePath == oldPath || notePath.hasPrefix(oldPath + "/") else {
            return nil
        }
        let migratedPath = newPath + notePath.dropFirst(oldPath.count)
        components[1] = encoded(migratedPath)
        return components.joined(separator: "|")
    }
}
