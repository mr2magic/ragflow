# CLAUDE_AI_ML.md — AI & Machine Learning

## Apple Intelligence & FoundationModels (iOS 26)

iOS 26 ships **FoundationModels** — an on-device LLM API backed by Apple Intelligence.

```swift
import FoundationModels

// Basic on-device inference
actor IntelligenceService {

    // Text generation
    func generateSummary(for text: String) async throws -> String {
        let session = LanguageModelSession()
        let prompt = "Summarize the following in 2 sentences:\n\n\(text)"
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // Structured output with @Generable (iOS 26)
    @Generable
    struct ExtractedEntities {
        @Guide("Names of people mentioned")
        var people: [String]
        @Guide("Places mentioned")
        var locations: [String]
        @Guide("Dates mentioned in ISO 8601 format")
        var dates: [String]
    }

    func extractEntities(from text: String) async throws -> ExtractedEntities {
        let session = LanguageModelSession()
        return try await session.respond(
            to: "Extract entities from: \(text)",
            generating: ExtractedEntities.self
        )
    }

    // Streaming response for UI
    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let session = LanguageModelSession()
                let stream = session.streamResponse(to: prompt)
                for try await chunk in stream {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
}
```

### Writing Tools Integration

```swift
// Make text fields participate in Writing Tools (iOS 18+, enhanced in iOS 26)
TextField("Notes", text: $text, axis: .vertical)
    .writingToolsBehavior(.complete)   // full Writing Tools panel

// Disable for code / structured input
TextField("API Key", text: $apiKey)
    .writingToolsBehavior(.limited)    // no rewrites, only lookup
```

---

## Core ML — Custom Models

### Loading & Running a Model

```swift
actor MLService {
    private var model: VNCoreMLModel?

    func loadModel(named name: String) async throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw MLError.modelNotFound(name)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all   // ANE + GPU + CPU
        let mlModel = try await MLModel.load(contentsOf: url, configuration: config)
        self.model = try VNCoreMLModel(for: mlModel)
    }

    func classify(image: CIImage) async throws -> [VNClassificationObservation] {
        guard let model else { throw MLError.modelNotLoaded }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error { continuation.resume(throwing: error); return }
                let results = request.results as? [VNClassificationObservation] ?? []
                continuation.resume(returning: results)
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(ciImage: image)
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}
```

### On-Device Model Compilation

```swift
// Compile .mlpackage at runtime (for downloaded models)
func compileModel(at sourceURL: URL) async throws -> URL {
    let compiledURL = try await MLModel.compileModel(at: sourceURL)
    // Move to Application Support for persistence
    let destination = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(compiledURL.lastPathComponent)
    _ = try FileManager.default.replaceItemAt(destination, withItemAt: compiledURL)
    return destination
}
```

---

## Vision Framework

```swift
actor VisionService {

    // Face detection + landmarks
    func detectFaces(in image: CIImage) async throws -> [VNFaceObservation] {
        try await performRequest(VNDetectFaceLandmarksRequest(), on: image)
    }

    // Text recognition (Live Text style)
    func recognizeText(in image: CIImage, languages: [String] = ["en-US"]) async throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        return try await performRequest(request, on: image)
    }

    // Object detection with bounding boxes
    func detectObjects(in image: CIImage) async throws -> [VNRecognizedObjectObservation] {
        try await performRequest(VNRecognizeAnimalsRequest(), on: image)
    }

    // Body pose estimation
    func detectBodyPose(in image: CIImage) async throws -> VNHumanBodyPoseObservation? {
        let results: [VNHumanBodyPoseObservation] = try await performRequest(
            VNDetectHumanBodyPoseRequest(), on: image
        )
        return results.first
    }

    // Hand pose — for gesture recognition
    func detectHandPose(in pixelBuffer: CVPixelBuffer) async throws -> [VNHumanHandPoseObservation] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    // Saliency — find visually important regions
    func attentionSaliency(in image: CIImage) async throws -> VNSaliencyImageObservation? {
        let results: [VNSaliencyImageObservation] = try await performRequest(
            VNGenerateAttentionBasedSaliencyImageRequest(), on: image
        )
        return results.first
    }

    // Generic helper
    private func performRequest<T: VNObservation>(_ request: VNRequest, on image: CIImage) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
                continuation.resume(returning: (request.results as? [T]) ?? [])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

---

## Natural Language Framework

```swift
import NaturalLanguage

struct NLService {
    // Sentiment analysis
    func sentiment(of text: String) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return tag.flatMap { Double($0.rawValue) }
    }

    // Language detection
    func detectLanguage(of text: String) -> NLLanguage? {
        NLLanguageRecognizer.dominantLanguage(for: text)
    }

    // Named entity recognition
    func entities(in text: String) -> [(String, NLTag)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var results: [(String, NLTag)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                results.append((String(text[range]), tag))
            }
            return true
        }
        return results
    }

    // Sentence embedding for semantic search
    func embedding(for text: String) -> [Double]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        return embedding.vector(for: text).map(Array.init)
    }

    func semanticallySimilar(_ a: String, _ b: String, threshold: Double = 0.8) -> Bool {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return false }
        return embedding.distance(between: a, and: b) < (1.0 - threshold)
    }
}
```

---

## Speech Recognition & Synthesis

```swift
import Speech
import AVFoundation

actor SpeechService {

    // Recognition
    func recognizeSpeech(from audioURL: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw PermissionError.speechRecognitionDenied
        }
        let recognizer = SFSpeechRecognizer(locale: Locale.current)!
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error { continuation.resume(throwing: error); return }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // Live microphone recognition stream
    func liveSpeechStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            let audioEngine = AVAudioEngine()
            let recognizer = SFSpeechRecognizer()!
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let node = audioEngine.inputNode
            node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            try? audioEngine.start()

            recognizer.recognitionTask(with: request) { result, _ in
                if let result {
                    continuation.yield(result.bestTranscription.formattedString)
                }
            }
            continuation.onTermination = { _ in audioEngine.stop() }
        }
    }

    // Synthesis (TTS)
    func speak(_ text: String, voice: AVSpeechSynthesisVoice? = nil) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        AVSpeechSynthesizer().speak(utterance)
    }
}
```

---

## Sound Analysis

```swift
import SoundAnalysis

actor SoundClassifier {
    func classifyAmbientSound() -> AsyncStream<SNClassificationResult> {
        AsyncStream { continuation in
            let analyzer = SNAudioStreamAnalyzer(format: AVAudioEngine().inputNode.outputFormat(forBus: 0))
            let request = try! SNClassifySoundRequest(classifierIdentifier: .version1)
            try! analyzer.add(request, withObserver: SoundObserver(continuation: continuation))
        }
    }
}
```

---

*See also: `CLAUDE_HARDWARE.md` for camera/sensor feeds into ML pipelines, `CLAUDE_CONCURRENCY.md` for actor isolation.*
