import Vision
import UIKit

/// Uses the Vision framework's on-device OCR to extract text from images or image-based PDFs.
/// Runs entirely on the Neural Engine — no network, no API key.
struct VisionOCRParser {

    // MARK: - Image OCR

    /// Extract all text from a UIImage (e.g. from the document scanner).
    func extractText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await recognize(cgImage: cgImage)
    }

    // MARK: - PDF fallback

    /// Extract text from every page of a PDF that returned no text from PDFKit.
    /// Returns page-separated text strings.
    func extractText(fromPDFAt url: URL) async -> [String] {
        guard let doc = CGPDFDocument(url as CFURL) else { return [] }
        let count = doc.numberOfPages
        var results: [String] = []

        for i in 1...max(1, count) {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.getBoxRect(.mediaBox)

            // Render the PDF page to a CGImage at 150 dpi
            let scale: CGFloat = 150.0 / 72.0
            let width  = Int(bounds.width  * scale)
            let height = Int(bounds.height * scale)
            guard width > 0, height > 0 else { continue }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(page)

            guard let cgImage = ctx.makeImage() else { continue }
            let pageText = await recognize(cgImage: cgImage)
            if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(pageText)
            }
        }
        return results
    }

    // MARK: - Core Vision call

    private func recognize(cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
