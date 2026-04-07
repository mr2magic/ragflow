import Foundation

struct OllamaModelsService {
    /// Direct session — bypasses iCloud Private Relay so local hostnames are reachable.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    static func fetchModels(host: String) async -> [String] {
        guard let url = URL(string: "\(host)/api/tags") else { return [] }
        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }
}
