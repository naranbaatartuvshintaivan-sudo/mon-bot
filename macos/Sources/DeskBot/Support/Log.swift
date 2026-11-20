import Foundation
import os

/// os.Logger (Console.app) + ~/Library/Logs/DeskBot/deskbot.log. Хувийн өгөгдөл бичихгүй.
enum Log {
    private static let logger = Logger(subsystem: "dev.deskbot.DeskBot", category: "app")

    static let directory: URL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/DeskBot", isDirectory: true)

    static func info(_ message: String) { write("INFO", message); logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .public)") }

    private static func write(_ level: String, _ message: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("deskbot.log")
        let line = "\(Date().formatted(.iso8601)) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
