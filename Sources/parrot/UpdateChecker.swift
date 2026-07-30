import Foundation

/// A parsed "vX.Y.Z" tag, comparable numerically so "v0.0.10" correctly
/// sorts after "v0.0.9" (plain string comparison gets this wrong).
struct SemVer: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(tag: String) {
        let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = trimmed.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        major = parts[0]
        minor = parts[1]
        patch = parts[2]
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Polls GitHub for the latest release tag and reports whether it's newer
/// than the running build. Dev builds (parrotVersion == "dev") never check.
enum UpdateChecker {
    private static let releaseURL = URL(
        string: "https://api.github.com/repos/amtsh/parrot/releases/latest"
    )!

    /// Calls `completion` with the newer tag name if one exists, or nil if
    /// already current / the check failed / this is a dev build.
    static func checkForUpdate(completion: @escaping (String?) -> Void) {
        guard let current = SemVer(tag: parrotVersion) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard
                error == nil,
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String,
                let latest = SemVer(tag: tag),
                latest > current
            else {
                completion(nil)
                return
            }
            completion(tag)
        }.resume()
    }
}
