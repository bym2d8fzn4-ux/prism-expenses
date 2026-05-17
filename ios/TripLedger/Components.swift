import PhotosUI
import SwiftUI
import UIKit

enum LedgerFormatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let weekdayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d, yyyy"
        return formatter
    }()

    static func currency(_ value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func date(_ value: Date?) -> String {
        guard let value else {
            return "Not set"
        }

        return shortDate.string(from: value)
    }

    static func weekdayDate(_ value: Date) -> String {
        weekdayDate.string(from: value)
    }
}

struct SummaryTile: View {
    let title: String
    let summary: LedgerSummary
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .bottomLeading)

            Text(LedgerFormatters.currency(summary.total))
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            Text("\(summary.count) \(summary.count == 1 ? "entry" : "entries")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(isSelected ? Color.tripAccent.opacity(0.16) : Color.tripSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.tripAccent : Color.tripLine, lineWidth: isSelected ? 1.5 : 1)
        }
    }
}

struct RecordCard: View {
    let record: ExpenseRecord
    let onEdit: () -> Void
    let onQuickStatus: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusBadge(status: record.status, recordType: record.recordType)
                    if !record.tripNumber.isEmpty {
                        Text("Trip \(record.tripNumber)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.tripHighlight.opacity(0.22))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    detailLabel("Date", LedgerFormatters.date(record.date))
                    detailLabel("Category", record.category)
                    if !record.location.isEmpty {
                        detailLabel("Airport", record.location)
                    }
                    if !record.aircraft.isEmpty {
                        detailLabel("Aircraft", record.aircraft)
                    }
                    if let expected = record.expectedPayoutDate, record.status == .submitted {
                        detailLabel("Expected payout", LedgerFormatters.date(expected))
                    }
                    if let submittedDate = record.submittedDate {
                        detailLabel("Submitted", LedgerFormatters.date(submittedDate))
                    }
                    if let reimbursedDate = record.reimbursedDate {
                        detailLabel("Paid", LedgerFormatters.date(reimbursedDate))
                    }
                    if let archivedAt = record.archivedAt {
                        detailLabel("Archived", LedgerFormatters.date(archivedAt))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !record.notes.isEmpty {
                    Text(record.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let image = ReceiptImageStore.image(for: record.receiptImageFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack {
                    if record.status != .reimbursed {
                        Button(quickStatusTitle, action: onQuickStatus)
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button("Edit", systemImage: "pencil", action: onEdit)
                        .buttonStyle(.bordered)

                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                }
                .labelStyle(.iconOnly)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayMerchant)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.tripInk)
                        .lineLimit(1)

                    Text(compactMeta)
                        .font(.caption)
                        .foregroundStyle(Color.tripMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(LedgerFormatters.currency(record.amount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.tripAccent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.tripSurface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
    }

    private var compactMeta: String {
        [
            LedgerFormatters.date(record.date),
            record.category,
            record.location,
            record.aircraft
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func detailLabel(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tripMuted)
            Text(value)
        }
    }

    private var quickStatusTitle: String {
        switch record.status {
        case .toSubmit:
            return "Mark submitted"
        case .submitted:
            return "Mark paid"
        case .reimbursed:
            return ""
        }
    }
}

struct StatusBadge: View {
    let status: LedgerStatus
    let recordType: RecordType

    var body: some View {
        Text(status.heading(for: recordType))
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .toSubmit:
            return .tripAccent
        case .submitted:
            return .tripWarning
        case .reimbursed:
            return .tripSuccess
        }
    }
}

struct EmptyLedgerState: View {
    let status: LedgerStatus
    let recordType: RecordType

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(Color.tripAccent)

            Text(emptyTitle)
                .font(.headline)

            Text(emptyBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.tripSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
}

    private var emptyTitle: String {
        switch status {
        case .toSubmit:
            return "Nothing is waiting to be submitted."
        case .submitted:
            return "Nothing has been submitted yet."
        case .reimbursed:
            return "No paid entries yet."
        }
    }

    private var emptyBody: String {
        switch (status, recordType) {
        case (.toSubmit, .expense):
            return "Add a new expense and it will land here."
        case (.toSubmit, .incentive):
            return "Add a new incentive and it will land here."
        case (.submitted, .expense):
            return "Submitted expenses will wait here until they are paid."
        case (.submitted, .incentive):
            return "Submitted incentives will wait here until they are paid."
        case (.reimbursed, .expense):
            return "Paid expenses will move here."
        case (.reimbursed, .incentive):
            return "Paid incentives will move here."
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                dismiss()
                return
            }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [onImage, dismiss] object, _ in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            onImage(image)
                        }
                        dismiss()
                    }
                }
            } else {
                dismiss()
            }
        }
    }
}

extension Color {
    static let tripBackground = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let tripBackgroundWarm = Color(red: 0.09, green: 0.07, blue: 0.05)
    static let tripSurface = Color(red: 1.0, green: 0.992, blue: 0.973)
    static let tripSurfaceStrong = Color(red: 1.0, green: 0.98, blue: 0.953)
    static let tripLine = Color(red: 0.933, green: 0.443, blue: 0.0).opacity(0.16)
    static let tripInk = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let tripMuted = Color(red: 0.424, green: 0.384, blue: 0.341)
    static let tripAccent = Color(red: 0.933, green: 0.443, blue: 0.0)
    static let tripAccentStrong = Color(red: 0.784, green: 0.357, blue: 0.0)
    static let tripHighlight = Color(red: 0.91, green: 0.745, blue: 0.518)
    static let tripSuccess = Color(red: 0.184, green: 0.427, blue: 0.333)
    static let tripWarning = Color(red: 0.639, green: 0.353, blue: 0.114)
}
