import Foundation

/// Developer diagnostics, off by default. While enabled (until the user turns it off; the panel
/// shows a "Diagnostics" badge) each CareLink request is appended as a JSON line to ~/Library/Logs/CareLink Menubar ("CareLink Menubar Dev" for the development
/// variant) with private permissions.
/// Responses include health data and identity; tokens, codes and auth values are always redacted.
/// Files older than 7 days are purged. Nothing here is ever written inside the repository.
enum Diagnostics {
    static let retention: TimeInterval = 7 * 24 * 3600
    static let defaultsKey = "diagnosticsEnabled"
    /// Pre-2026-11-08 builds stored an expiry date; read once to migrate.
    private static let legacyKey = "diagnosticsUntil"
    static let redacted = "[redacted]"
    private static let queue = DispatchQueue(label: "local.tcx.carelink.menu.diagnostics")
    /// Compared after lowercasing and removing "_"/"-"; any key containing "token", "secret"
    /// or "password" is redacted too (covers refreshToken, access_token, clientSecret...).
    private static let sensitiveKeys: Set<String> = ["authorization", "code", "codeverifier", "assertion", "cookie", "setcookie"]
    static func isSensitive(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        return sensitiveKeys.contains(normalized)
            || ["token", "secret", "password"].contains { normalized.contains($0) }
    }
    private static var lastPurge: Date?

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(AppVariant.current.logsFolder)", isDirectory: true)
    }
    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            if let until = defaults.object(forKey: legacyKey) as? Date {
                defaults.removeObject(forKey: legacyKey)
                defaults.set(until > Date(), forKey: defaultsKey)
            }
            return defaults.bool(forKey: defaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Recursively replaces sensitive values. JWT-like strings are redacted under any key.
    static func redact(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in dict {
                out[key] = isSensitive(key) ? redacted : redact(item)
            }
            return out
        }
        if let array = value as? [Any] { return array.map(redact) }
        if let text = value as? String, looksLikeJWT(text) { return redacted }
        return value
    }
    private static func looksLikeJWT(_ text: String) -> Bool {
        text.hasPrefix("eyJ") && text.split(separator: ".").count == 3
    }

    /// Field paths and JSON types only; never values. Arrays merge their elements' shapes.
    static func shape(_ value: Any) -> [String] {
        var lines = Set<String>()
        walk(value, path: "", into: &lines)
        return lines.sorted()
    }
    private static func walk(_ value: Any, path: String, into lines: inout Set<String>) {
        if let dict = value as? [String: Any] {
            if !path.isEmpty { lines.insert("\(path): object") }
            for (key, item) in dict { walk(item, path: path.isEmpty ? key : "\(path).\(key)", into: &lines) }
        } else if let array = value as? [Any] {
            lines.insert("\(path): array")
            for item in array { walk(item, path: "\(path)[]", into: &lines) }
        } else {
            lines.insert("\(path): \(typeName(value))")
        }
    }
    private static func typeName(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
        }
        if value is String { return "string" }
        return "unknown"
    }

    static func record(method: String, url: URL, status: Int?, request: Any?, response: Any?, now: Date = Date()) {
        guard isEnabled else { return }
        // Keep the 7-day retention even when the app runs for weeks without relaunching.
        if lastPurge.map({ now.timeIntervalSince($0) > 24 * 3600 }) ?? true { lastPurge = now; purge(now: now) }
        var entry: [String: Any] = ["time": ISO8601DateFormatter().string(from: now), "method": method,
                                    "url": url.absoluteString, "status": status ?? NSNull()]
        entry["request"] = request.map(redact) ?? NSNull()
        entry["response"] = response.map(redact) ?? NSNull()
        guard JSONSerialization.isValidJSONObject(entry),
              var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let day = String(ISO8601DateFormatter().string(from: now).prefix(10))
        queue.async { append(line, to: directory.appendingPathComponent("carelink-\(day).jsonl")) }
    }
    private static func append(_ data: Data, to file: URL) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            if !manager.fileExists(atPath: file.path) {
                manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never affect the app; failures are dropped silently.
        }
    }

    static func enable(now: Date = Date()) {
        isEnabled = true
        purge(now: now)
    }
    static func disable() { isEnabled = false }

    /// Deletes log files older than the retention period.
    static func purge(now: Date = Date()) {
        queue.async {
            let manager = FileManager.default
            guard let files = try? manager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, now.timeIntervalSince(modified) > retention { try? manager.removeItem(at: file) }
            }
        }
    }
    /// Synchronous variant, used right before quitting.
    static func deleteAllNow() {
        queue.sync {
            let manager = FileManager.default
            guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            for file in files where file.pathExtension == "jsonl" { try? manager.removeItem(at: file) }
        }
    }
    static func deleteAll() {
        queue.async {
            let manager = FileManager.default
            guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            for file in files where file.pathExtension == "jsonl" { try? manager.removeItem(at: file) }
        }
    }
}
