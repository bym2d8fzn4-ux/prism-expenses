import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExportDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .commaSeparatedText, .pdf] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CSVReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct PDFReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum PDFReportRenderer {
    static func render(records: [ExpenseRecord], filterSummary: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 42
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let total = records.reduce(0) { $0 + $1.amount }

        return renderer.pdfData { context in
            var y = margin
            context.beginPage()

            y = drawHeader(
                y: y,
                margin: margin,
                width: page.width - margin * 2,
                recordCount: records.count,
                total: total,
                filterSummary: filterSummary
            )

            y += 18
            y = drawSummaryBlocks(records: records, y: y, margin: margin, pageWidth: page.width)
            y += 18

            drawText(
                "Entries",
                at: CGPoint(x: margin, y: y),
                attributes: titleAttributes(size: 18, color: .tripPDFInk)
            )
            y += 28

            for record in records {
                if y > page.height - 110 {
                    context.beginPage()
                    y = margin
                }

                y = drawRecord(record, y: y, margin: margin, width: page.width - margin * 2)
                y += 10
            }
        }
    }

    private static func drawHeader(
        y: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        recordCount: Int,
        total: Double,
        filterSummary: String
    ) -> CGFloat {
        let card = CGRect(x: margin, y: y, width: width, height: 142)
        UIColor.tripPDFInk.setFill()
        UIBezierPath(roundedRect: card, cornerRadius: 18).fill()

        drawText("PRISMJET", at: CGPoint(x: margin + 24, y: y + 22), attributes: eyebrowAttributes())
        drawText("Expenses Report", at: CGPoint(x: margin + 24, y: y + 48), attributes: titleAttributes(size: 32, color: .white))
        drawText(
            "\(recordCount) entries • \(LedgerFormatters.currency(total))",
            at: CGPoint(x: margin + 24, y: y + 88),
            attributes: bodyAttributes(color: .white.withAlphaComponent(0.86), size: 13)
        )
        drawText(
            filterSummary,
            in: CGRect(x: margin + 24, y: y + 108, width: width - 48, height: 28),
            attributes: bodyAttributes(color: .white.withAlphaComponent(0.7), size: 10)
        )

        return card.maxY
    }

    private static func drawSummaryBlocks(records: [ExpenseRecord], y: CGFloat, margin: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let grouped = Dictionary(grouping: records, by: \.status)
        let cardWidth = (pageWidth - margin * 2 - 18) / 3
        var x = margin

        for status in LedgerStatus.allCases {
            let statusRecords = grouped[status, default: []]
            let total = statusRecords.reduce(0) { $0 + $1.amount }
            let rect = CGRect(x: x, y: y, width: cardWidth, height: 72)

            UIColor.tripPDFCream.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

            drawText(status.title, at: CGPoint(x: x + 12, y: y + 12), attributes: bodyAttributes(color: .tripPDFMuted, size: 10))
            drawText(LedgerFormatters.currency(total), at: CGPoint(x: x + 12, y: y + 30), attributes: titleAttributes(size: 14, color: .tripPDFInk))
            drawText("\(statusRecords.count) entries", at: CGPoint(x: x + 12, y: y + 50), attributes: bodyAttributes(color: .tripPDFMuted, size: 9))

            x += cardWidth + 9
        }

        return y + 72
    }

    private static func drawRecord(_ record: ExpenseRecord, y: CGFloat, margin: CGFloat, width: CGFloat) -> CGFloat {
        let rect = CGRect(x: margin, y: y, width: width, height: 86)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

        UIColor.tripPDFLine.setStroke()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).stroke()

        drawText(record.displayMerchant, at: CGPoint(x: margin + 14, y: y + 12), attributes: titleAttributes(size: 13, color: .tripPDFInk))
        drawText(LedgerFormatters.currency(record.amount), at: CGPoint(x: margin + width - 118, y: y + 12), attributes: titleAttributes(size: 13, color: .tripPDFOrange))

        let meta = [
            LedgerFormatters.date(record.date),
            record.category,
            record.location,
            record.aircraft
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        drawText(meta, in: CGRect(x: margin + 14, y: y + 34, width: width - 28, height: 18), attributes: bodyAttributes(color: .tripPDFMuted, size: 9))
        let statusText: String
        if let archivedAt = record.archivedAt {
            statusText = "\(record.status.heading(for: record.recordType)) • Archived \(LedgerFormatters.date(archivedAt))"
        } else {
            statusText = record.status.heading(for: record.recordType)
        }

        drawText(statusText, at: CGPoint(x: margin + 14, y: y + 57), attributes: bodyAttributes(color: .tripPDFOrange, size: 9))

        if !record.notes.isEmpty {
            drawText(record.notes, in: CGRect(x: margin + 130, y: y + 57, width: width - 144, height: 18), attributes: bodyAttributes(color: .tripPDFMuted, size: 9))
        }

        return rect.maxY
    }

    private static func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
        NSString(string: text).draw(at: point, withAttributes: attributes)
    }

    private static func drawText(_ text: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private static func titleAttributes(size: CGFloat, color: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont(name: "IowanOldStyle-Roman", size: size) ?? UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color
        ]
    }

    private static func bodyAttributes(color: UIColor, size: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: color
        ]
    }

    private static func eyebrowAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.tripPDFHighlight,
            .kern: 1.6
        ]
    }
}

private extension UIColor {
    static let tripPDFInk = UIColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 1)
    static let tripPDFCream = UIColor(red: 1, green: 0.98, blue: 0.953, alpha: 1)
    static let tripPDFOrange = UIColor(red: 0.933, green: 0.443, blue: 0, alpha: 1)
    static let tripPDFHighlight = UIColor(red: 0.91, green: 0.745, blue: 0.518, alpha: 1)
    static let tripPDFMuted = UIColor(red: 0.424, green: 0.384, blue: 0.341, alpha: 1)
    static let tripPDFLine = UIColor(red: 0.933, green: 0.443, blue: 0, alpha: 0.16)
}
