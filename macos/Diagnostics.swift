import Foundation

/// Developer diagnostics, off by default. While enabled (until the user turns it off; the panel
/// shows a "Diagnostics" badge) each CareLink request is appended as a JSON line to ~/Library/Logs/CareLink Menubar ("CareLink Menubar Dev" for the development
/// variant) with private permissions.
/// Responses include health data and identity; tokens, codes and auth values are always redacted.
/// Files older than 7 days are purged, and the folder is capped at 50 MB: a day rolls over to numbered
/// 10 MB chunks and the oldest files go first. Nothing here is ever written inside the repository.
enum Diagnostics {
    static let retention: TimeInterval = 7 * 24 * 3600
    /// Size of one log file before the day continues in a new numbered chunk.
    static let fileLimit = 10 * 1024 * 1024
    /// Total size of the log folder; the oldest files are deleted above it.
    static let totalLimit = 50 * 1024 * 1024
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
    private static var legacyDirectory: URL? {
        AppVariant.current.legacyLogsFolder.map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\($0)", isDirectory: true)
        }
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
        queue.async { write(line, day: day, in: directory, fileLimit: fileLimit, totalLimit: totalLimit, now: now) }
    }

    /// Appends a line to the day's current chunk (`carelink-DAY.jsonl`, then `carelink-DAY-2.jsonl`...).
    /// Starting a new chunk also enforces the folder's size cap. Runs on the diagnostics queue
    /// (checks call it directly with small limits).
    static func write(_ data: Data, day: String, in folder: URL, fileLimit: Int, totalLimit: Int, now: Date) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            var index = 1
            var file: URL
            while true {
                file = folder.appendingPathComponent(index == 1 ? "carelink-\(day).jsonl" : "carelink-\(day)-\(index).jsonl")
                guard let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int else { break }
                if size == 0 || size + data.count <= fileLimit { break }
                index += 1
            }
            if !manager.fileExists(atPath: file.path) {
                manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
                prune(in: folder, now: now, totalLimit: totalLimit, keep: file)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never affect the app; failures are dropped silently.
        }
    }

    /// Deletes `.jsonl` logs older than the retention period, then the oldest ones while the folder
    /// is above `totalLimit`. `keep` (the file being written) is never deleted. Synchronous.
    static func prune(in folder: URL, now: Date, totalLimit: Int, keep: URL? = nil) {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) else { return }
        var logs: [(url: URL, modified: Date, size: Int)] = []
        for file in files where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: keys)
            let modified = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > retention, file.lastPathComponent != keep?.lastPathComponent {
                try? manager.removeItem(at: file)
            } else {
                logs.append((file, modified, values?.fileSize ?? 0))
            }
        }
        var total = logs.reduce(0) { $0 + $1.size }
        for log in logs.sorted(by: { ($0.modified, $0.url.lastPathComponent) < ($1.modified, $1.url.lastPathComponent) }) {
            guard total > totalLimit else { break }
            if log.url.lastPathComponent == keep?.lastPathComponent { continue }
            if (try? manager.removeItem(at: log.url)) != nil { total -= log.size }
        }
    }

    /// Deletes every `.jsonl` log in `folder`; other files are left alone.
    static func removeLogs(in folder: URL, removeFolderIfEmpty: Bool = false) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "jsonl" { try? manager.removeItem(at: file) }
        if removeFolderIfEmpty, (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? manager.removeItem(at: folder)
        }
    }

    static func enable(now: Date = Date()) {
        isEnabled = true
        purge(now: now)
    }
    static func disable() { isEnabled = false }

    /// Applies retention and the size cap, and deletes logs left in the pre-0.3.0 folder.
    static func purge(now: Date = Date()) {
        queue.async {
            prune(in: directory, now: now, totalLimit: totalLimit)
            if let legacyDirectory { removeLogs(in: legacyDirectory, removeFolderIfEmpty: true) }
        }
    }
    /// Synchronous variant, used right before quitting (consent withdrawal).
    static func deleteAllNow() {
        queue.sync { deleteEverything() }
    }
    static func deleteAll() {
        queue.async { deleteEverything() }
    }
    private static func deleteEverything() {
        removeLogs(in: directory)
        if let legacyDirectory { removeLogs(in: legacyDirectory, removeFolderIfEmpty: true) }
    }
}
