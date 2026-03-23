import Foundation
import Accelerate

struct EmbeddingService {
    let host: String
    let model: String

    init(host: String = "http://localhost:11434", model: String = "nomic-embed-text") {
        self.host = host
        self.model = model
    }

    // MARK: - Embed

    func embed(texts: [String]) async throws -> [[Float]] {
        let url = URL(string: "\(host)/api/embed")!
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": texts
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EmbeddingError.badResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["embeddings"] as? [[Double]] else {
            throw EmbeddingError.parseError
        }

        return raw.map { $0.map(Float.init) }
    }

    func embed(text: String) async throws -> [Float] {
        let results = try await embed(texts: [text])
        guard let first = results.first else { throw EmbeddingError.parseError }
        return first
    }

    // MARK: - Similarity

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - Serialization

    static func floatsToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func dataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    enum EmbeddingError: LocalizedError {
        case badResponse, parseError

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Embedding service returned an error."
            case .parseError: return "Could not parse embedding response."
            }
        }
    }
}
