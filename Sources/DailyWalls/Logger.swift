import Foundation
import os.log

/// Writes timestamped log lines to ~/.dailywalls/{yyyy-MM-dd}.log
final class Logger {
    static let shared = Logger()

    private let fileManager = FileManager.default
    private let logDir: URL

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        logDir = home.appendingPathComponent(".dailywalls")
    }

    func log(_ message: String) {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayString = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: now)

        let line = "[\(timeString)] \(message)\n"

        do {
            try fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
            let logFile = logDir.appendingPathComponent("\(dayString).log")
            if fileManager.fileExists(atPath: logFile.path) {
                let handle = try FileHandle(forWritingTo: logFile)
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try line.write(to: logFile, atomically: true, encoding: .utf8)
            }
        } catch {
            // Fallback: write to os_log so we don't lose the message silently
            os_log("DailyWalls: %{public}@ (log write failed: %{public}@)",
                   message, error.localizedDescription)
        }

        // Also echo to stdout for debugging during development
        print(line, terminator: "")
    }
}
