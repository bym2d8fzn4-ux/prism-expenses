import Foundation
import ImageIO
import UIKit
import Vision

struct ReceiptScanResult {
    var merchant: String?
    var amount: Double?
    var date: Date?
    var category: String?
}

enum ReceiptScanner {
    static func scan(image: UIImage) async throws -> ReceiptScanResult {
        guard let cgImage = image.cgImage else {
            return ReceiptScanResult()
        }

        let observations = try await recognizeText(in: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        let lines = observations
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let receiptLines = lines.enumerated().map { ReceiptLine(index: $0.offset, raw: $0.element) }
        let merchant = findMerchant(in: receiptLines)
        let amount = findAmount(in: receiptLines)
        let date = findDate(in: receiptLines)
        let category = mapCategory(from: [merchant ?? ""] + lines)

        return ReceiptScanResult(merchant: merchant, amount: amount, date: date, category: category)
    }

    private static func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: request.results as? [VNRecognizedTextObservation] ?? [])
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func findMerchant(in lines: [ReceiptLine]) -> String? {
        let candidates = lines
            .prefix(12)
            .compactMap { line -> (merchant: String, score: Int)? in
                guard line.raw.rangeOfCharacter(from: .letters) != nil else {
                    return nil
                }

                guard findAmount(in: [line]) == nil, findDate(in: [line]) == nil else {
                    return nil
                }

                let lower = line.normalizedLower
                guard merchantBlocklist.allSatisfy({ !lower.contains($0) }) else {
                    return nil
                }

                var score = 150 - (line.index * 12)
                let letterCount = line.raw.filter(\.isLetter).count
                let digitCount = line.raw.filter(\.isNumber).count
                if letterCount >= 4 { score += 20 }
                if line.raw == line.raw.uppercased(), letterCount >= 4 { score += 10 }
                if digitCount > 0 { score -= digitCount * 12 }
                if lower.contains(".com") || lower.contains("www") || lower.contains("@") { score -= 80 }
                if lower.contains("street") || lower.contains(" st ") || lower.contains(" ave") || lower.contains("road") { score -= 60 }

                let merchant = cleanMerchant(line.raw)
                guard merchant.count >= 3 else {
                    return nil
                }

                return (merchant, score)
            }

        return candidates.max { $0.score < $1.score }?.merchant
    }

    private static func findAmount(in lines: [ReceiptLine]) -> Double? {
        let amountPattern = #"(?<![\d/])(?:[$S])?\s*(\d{1,4}(?:,\d{3})*|\d+)[\.,](\d{2})(?!\d)"#
        let regex = try? NSRegularExpression(pattern: amountPattern)
        var candidates: [(value: Double, score: Double)] = []
        let tipAdjustmentIndex = lines.last { lineLooksLikeTipAdjustment($0.normalizedLower) }?.index

        for line in lines {
            let lower = line.normalizedLower
            let nsRange = NSRange(line.raw.startIndex..<line.raw.endIndex, in: line.raw)
            let matches = regex?.matches(in: line.raw, range: nsRange) ?? []

            for match in matches {
                guard let range = Range(match.range, in: line.raw) else {
                    continue
                }

                let cleaned = line.raw[range]
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "S", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ",", with: "")

                guard let value = Double(cleaned), value > 0, value < 100_000 else {
                    continue
                }

                var score = log10(value + 1) * 15
                score += Double(line.index) * 2.5

                if strongTotalKeywords.contains(where: lower.contains) {
                    score += 600
                } else if lower.contains("total") {
                    score += 350
                }

                if amountKeywords.contains(where: lower.contains) {
                    score += 150
                }

                if amountRejectKeywords.contains(where: lower.contains) {
                    score -= 450
                }

                if let tipAdjustmentIndex, line.index > tipAdjustmentIndex {
                    score += 700 + Double(line.index - tipAdjustmentIndex) * 10

                    if lower.contains("total") || lower.contains("balance") || lower.contains("amount") {
                        score += 200
                    }
                } else if lineLooksLikeTipAdjustment(lower),
                          !lower.contains("total"),
                          !lower.contains("balance"),
                          !lower.contains("amount") {
                    score -= 300
                }

                if line.raw.contains("$") {
                    score += 35
                }

                if lower.contains("cash") || lower.contains("tender") || lower.contains("change") {
                    score -= 250
                }

                if lineContainsLikelyDateOrTime(line.raw) {
                    score -= 80
                }

                candidates.append((value, score))
            }
        }

