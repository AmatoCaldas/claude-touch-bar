import Foundation

/// The Code chats you opened most recently, newest first, kept across
/// restarts. A chat counts as opened when you send it a message (the
/// UserPromptSubmit hook) or pick it on the Touch Bar.
enum RecentChats {
    /// How many chats the Touch Bar row shows.
    static let capacity = 6
    /// How many paths are remembered; older ones drop off.
    private static let stored = 30
    private static let key = "recentChats"

    /// Transcript paths, most recently opened first.
    static var paths: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    /// Moves `transcript` to the front of the list.
    static func touch(_ transcript: URL) {
        let path = transcript.standardizedFileURL.path
        let updated = [path] + paths.filter { $0 != path }
        UserDefaults.standard.set(Array(updated.prefix(stored)), forKey: key)
    }
}
