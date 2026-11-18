import Foundation

// C# порт: src/DeskBot.Core/Storage/JsonFileStore.cs

/// Atomic JSON хадгалалт. Эвдэрсэн файлыг `.corrupt-<timestamp>` болгож нөөцлөөд default руу буцна.
public enum JSONFileStore {
    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)))
        }
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? Date(s, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(s, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO-8601 date: \(s)")
        }
        return d
    }

    public static func loadOrDefault<T: Decodable>(_ url: URL, fallback: () -> T) -> T {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return fallback() }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return fallback() }
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            // Эвдэрсэн → нөөцлөөд default (best effort)
            let stamp = Self.timestamp()
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
            return fallback()
        }
    }

    /// tmp файлд бичээд `replaceItemAt`-аар atomic солино.
    public static func saveAtomic<T: Encodable>(_ url: URL, _ value: T) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try makeEncoder().encode(value)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tmp)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: Date())
    }
}
