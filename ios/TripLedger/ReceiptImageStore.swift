import Foundation
import UIKit

enum ReceiptImageStore {
    static func save(_ image: UIImage, replacing existingFilename: String? = nil) throws -> String {
        if let existingFilename {
            delete(filename: existingFilename)
        }

        let filename = "\(UUID().uuidString).jpg"
        let url = try receiptsDirectory().appending(path: filename)
        let resized = image.resized(maxDimension: 1800)

        guard let data = resized.jpegData(compressionQuality: 0.82) else {
            throw ReceiptImageError.couldNotCreateJPEG
        }

        try data.write(to: url, options: [.atomic])
        return filename
    }

    static func saveDataURL(_ dataURL: String, replacing existingFilename: String? = nil) throws -> String? {
        let trimmed = dataURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let base64Payload: String
        if let commaIndex = trimmed.firstIndex(of: ",") {
            base64Payload = String(trimmed[trimmed.index(after: commaIndex)...])
        } else {
            base64Payload = trimmed
        }

        guard let data = Data(base64Encoded: base64Payload, options: [.ignoreUnknownCharacters]),
              let image = UIImage(data: data) else {
            return nil
        }

        return try save(image, replacing: existingFilename)
    }

    static func image(for filename: String?) -> UIImage? {
        guard let filename else {
            return nil
        }

        guard let url = try? receiptsDirectory().appending(path: filename) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    static func delete(filename: String) {
        guard let url = try? receiptsDirectory().appending(path: filename) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func receiptsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "TripLedger/Receipts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum ReceiptImageError: Error {
    case couldNotCreateJPEG
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return self
        }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
