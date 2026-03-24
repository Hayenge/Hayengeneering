import Vision
import CoreImage
import UIKit

// MARK: - Recognition Result

struct RecognitionResult {
    /// Best candidate card name extracted from OCR
    let cardName: String
    /// All text blocks found in the image
    let allText: [String]
    /// Confidence score 0.0–1.0
    let confidence: Float
    /// Detected game (if identifiable from text patterns)
    let detectedGame: TCGGame?
}

// MARK: - Card Recognition Service

final class CardRecognitionService {

    // Minimum confidence for a recognition result to be acted upon
    private let minimumConfidence: Float = 0.6

    // MARK: - Public API

    /// Recognise card name from a pixel buffer (live camera frame)
    func recognise(pixelBuffer: CVPixelBuffer) async throws -> RecognitionResult? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        return try await performRecognition(with: handler)
    }

    /// Recognise card name from a UIImage (photo / gallery pick)
    func recognise(image: UIImage) async throws -> RecognitionResult? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return try await performRecognition(with: handler)
    }

    // MARK: - Internal Recognition

    private func performRecognition(with handler: VNImageRequestHandler) async throws -> RecognitionResult? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let result = self.processObservations(observations)
                continuation.resume(returning: result)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.02   // skip very small text (card text body)

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Text Processing

    private func processObservations(_ observations: [VNRecognizedTextObservation]) -> RecognitionResult? {
        guard !observations.isEmpty else { return nil }

        // Sort observations by vertical position (top = low Y in normalized coords, Vision uses bottom-left origin)
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        // Collect all recognized strings with their bounding boxes
        var textBlocks: [(text: String, box: CGRect, confidence: Float)] = []
        for observation in sorted {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            textBlocks.append((text, observation.boundingBox, candidate.confidence))
        }

        guard !textBlocks.isEmpty else { return nil }

        let allText = textBlocks.map { $0.text }

        // Extract the card name (first prominent text block in the top 25% of the card)
        let topBlocks = textBlocks.filter { $0.box.origin.y > 0.75 }
        let candidateBlocks = topBlocks.isEmpty ? Array(textBlocks.prefix(3)) : topBlocks

        // Find the best candidate: largest bounding box width (headline text)
        guard let bestBlock = candidateBlocks.max(by: { $0.box.width < $1.box.width }) else {
            return nil
        }

        let cardName = cleanCardName(bestBlock.text)
        guard !cardName.isEmpty, cardName.count >= 2 else { return nil }
        guard bestBlock.confidence >= minimumConfidence else { return nil }

        let detectedGame = detectGame(from: allText)

        return RecognitionResult(
            cardName: cardName,
            allText: allText,
            confidence: bestBlock.confidence,
            detectedGame: detectedGame
        )
    }

    // MARK: - Card Name Cleaning

    private func cleanCardName(_ raw: String) -> String {
        var name = raw

        // Remove common OCR artifacts
        name = name.replacingOccurrences(of: "|", with: "I")

        // Remove non-printable characters
        name = name.filter { $0.isLetter || $0.isNumber || $0.isWhitespace || "-',./!?:".contains($0) }

        // Trim and normalize whitespace
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Remove purely numeric strings (likely card numbers, not names)
        if name.allSatisfy({ $0.isNumber || $0 == "/" }) { return "" }

        return name
    }

    // MARK: - Game Detection

    private func detectGame(from textBlocks: [String]) -> TCGGame? {
        let combined = textBlocks.joined(separator: " ").lowercased()

        // Pokemon indicators
        if combined.contains("hp") && (combined.contains("pokémon") || combined.contains("pokemon") ||
           combined.contains("trainer") || combined.contains("energy")) {
            return .pokemon
        }

        // Yu-Gi-Oh indicators
        if combined.contains("atk/") || combined.contains("def/") ||
           combined.contains("effect monster") || combined.contains("spell card") ||
           combined.contains("trap card") {
            return .yugioh
        }

        // Magic: The Gathering indicators
        if combined.contains("instant") || combined.contains("sorcery") ||
           combined.contains("enchantment") || combined.contains("artifact") ||
           combined.contains("legendary creature") || combined.contains("planeswalker") {
            return .magicTheGathering
        }

        // One Piece indicators
        if combined.contains("don!!") || combined.contains("don card") {
            return .onePiece
        }

        // Lorcana indicators
        if combined.contains("lorcana") || combined.contains("inkwell") {
            return .lorcana
        }

        // Star Wars Unlimited
        if combined.contains("base set") && (combined.contains("rebel") || combined.contains("empire")) {
            return .starWarsUnlimited
        }

        return nil
    }
}