        return candidates.max { $0.score < $1.score }?.value
    }

    private static func lineLooksLikeTipAdjustment(_ line: String) -> Bool {
        containsAny(tipAdjustmentKeywords, in: line)
    }

    private static func findDate(in lines: [ReceiptLine]) -> Date? {
        let patterns = [
            #"\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b"#,
            #"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#,
            #"\b(\d{4})[/-](\d{1,2})[/-](\d{1,2})\b"#,
            #"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}\b"#,
            #"\b\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{2,4}\b"#
        ]
        var candidates: [(date: Date, score: Int)] = []

        for line in lines {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }

                let nsRange = NSRange(line.raw.startIndex..<line.raw.endIndex, in: line.raw)
                let matches = regex.matches(in: line.raw, range: nsRange)

                for match in matches {
                    guard let fullRange = Range(match.range, in: line.raw) else {
                        continue
                    }

                    let value = String(line.raw[fullRange])
                    guard let date = parseDate(value), isPlausibleReceiptDate(date) else {
                        continue
                    }

                    var score = 100 - line.index
                    let lower = line.normalizedLower
                    if lower.contains("date") { score += 80 }
                    if lower.contains("purchase") || lower.contains("transaction") || lower.contains("ordered") { score += 40 }
                    if lower.contains("expires") || lower.contains("member") || lower.contains("card") { score -= 80 }
                    candidates.append((date, score))
                }
            }
        }

        return candidates.max { $0.score < $1.score }?.date
    }

    private static func parseDate(_ value: String) -> Date? {
        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formatters = [
            "M/d/yy",
            "M/d/yyyy",
            "M-d-yy",
            "M-d-yyyy",
            "yyyy-M-d",
            "MMM d yy",
            "MMM d yyyy",
            "MMMM d yy",
            "MMMM d yyyy",
            "d MMM yy",
            "d MMM yyyy",
            "d MMMM yy",
            "d MMMM yyyy"
        ].map { pattern in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            formatter.isLenient = true
            return formatter
        }

        return formatters.compactMap { $0.date(from: normalized) }.first
    }

    private static func mapCategory(from lines: [String]) -> String {
        let text = lines.joined(separator: " ").lowercased()

        if containsAny(lodgingKeywords, in: text) {
            return ExpenseCategory.lodging.rawValue
        }

        if containsAny(mealKeywords, in: text) {
            return ExpenseCategory.meal.rawValue
        }

        if containsAny(flightKeywords, in: text) {
            return ExpenseCategory.flight.rawValue
        }

        if containsAny(transportKeywords, in: text) {
            return ExpenseCategory.transport.rawValue
        }

        if containsAny(suppliesKeywords, in: text) {
            return ExpenseCategory.supplies.rawValue
        }

        return ExpenseCategory.miscellaneous.rawValue
    }

    private static func cleanMerchant(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\W+|\W+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlausibleReceiptDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        guard let oldest = calendar.date(byAdding: .year, value: -8, to: .now),
              let newest = calendar.date(byAdding: .day, value: 2, to: .now) else {
            return true
        }

        return date >= oldest && date <= newest
    }

    private static func lineContainsLikelyDateOrTime(_ line: String) -> Bool {
        let patterns = [
            #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#,
            #"\b\d{1,2}:\d{2}\s*(?:am|pm)?\b"#
        ]

        return patterns.contains { pattern in
            line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static let strongTotalKeywords = [
        "grand total",
        "total due",
        "amount due",
        "balance due",
        "total sale",
        "total paid",
        "sale amount",
        "purchase total",
        "transaction total"
    ]

    private static let amountKeywords = [
        "amount",
        "balance",
        "paid",
        "charge",
        "sale"
    ]

    private static let amountRejectKeywords = [
        "subtotal",
        "sub total",
        "tax",
        "tip",
        "gratuity",
        "change",
        "cash back",
        "cashback",
        "tendered",
        "discount",
        "coupon",
        "savings",
        "points",
        "reward",
        "visa",
        "mastercard",
        "amex",
        "discover",
        "card",
        "auth",
        "approval"
    ]

    private static let tipAdjustmentKeywords = [
        "tip",
        "gratuity",
        "additional gratuity",
        "additional tip"
    ]

    private static let merchantBlocklist = [
        "receipt",
        "invoice",
        "order",
        "cashier",
        "server",
        "terminal",
        "register",
        "transaction",
        "approval",
        "auth",
        "visa",
        "mastercard",
        "amex",
        "discover",
        "subtotal",
        "total",
        "tax",
        "tip",
        "change",
        "balance",
        "amount",
        "date",
        "time",
        "phone",
        "tel",
        "www",
        ".com",
        "thank you"
    ]

    private static let lodgingKeywords = [
        "hotel",
        "motel",
        "lodging",
        "marriott",
        "courtyard",
        "hilton",
        "hyatt",
        "hampton",
        "holiday inn",
        "suites",
        "resort",
        "airbnb",
        "vrbo",
        "inn "
    ]

    private static let mealKeywords = [
        "meal",
        "restaurant",
        "cafe",
        "coffee",
        "breakfast",
        "lunch",
        "dinner",
        "grill",
        "bar ",
        "diner",
        "pizza",
        "burger",
        "starbucks",
        "dunkin",
        "mcdonald",
        "chipotle",
        "subway",
        "panera",
        "taco",
        "kitchen"
    ]

    private static let flightKeywords = [
        "airline",
        "flight",
        "delta",
        "southwest",
        "united airlines",
        "american airlines",
        "jetblue",
        "alaska air",
        "frontier",
        "spirit airlines",
        "boarding"
    ]

    private static let transportKeywords = [
        "uber",
        "lyft",
        "taxi",
        "cab",
        "parking",
        "rental car",
        "rent a car",
        "hertz",
        "avis",
        "enterprise",
        "budget",
        "national",
        "fuel",
        "gas",
        "shell",
        "chevron",
        "exxon",
        "mobil",
        "bp ",
        "toll"
    ]

    private static let suppliesKeywords = [
        "supplies",
        "office",
        "fedex",
        "ups",
        "staples",
        "office depot",
        "office max",
        "shipping",
        "postage",
        "usps"
    ]
}

private struct ReceiptLine {
    let index: Int
    let raw: String

    var normalizedLower: String {
        raw
            .lowercased()
            .replacingOccurrences(of: #"[\s\n\t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension CGImagePropertyOrientation {
    init(_ imageOrientation: UIImage.Orientation) {
        switch imageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
