// NudeFndr - nudefndr.com
// Transparency Repository - On-device document & ID detection (v2.5.6)

import Foundation
import Vision
import UIKit
import ImageIO

/// On-device detection of photos that expose documents, payment cards, or
/// credentials — the "sensitive" most people forget they have in their library.
/// Runs entirely locally via Apple's Vision framework. NO network activity.
///
/// Detection is deliberately conservative: every signal needs a structural
/// check (card Luhn checksum, IBAN mod-97, passport MRZ shape) or an explicit
/// credential phrase, so ordinary receipts, menus, and screenshots don't flood
/// results. This feature is OFF by default and opt-in in Settings.
final class DocumentDetectionService {

    enum Finding: String, CaseIterable {
        case paymentCard = "PAYMENT_CARD"
        case iban = "IBAN"
        case passportMRZ = "PASSPORT_MRZ"
        case ssn = "SSN"
        case credential = "CREDENTIAL"
        case governmentID = "GOVERNMENT_ID"
    }

    struct DetectionResult {
        let findings: Set<Finding>
        var isSensitiveDocument: Bool { !findings.isEmpty }
    }

    /// Text recognition doesn't need full-res; this keeps the per-photo cost
    /// bounded on large libraries.
    private static let maxAnalysisPixels: CGFloat = 1600

    // MARK: - Public

    func analyze(cgImage: CGImage) async -> DetectionResult {
        let lines = await recognizeText(in: cgImage)
        guard !lines.isEmpty else { return DetectionResult(findings: []) }

        var findings = Set<Finding>()
        let joined = lines.joined(separator: "\n")
        let joinedLower = joined.lowercased()

        if Self.containsPaymentCardNumber(joined) { findings.insert(.paymentCard) }
        if Self.containsIBAN(joined) { findings.insert(.iban) }
        if Self.containsMRZ(lines: lines) { findings.insert(.passportMRZ) }
        if Self.containsSSN(joined) { findings.insert(.ssn) }
        if Self.containsCredentialPhrase(joinedLower) { findings.insert(.credential) }

        // Document-shaped photo + identity keywords → likely a photographed ID.
        // The segmentation check alone would flag every receipt, so it only ever
        // acts as a booster for explicit identity terms.
        if findings.isEmpty, Self.containsIdentityKeywords(joinedLower) {
            if await looksLikeDocument(cgImage: cgImage) {
                findings.insert(.governmentID)
            }
        }

        return DetectionResult(findings: findings)
    }

    // MARK: - Vision (on-device, no network)

    private func recognizeText(in cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false // MRZ and card numbers aren't words.

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func looksLikeDocument(cgImage: CGImage) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = VNDetectDocumentSegmentationRequest { request, _ in
                let confident = (request.results as? [VNRectangleObservation])?
                    .contains { $0.confidence > 0.8 } ?? false
                continuation.resume(returning: confident)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) } catch { continuation.resume(returning: false) }
        }
    }

    // MARK: - Structural checks

    /// 13–19 digit runs (allowing spaces/hyphens) that pass Luhn.
    static func containsPaymentCardNumber(_ text: String) -> Bool {
        let pattern = #"(?<!\d)(?:\d[ \-]?){12,18}\d(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].compactMap { $0.wholeNumberValue }
            guard (13...19).contains(digits.count) else { continue }
            guard Set(digits).count > 1 else { continue } // all-same-digit noise
            if luhnValid(digits) { return true }
        }
        return false
    }

    static func luhnValid(_ digits: [Int]) -> Bool {
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// IBAN with a valid mod-97 checksum.
    static func containsIBAN(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let pattern = #"[A-Z]{2}\d{2}[A-Z0-9]{11,30}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(compact.startIndex..., in: compact)
        for match in regex.matches(in: compact, range: range) {
            guard let r = Range(match.range, in: compact) else { continue }
            if ibanChecksumValid(String(compact[r])) { return true }
        }
        return false
    }

    static func ibanChecksumValid(_ iban: String) -> Bool {
        guard iban.count >= 15, iban.count <= 34 else { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            let value: String
            if let digit = character.wholeNumberValue, character.isNumber {
                value = String(digit)
            } else if let ascii = character.asciiValue, character.isLetter {
                value = String(Int(ascii) - 55) // A=10 … Z=35
            } else {
                return false
            }
            for digitChar in value {
                remainder = (remainder * 10 + digitChar.wholeNumberValue!) % 97
            }
        }
        return remainder == 1
    }

    /// Passport/ID machine-readable zone: long lines from [A-Z0-9<] with the
    /// telltale chevron filler.
    static func containsMRZ(lines: [String]) -> Bool {
        let mrzCharset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
        var mrzLineCount = 0
        for rawLine in lines {
            let line = rawLine.replacingOccurrences(of: " ", with: "")
            guard line.count >= 28, line.count <= 46 else { continue }
            guard line.unicodeScalars.allSatisfy({ mrzCharset.contains($0) }) else { continue }
            let chevronCount = line.filter { $0 == "<" }.count
            if chevronCount >= 3 {
                mrzLineCount += 1
                if chevronCount >= 6 { return true }
            }
        }
        return mrzLineCount >= 2
    }

    static func containsSSN(_ text: String) -> Bool {
        let pattern = #"(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Explicit credential phrases (multi-language). Deliberately phrase-level,
    /// not the bare word "code", so discount-code screenshots don't count.
    private static let credentialPhrases: [String] = [
        "verification code", "one-time password", "one time password",
        "recovery code", "recovery key", "backup code", "seed phrase",
        "recovery phrase", "private key", "your password is",
        "temporary password", "2fa code", "security code is"
    ]

    static func containsCredentialPhrase(_ lowercasedText: String) -> Bool {
        credentialPhrases.contains { lowercasedText.contains($0) }
    }

    private static let identityKeywords: [String] = [
        "passport", "driving licence", "driver license", "driver's license",
        "identity card", "national id", "date of birth", "nationality",
        "place of birth"
    ]

    static func containsIdentityKeywords(_ lowercasedText: String) -> Bool {
        identityKeywords.contains { lowercasedText.contains($0.lowercased()) }
    }
}
