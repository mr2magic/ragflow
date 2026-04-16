import Foundation

/// Resolves Project Gutenberg book page URLs to direct download URLs.
///
/// Supported input forms:
///   https://www.gutenberg.org/ebooks/1342
///   https://gutenberg.org/ebooks/1342
///   http://www.gutenberg.org/ebooks/1342
///
/// Resolution strategy (in priority order):
///   1. EPUB (no images) via cache CDN  — smallest, best for reading
///   2. Plain text UTF-8 via cache CDN  — fallback if EPUB unavailable
///
/// Uses HEAD requests to confirm the file exists before returning the URL
/// so the caller never receives a 404.
enum GutenbergResolver {

    struct ResolvedBook {
        let downloadURL: URL
        let title: String       // best-effort from URL; real title comes after parse
        let gutenbergID: Int
    }

    enum GutenbergError: LocalizedError {
        case notAGutenbergURL
        case noDownloadFound(Int)

        var errorDescription: String? {
            switch self {
            case .notAGutenbergURL:
                return "URL is not a Project Gutenberg book page."
            case .noDownloadFound(let id):
                return "Could not find a downloadable file for Gutenberg book #\(id)."
            }
        }
    }

    // MARK: - Public

    /// Returns `nil` quickly if `url` is clearly not a Gutenberg book page,
    /// so callers can skip resolution for normal URLs.
    static func isGutenbergBookPage(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let isGutenberg = host.hasSuffix("gutenberg.org")
        let isBookPage  = url.pathComponents.count >= 3
                       && url.pathComponents[1] == "ebooks"
                       && Int(url.pathComponents[2]) != nil
        return isGutenberg && isBookPage
    }

    /// Resolves a Gutenberg book page URL to a direct EPUB or TXT download URL.
    /// Throws `GutenbergError.notAGutenbergURL` if the URL isn't a book page.
    static func resolve(_ url: URL) async throws -> ResolvedBook {
        guard isGutenbergBookPage(url),
              let idString = url.pathComponents.dropFirst(2).first,
              let id = Int(idString) else {
            throw GutenbergError.notAGutenbergURL
        }

        let candidates: [URL] = [
            URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).epub")!,
            URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id)-images.epub")!,
            URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).txt")!,
        ]

        for candidate in candidates {
            if await fileExists(candidate) {
                return ResolvedBook(
                    downloadURL: candidate,
                    title: "Gutenberg #\(id)",
                    gutenbergID: id
                )
            }
        }

        throw GutenbergError.noDownloadFound(id)
    }

    // MARK: - Private

    private static func fileExists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        return (try? await URLSession.shared.data(for: request))
            .map { _, response in (response as? HTTPURLResponse)?.statusCode == 200 }
            ?? false
    }
}
