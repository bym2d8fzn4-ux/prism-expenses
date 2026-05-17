import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ExpenseStore

    let mode: EditorMode
    let onSave: (ExpenseRecord) -> Void

    @State private var record: ExpenseRecord
    @State private var amountCents: Int
    @State private var receiptImage: UIImage?
    @State private var receiptImageChanged = false
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var isImportingReceiptFile = false
    @State private var isScanning = false
    @State private var alertMessage: String?
    @State private var newAircraft = ""
    @State private var newTrip = ""

    init(mode: EditorMode, onSave: @escaping (ExpenseRecord) -> Void) {
        let record = mode.record
        self.mode = mode
        self.onSave = onSave
        _record = State(initialValue: record)
        _amountCents = State(initialValue: Int((record.amount * 100).rounded()))
        _receiptImage = State(initialValue: ReceiptImageStore.image(for: record.receiptImageFilename))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry type", selection: $record.recordType) {
                        ForEach(RecordType.allCases) { type in
                            Text(type.singularTitle).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    receiptControls

                    if isScanning {
                        Label("Reading receipt...", systemImage: "text.viewfinder")
                            .foregroundStyle(.secondary)
                    }

                    receiptPreview
                }

                Section {
                    TextField("Vendor", text: $record.merchant)
                        .textContentType(.organizationName)

                    CurrencyAmountField(cents: $amountCents)

                    DatePicker(dateTitle, selection: $record.date, displayedComponents: .date)

                    Picker("Category", selection: $record.category) {
                        ForEach(store.categoryMenuOptions(including: record.category), id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }

                    Picker("Trip", selection: $record.tripNumber) {
                        Text("No trip").tag("")
                        ForEach(store.tripMenuOptions(including: record.tripNumber), id: \.self) { trip in
                            Text(trip).tag(trip)
                        }
                    }

                    HStack {
                        TextField("Add trip", text: $newTrip)
                            .textInputAutocapitalization(.characters)
                            .submitLabel(.done)
                            .onSubmit(addTrip)

                        Button("Add", action: addTrip)
                            .disabled(newTrip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Airport") {
                    TextField("Airport", text: $record.location)
                        .textInputAutocapitalization(.characters)

                    Picker("Aircraft", selection: $record.aircraft) {
                        Text("Select aircraft").tag("")
                        ForEach(store.aircraftMenuOptions(including: record.aircraft), id: \.self) { aircraft in
                            Text(aircraft).tag(aircraft)
                        }
                    }

                    HStack {
                        TextField("Add aircraft", text: $newAircraft)
                            .textInputAutocapitalization(.characters)
                            .submitLabel(.done)
                            .onSubmit(addAircraft)

                        Button("Add", action: addAircraft)
                            .disabled(newAircraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextField("Notes", text: $record.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Status") {
                    Toggle("Submitted", isOn: Binding(
                        get: { record.submittedDate != nil },
                        set: { isSubmitted in
                            record.submittedDate = isSubmitted ? (record.submittedDate ?? .now) : nil
                            if !isSubmitted {
                                record.reimbursedDate = nil
                            }
                        }
                    ))

                    if record.submittedDate != nil {
                        DatePicker(
                            "Date submitted",
                            selection: Binding($record.submittedDate, replacingNilWith: .now),
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                PhotoLibraryPickerView { image in
                    setReceiptImage(image)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { image in
                    setReceiptImage(image)
                }
            }
            .fileImporter(
                isPresented: $isImportingReceiptFile,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: false,
                onCompletion: importReceiptFile
            )
            .alert("Expenses", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var dateTitle: String {
        record.recordType == .incentive ? "Incentive date" : "Expense date"
    }

    private var receiptControls: some View {
        Menu {
            Button("Choose Photo", systemImage: "photo") {
                presentAfterMenuDismiss {
                    showingPhotoLibrary = true
                }
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo", systemImage: "camera") {
                    presentAfterMenuDismiss {
                        showingCamera = true
                    }
                }
            }

            Button("Choose File", systemImage: "folder") {
                presentAfterMenuDismiss {
                    isImportingReceiptFile = true
                }
            }
        } label: {
            Label(receiptImage == nil ? "Choose File" : "Replace File", systemImage: "paperclip")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.tripAccent)
    }

    @ViewBuilder
    private var receiptPreview: some View {
        if let receiptImage {
            Image(uiImage: receiptImage)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button("Remove File", systemImage: "xmark.circle", role: .destructive) {
                self.receiptImage = nil
                receiptImageChanged = true
            }
        }
    }

    private func importReceiptFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            if let image = UIImage(data: data) {
                setReceiptImage(image)
                return
            }

            guard let image = renderFirstPDFPage(from: data) else {
                alertMessage = "Choose an image or PDF file for receipt scanning."
                return
            }

            setReceiptImage(image)
        } catch {
            alertMessage = "Expenses could not import that file."
        }
    }

    private func setReceiptImage(_ image: UIImage) {
        receiptImage = image
        receiptImageChanged = true
        scanReceipt()
    }

    private func scanReceipt() {
        guard let receiptImage else {
            return
        }

        isScanning = true
        Task {
            defer { isScanning = false }

            do {
                let result = try await ReceiptScanner.scan(image: receiptImage)
                applyScanResult(result)
            } catch {
                alertMessage = "Expenses could not scan that receipt."
            }
        }
    }

    private func applyScanResult(_ result: ReceiptScanResult) {
        if let merchant = result.merchant, record.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record.merchant = merchant
        }

        if let amount = result.amount, amountCents == 0 {
            amountCents = Int((amount * 100).rounded())
        }

        if let date = result.date {
            record.date = date
        }

        if let category = result.category, record.category == ExpenseCategory.miscellaneous.rawValue {
            record.category = category
        }
    }

    private func addAircraft() {
        guard let aircraft = store.addAircraftOption(newAircraft) else {
            return
        }

        record.aircraft = aircraft
        newAircraft = ""
    }

    private func addTrip() {
        guard let trip = store.addTripOption(newTrip) else {
            return
        }

        record.tripNumber = trip
        newTrip = ""
    }

    private func save() {
        guard amountCents > 0 else {
            alertMessage = "Enter an amount greater than zero."
            return
        }

        guard !record.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Enter a vendor."
            return
        }

        if let submittedDate = record.submittedDate, submittedDate < Calendar.current.startOfDay(for: record.date) {
            alertMessage = "The submitted date cannot be earlier than the expense date."
            return
        }

        if let reimbursedDate = record.reimbursedDate {
            if reimbursedDate < Calendar.current.startOfDay(for: record.date) {
                alertMessage = "The paid date cannot be earlier than the expense date."
                return
            }

            if let submittedDate = record.submittedDate, reimbursedDate < submittedDate {
                alertMessage = "The paid date cannot be earlier than the submitted date."
                return
            }
        }

        do {
            var savedRecord = record
            savedRecord.amount = Double(amountCents) / 100

            if receiptImageChanged {
                if let receiptImage {
                    savedRecord.receiptImageFilename = try ReceiptImageStore.save(
                        receiptImage,
                        replacing: record.receiptImageFilename
                    )
                } else if let existing = record.receiptImageFilename {
                    ReceiptImageStore.delete(filename: existing)
                    savedRecord.receiptImageFilename = nil
                }
            }

            onSave(savedRecord)
            dismiss()
        } catch {
            alertMessage = "Expenses could not save the receipt photo."
        }
    }

    private func renderFirstPDFPage(from data: Data) -> UIImage? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            return nil
        }

        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let maxWidth: CGFloat = 1800
        let scale = maxWidth / pageBounds.width
        let imageSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
            context.cgContext.translateBy(x: 0, y: imageSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private func presentAfterMenuDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
    }
}

private struct CurrencyAmountField: UIViewRepresentable {
    @Binding var cents: Int

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = "Amount"
        textField.keyboardType = .numberPad
        textField.delegate = context.coordinator
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.inputAccessoryView = context.coordinator.makeToolbar()
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.text = cents == 0 ? "" : CurrencyInputFormatter.format(cents: cents)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CurrencyAmountField
        weak var textField: UITextField?

        init(parent: CurrencyAmountField) {
            self.parent = parent
        }

        func makeToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
            ]
            return toolbar
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                parent.cents /= 10
                return false
            }

            for digit in string.compactMap(\.wholeNumberValue) {
                parent.cents = min((parent.cents * 10) + digit, 99_999_999)
            }
            return false
        }

        @objc private func doneTapped() {
            textField?.resignFirstResponder()
        }
    }
}

private enum CurrencyInputFormatter {
    static func format(cents: Int) -> String {
        let dollars = cents / 100
        let centsRemainder = cents % 100
        return "\(groupThousands(String(dollars))).\(String(format: "%02d", centsRemainder))"
    }

    private static func groupThousands(_ digits: String) -> String {
        var grouped = ""

        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                grouped.insert(",", at: grouped.startIndex)
            }

            grouped.insert(character, at: grouped.startIndex)
        }

        return grouped
    }
}

private extension Binding where Value == Date {
    init(_ source: Binding<Date?>, replacingNilWith fallback: Date) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0 }
        )
    }
}
