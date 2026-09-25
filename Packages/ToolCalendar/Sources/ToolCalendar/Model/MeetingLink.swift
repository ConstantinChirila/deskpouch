import Foundation

/// Finds the link a calendar event joins through. Google puts its own Meet link in the description (EventKit's
/// `notes`) on a "Join with Google Meet:" line (plan 11 step 0); a description can also carry Meet links someone
/// pasted, so that line wins. Other call providers are not detected yet (planned before a public release): a
/// plain http(s) link in the event's URL or location field is taken as is, the description's other links are not
/// (they are usually docs and help pages).
public enum MeetingLink {
    static let meetHost = "meet.google.com"

    public static func find(url: String?, location: String?, notes: String?) -> URL? {
        let notes = notes.map(stripHTML)
        if let notes, let line = googleJoinLine(in: notes) { return line }
        for field in [notes, url, location] {
            if let field, let meet = links(in: field).first(where: isMeet) { return meet }
        }
        for field in [url, location] {
            if let field, let link = links(in: field).first { return link }
        }
        return nil
    }

    /// The link on Google's own "Join with Google Meet: <link>" line.
    static func googleJoinLine(in notes: String) -> URL? {
        for line in notes.split(whereSeparator: \.isNewline) where line.localizedCaseInsensitiveContains("join with google meet") {
            if let link = links(in: String(line)).first(where: isMeet) { return link }
        }
        return nil
    }

    static func isMeet(_ url: URL) -> Bool {
        url.host?.lowercased() == meetHost && url.path.count > 1
    }

    // Built once rather than per call, since every event's link is resolved on each fetch. Sendable in this SDK
    // (immutable and documented thread safe).
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let lineBreaks = try? NSRegularExpression(pattern: "<br\\s*/?>|</p>|</div>|</li>", options: .caseInsensitive)
    private static let anchors = try? NSRegularExpression(pattern: "<a\\s[^>]*href=\"([^\"]*)\"[^>]*>", options: .caseInsensitive)
    private static let tags = try? NSRegularExpression(pattern: "<[^>]+>")

    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    /// Every http(s) link in `text`, in order, with Google's `/url?q=` redirects unwrapped. A redirect whose
    /// target is not http(s) (`file:`, `smb:`, an app's scheme) is dropped: Join would otherwise open it.
    static func links(in text: String) -> [URL] {
        guard text.contains("://"), let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, isWeb(url) else { return nil }
            return unwrapRedirect(url)
        }
    }

    /// The target of a Google `/url?q=` redirect, the URL itself when it is not one, or nil when the target is
    /// not an http(s) link.
    static func unwrapRedirect(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host.hasPrefix("www.google.") || host.hasPrefix("google."),
              url.path == "/url",
              let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "q" })?.value,
              let inner = URL(string: target)
        else { return url }
        return isWeb(inner) ? inner : nil
    }

    /// Descriptions synced from Google can be HTML: turn `<br>` and block ends into new lines, drop the tags, and
    /// decode the few entities that sit in URLs.
    static func stripHTML(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var out = replace(lineBreaks, in: text, with: "\n")
        out = replace(anchors, in: out, with: " $1 ")
        out = replace(tags, in: out, with: "")
        for (entity, char) in [("&amp;", "&"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\"")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    private static func replace(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

extension URL {
    /// Meet opens in whichever Google account the browser has first; `authuser=<address>` picks the calendar's own.
    /// Left alone for other hosts, without an address, or when the link already names an account.
    func withAuthUser(_ email: String?) -> URL {
        guard let email, email.contains("@"), host?.lowercased() == MeetingLink.meetHost,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return self }
        var items = components.queryItems ?? []
        guard !items.contains(where: { $0.name == "authuser" }) else { return self }
        items.append(URLQueryItem(name: "authuser", value: email))
        components.queryItems = items
        return components.url ?? self
    }
}
