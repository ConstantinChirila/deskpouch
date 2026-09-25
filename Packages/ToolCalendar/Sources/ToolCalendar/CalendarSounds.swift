import AppKit

/// The alert sounds a pill can play: the ones macOS ships in /System/Library/Sounds plus any the user put in
/// ~/Library/Sounds, which is where `NSSound(named:)` looks too (System Settings lists the same set).
public enum CalendarSounds {
    static let extensions: Set<String> = ["aiff", "aif", "caf", "wav", "m4a", "mp3"]

    /// Sound names without extension: user sounds first, then the system ones, each sorted.
    public static func available() -> [String] {
        let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Sounds")
        let system = URL(fileURLWithPath: "/System/Library/Sounds")
        var seen = Set<String>()
        return [user, system].flatMap { names(in: $0) }.filter { seen.insert($0).inserted }
    }

    static func names(in folder: URL) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { extensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Plays `name`; one sound at a time, so scrolling through the picker does not stack them.
    @MainActor public static func play(_ name: String?) {
        current?.stop()
        guard let name, let sound = NSSound(named: name) else { current = nil; return }
        current = sound
        sound.play()
    }

    @MainActor private static var current: NSSound?
}
