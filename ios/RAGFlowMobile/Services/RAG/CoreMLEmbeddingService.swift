import Foundation
import CoreML
import Accelerate

/// On-device text embedding using a bundled Core ML model.
///
/// ## Setup
/// 1. Convert MiniLM-L6-v2 (or similar) to .mlpackage with coremltools:
///    ```python
///    import coremltools as ct
///    model = ct.convert(hf_model, ...)
///    model.save("MiniLMEmbedder.mlpackage")
///    ```
/// 2. Drag `MiniLMEmbedder.mlpackage` into Xcode → RAGFlowMobile target.
/// 3. Check `isAvailable` before using; fall back to `EmbeddingService`
///    (Ollama) when false.
///
/// Expected model I/O:
/// - Input:  `input_ids`      (MLMultiArray, Int32, shape [1, seqLen])
/// - Input:  `attention_mask` (MLMultiArray, Int32, shape [1, seqLen])
/// - Output: `embeddings`     (MLMultiArray, Float32, shape [1, hiddenDim])
final class CoreMLEmbeddingService {
    static let shared = CoreMLEmbeddingService()

    private let model: MLModel?
    private let tokenizer = SimpleWordpieceTokenizer()

    /// `true` when the `.mlpackage` bundle is present and loaded.
    var isAvailable: Bool { model != nil }

    private init() {
        let url = Bundle.main.url(forResource: "MiniLMEmbedder", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "MiniLMEmbedder", withExtension: "mlpackage")
        model = url.flatMap { try? MLModel(contentsOf: $0) }
    }

    // MARK: - Embed

    /// Returns a normalised embedding vector, or throws if unavailable.
    func embed(text: String) throws -> [Float] {
        guard let model else { throw CoreMLEmbeddingError.modelUnavailable }
        let tokens = tokenizer.tokenize(text, maxLength: 128)
        let seqLen = tokens.inputIds.count

        let inputIds = try MLMultiArray(shape: [1, seqLen as NSNumber], dataType: .int32)
        let mask     = try MLMultiArray(shape: [1, seqLen as NSNumber], dataType: .int32)
        for (i, id) in tokens.inputIds.enumerated() {
            inputIds[i] = NSNumber(value: id)
            mask[i]     = NSNumber(value: tokens.attentionMask[i])
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: mask),
        ])
        let output = try model.prediction(from: input)
        guard let raw = output.featureValue(for: "embeddings")?.multiArrayValue else {
            throw CoreMLEmbeddingError.badOutput
        }

        var floats = (0..<raw.count).map { Float(truncating: raw[$0]) }
        // L2 normalise
        var norm: Float = 0
        vDSP_svesq(floats, 1, &norm, vDSP_Length(floats.count))
        norm = sqrt(norm)
        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(floats.count))
        }
        return floats
    }

    func embed(texts: [String]) throws -> [[Float]] {
        try texts.map { try embed(text: $0) }
    }

    // MARK: - Errors

    enum CoreMLEmbeddingError: LocalizedError {
        case modelUnavailable, badOutput
        var errorDescription: String? {
            switch self {
            case .modelUnavailable: return "MiniLMEmbedder.mlpackage not found in bundle."
            case .badOutput:        return "Core ML model returned unexpected output shape."
            }
        }
    }
}

// MARK: - Minimal WordPiece tokenizer (ASCII; replace with swift-transformers for production)

struct TokenizerOutput {
    let inputIds: [Int32]
    let attentionMask: [Int32]
}

final class SimpleWordpieceTokenizer {
    private let cls: Int32 = 101, sep: Int32 = 102, unk: Int32 = 100, pad: Int32 = 0

    func tokenize(_ text: String, maxLength: Int) -> TokenizerOutput {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var ids: [Int32] = [cls]
        for _ in words {
            ids.append(unk)         // replace with real vocab lookup
            if ids.count >= maxLength - 1 { break }
        }
        ids.append(sep)
        let mask = [Int32](repeating: 1, count: ids.count)
        let padCount = max(0, maxLength - ids.count)
        return TokenizerOutput(
            inputIds:      ids  + [Int32](repeating: pad, count: padCount),
            attentionMask: mask + [Int32](repeating: 0,   count: padCount)
        )
    }
}
