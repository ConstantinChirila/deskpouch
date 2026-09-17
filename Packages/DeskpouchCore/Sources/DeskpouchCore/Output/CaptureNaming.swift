import Foundation

/// Filenames for captured files: `Screenshot yyyy-MM-dd HH.mm.ss.png` (01-screenshot.md), `Recording
/// yyyy-MM-dd HH.mm.ss.mp4`, and text results saved by `SystemOutputEffects`. One stamp format and one
/// unique-suffix rule for every capture tool, instead of each package keeping its own copy.
public enum CaptureNaming {
    /// "`prefix` yyyy-MM-dd HH.mm.ss.`ext`", e.g. `Screenshot 2026-09-16 14.05.02.png`. `timeZone` defaults to
    /// the system's; tests inject a fixed one so the exact string is assertable regardless of where they run.
    public static func stamped(prefix: String, extension ext: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "\(prefix) \(formatter(timeZone: timeZone).string(from: date)).\(ext)"
    }

    /// `url` if nothing there yet, otherwise `name 2.ext`, `name 3.ext`, ... up to the first free name.
    public static func unique(_ url: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        var candidate = folder.appending(path: "\(base) \(n)").appendingPathExtension(ext)
        while fileManager.fileExists(atPath: candidate.path) {
            n += 1
            candidate = folder.appending(path: "\(base) \(n)").appendingPathExtension(ext)
        }
        return candidate
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        f.timeZone = timeZone
        return f
    }
}
