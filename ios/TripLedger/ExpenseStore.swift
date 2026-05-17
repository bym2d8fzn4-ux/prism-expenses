import Foundation

@MainActor
final class ExpenseStore: ObservableObject {
    @Published private(set) var records: [ExpenseRecord] = []
    @Published private(set) var settings: AppSettings = .default
    @Published var lastError: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() async {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                records = []
                settings = .default
                return
            }

            let data = try Data(contentsOf: url)
            let payload = try decoder.decode(BackupPayload.self, from: data)
            records = payload.expenses.sortedForLedger()
            settings = payload.settings.normalized()
            settings.tripOptions = Self.recentOptions(settings.tripOptions + records.sortedForLedger().map(\.tripNumber), limit: 10)
        } catch {
            lastError = "Expenses could not load saved records."
        }
    }

    func upsert(_ record: ExpenseRecord) {
        var nextRecord = record
        nextRecord.updatedAt = .now

        if let index = records.firstIndex(where: { $0.id == nextRecord.id }) {
            records[index] = nextRecord
        } else {
            records.append(nextRecord)
        }

        rememberTrip(nextRecord.tripNumber)
        records = records.sortedForLedger()
        save()
    }

    func delete(_ record: ExpenseRecord) {
        records.removeAll { $0.id == record.id }
        if let filename = record.receiptImageFilename {
            ReceiptImageStore.delete(filename: filename)
        }
        save()
    }

    func markSubmittedToday(_ record: ExpenseRecord) {
        var updated = record
        updated.submittedDate = updated.submittedDate ?? .now
        upsert(updated)
    }

    func markReimbursedToday(_ record: ExpenseRecord) {
        var updated = record
        updated.submittedDate = updated.submittedDate ?? .now
        updated.reimbursedDate = .now
        updated.archivedAt = nil
        upsert(updated)
    }

    func markGroupPaid(_ recordsToUpdate: [ExpenseRecord]) {
        for record in recordsToUpdate {
            var updated = record
            updated.submittedDate = updated.submittedDate ?? .now
            updated.reimbursedDate = .now
            updated.archivedAt = nil
            if let index = records.firstIndex(where: { $0.id == updated.id }) {
                records[index] = updated
            }
        }

        records = records.sortedForLedger()
        save()
    }

    func archivePaidGroup(_ recordsToArchive: [ExpenseRecord]) {
        let archiveDate = Date.now
        for record in recordsToArchive where record.status == .reimbursed {
            var updated = record
            updated.archivedAt = archiveDate
            if let index = records.firstIndex(where: { $0.id == updated.id }) {
                records[index] = updated
            }
        }

        records = records.sortedForLedger()
        save()
    }

    func restoreArchivedGroup(_ recordsToRestore: [ExpenseRecord]) {
        for record in recordsToRestore {
            var updated = record
            updated.archivedAt = nil
            if let index = records.firstIndex(where: { $0.id == updated.id }) {
                records[index] = updated
            }
        }

        records = records.sortedForLedger()
        save()
    }

    func backupData() throws -> Data {
        try encoder.encode(BackupPayload(expenses: records, settings: settings.normalized()))
    }

    func importBackupData(_ data: Data) throws -> Int {
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var importedCount = 0

        for var incoming in payload.expenses {
            if incoming.receiptImageFilename == nil,
               let photoDataURL = incoming.legacyPhotoDataURL,
               let filename = try? ReceiptImageStore.saveDataURL(photoDataURL) {
                incoming.receiptImageFilename = filename
            }
            incoming.legacyPhotoDataURL = nil

            if let index = records.firstIndex(where: { $0.id == incoming.id }) {
                records[index] = incoming
            } else {
                records.append(incoming)
            }
            importedCount += 1
        }

        records = records.sortedForLedger()
        settings = settings.merging(payload.settings)
        save()
        return importedCount
    }

    func importCSVData(_ data: Data) throws -> Int {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let rows = Self.parseCSV(text)
        guard let header = rows.first, !header.isEmpty else {
            return 0
        }

        let headerMap = Dictionary(uniqueKeysWithValues: header.enumerated().map { index, value in
            (Self.normalizedHeader(value), index)
        })

        var imported: [ExpenseRecord] = []

        for row in rows.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let record = ExpenseRecord(
                recordType: Self.recordType(from: Self.value(in: row, headerMap: headerMap, keys: ["type", "entry type"])),
                amount: Self.parseAmount(Self.value(in: row, headerMap: headerMap, keys: ["amount", "total"])) ?? 0,
                merchant: Self.value(in: row, headerMap: headerMap, keys: ["vendor", "merchant", "name"]),
                category: Self.value(in: row, headerMap: headerMap, keys: ["category"]).ifEmpty(ExpenseCategory.miscellaneous.rawValue),
                tripNumber: Self.value(in: row, headerMap: headerMap, keys: ["trip #", "trip", "trip number"]),
                date: Self.parseDate(Self.value(in: row, headerMap: headerMap, keys: ["expense date", "date"])) ?? .now,
                location: Self.value(in: row, headerMap: headerMap, keys: ["airport", "location"]),
                aircraft: Self.value(in: row, headerMap: headerMap, keys: ["aircraft", "tail", "tail number", "tail #"]),
                notes: Self.value(in: row, headerMap: headerMap, keys: ["notes"]),
                submittedDate: Self.parseDate(Self.value(in: row, headerMap: headerMap, keys: ["submitted date", "date submitted"])),
                reimbursedDate: Self.parseDate(Self.value(in: row, headerMap: headerMap, keys: ["paid date", "reimbursed date", "date paid"])),
                archivedAt: Self.parseDate(Self.value(in: row, headerMap: headerMap, keys: ["archived date", "archived at"]))
            )

            guard record.amount > 0 || !record.merchant.isEmpty else {
                continue
            }

            imported.append(record)
        }

        records.append(contentsOf: imported)
        records = records.sortedForLedger()
        imported.forEach { rememberTrip($0.tripNumber) }
        settings = settings.merging(AppSettings(
            categoryOptions: imported.map(\.category),
            aircraftOptions: imported.map(\.aircraft),
            tripOptions: imported.map(\.tripNumber)
        ))
        save()
        return imported.count
    }

    func updateCategoryOptions(_ options: [String]) {
        settings.categoryOptions = Self.normalizedOptions(options, fallback: ExpenseCategory.defaultOptions)
        save()
    }

    func updateAircraftOptions(_ options: [String]) {
        settings.aircraftOptions = Self.normalizedOptions(options, fallback: [])
        save()
    }

    func updateTripOptions(_ options: [String]) {
        settings.tripOptions = Self.recentOptions(options.map { $0.uppercased() }, limit: 10)
        save()
    }

    func addAircraftOption(_ option: String) -> String? {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return nil
        }

        updateAircraftOptions(settings.aircraftOptions + [trimmed])
        return trimmed
    }

    func addTripOption(_ option: String) -> String? {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return nil
        }

        updateTripOptions([trimmed] + settings.tripOptions)
        return trimmed
    }

    func markGroupSubmitted(_ recordsToUpdate: [ExpenseRecord]) {
        for record in recordsToUpdate {
            var updated = record
            updated.submittedDate = updated.submittedDate ?? .now
            if let index = records.firstIndex(where: { $0.id == updated.id }) {
                records[index] = updated
            }
        }

        records = records.sortedForLedger()
        save()
    }

    func categoryMenuOptions(including currentValue: String = "") -> [String] {
        Self.normalizedOptions(settings.categoryOptions + [currentValue], fallback: ExpenseCategory.defaultOptions)
    }

    func aircraftMenuOptions(including currentValue: String = "") -> [String] {
        Self.normalizedOptions(settings.aircraftOptions + [currentValue], fallback: [])
    }

    func tripMenuOptions(including currentValue: String = "") -> [String] {
        Self.recentOptions(settings.tripOptions + [currentValue], limit: 10)
    }

    var reportCategories: [String] {
        Self.normalizedOptions(settings.categoryOptions + records.map(\.category), fallback: ExpenseCategory.defaultOptions)
    }

    var reportAirports: [String] {
        Self.normalizedOptions(records.map(\.location), fallback: [])
    }

    var reportAircraft: [String] {
        Self.normalizedOptions(settings.aircraftOptions + records.map(\.aircraft), fallback: [])
    }

    var archivedRecords: [ExpenseRecord] {
        records
            .filter { $0.archivedAt != nil }
            .sortedForLedger()
    }

    func records(matching filter: ReportFilter) -> [ExpenseRecord] {
        records.filter { record in
            switch filter.archiveScope {
            case .active:
                if record.archivedAt != nil {
                    return false
                }
            case .archived:
                if record.archivedAt == nil {
                    return false
                }
            case .all:
                break
            }

            if record.recordType == .expense, !filter.includeExpenses {
                return false
            }

            if record.recordType == .incentive, !filter.includeIncentives {
                return false
            }

            if let startDate = filter.startDate, record.date < Calendar.current.startOfDay(for: startDate) {
                return false
            }

            if let endDate = filter.endDate,
               let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)),
               record.date >= exclusiveEnd {
                return false
            }

            if !filter.categories.isEmpty, !filter.categories.contains(record.category) {
                return false
            }

            if !filter.airports.isEmpty, !filter.airports.contains(record.location) {
                return false
            }

            if !filter.aircraft.isEmpty, !filter.aircraft.contains(record.aircraft) {
                return false
            }

            return true
        }
        .sortedForLedger()
    }

    func reportCSV(for filteredRecords: [ExpenseRecord]) -> String {
        let header = [
            "Type",
            "Status",
            "Expected payout date",
            "Amount",
            "Vendor",
            "Category",
            "Trip #",
            "Expense date",
            "Submitted date",
            "Paid date",
            "Archived date",
            "Airport",
            "Aircraft",
            "Notes"
        ]

        let rows = filteredRecords.sortedForLedger().map { record in
            [
                record.recordType.singularTitle,
                record.status.heading(for: record.recordType),
                record.expectedPayoutDate.map { Self.isoDateFormatter.string(from: $0) } ?? "",
                String(format: "%.2f", record.amount),
                record.displayMerchant,
                record.category,
                record.tripNumber,
                Self.isoDateFormatter.string(from: record.date),
                record.submittedDate.map { Self.isoDateFormatter.string(from: $0) } ?? "",
                record.reimbursedDate.map { Self.isoDateFormatter.string(from: $0) } ?? "",
                record.archivedAt.map { Self.isoDateFormatter.string(from: $0) } ?? "",
                record.location,
                record.aircraft,
                record.notes
            ].map(Self.csvEscape).joined(separator: ",")
        }

        return ([header.map(Self.csvEscape).joined(separator: ",")] + rows).joined(separator: "\n")
    }

    private func save() {
        do {
            let url = try storageURL()
            let data = try backupData()
            try data.write(to: url, options: [.atomic])
            try writeAutoBackup(data: data)
        } catch {
            lastError = "Expenses could not save your latest changes."
        }
    }

    private func writeAutoBackup(data: Data) throws {
        let url = try documentsDirectory().appending(path: "Expenses Auto Backup.json")
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        let directory = try applicationSupportDirectory()
        return directory.appending(path: "trip-ledger-records.json")
    }

    private func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "TripLedger", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func documentsDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let csvDateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "M/d/yy", "M/d/yyyy", "M-d-yy", "M-d-yyyy"].map { pattern in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return csvDateFormatters.compactMap { $0.date(from: trimmed) }.first
    }

    private static func parseAmount(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func recordType(from value: String) -> RecordType {
        value.localizedCaseInsensitiveContains("incentive") ? .incentive : .expense
    }

    private static func value(in row: [String], headerMap: [String: Int], keys: [String]) -> String {
        for key in keys {
            if let index = headerMap[normalizedHeader(key)], index < row.count {
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ""
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated fileprivate static func normalizedOptions(_ options: [String], fallback: [String]) -> [String] {
        let cleaned = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let unique = cleaned.reduce(into: [String]()) { result, option in
            guard !result.contains(where: { $0.caseInsensitiveCompare(option) == .orderedSame }) else {
                return
            }
            result.append(option)
        }

        return unique.isEmpty ? fallback : unique
    }

    nonisolated fileprivate static func recentOptions(_ options: [String], limit: Int) -> [String] {
        Array(normalizedOptions(options, fallback: []).prefix(limit))
    }

    private func rememberTrip(_ tripNumber: String) {
        let trimmed = tripNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return
        }

        settings.tripOptions = Self.recentOptions([trimmed] + settings.tripOptions, limit: 10)
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInQuotes = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if isInQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        isInQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    isInQuotes.toggle()
                }
            } else if character == ",", !isInQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !isInQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }

        return escaped
    }
}

struct BackupPayload: Codable {
    var app: String = "Expenses"
    var exportedAt: Date = .now
    var expenses: [ExpenseRecord]
    var settings: AppSettings = .default

    init(
        app: String = "Expenses",
        exportedAt: Date = .now,
        expenses: [ExpenseRecord],
        settings: AppSettings = .default
    ) {
        self.app = app
        self.exportedAt = exportedAt
        self.expenses = expenses
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case app
        case exportedAt
        case expenses
        case settings
    }

    init(from decoder: Decoder) throws {
        if let records = try? decoder.singleValueContainer().decode([ExpenseRecord].self) {
            app = "Expenses"
            exportedAt = .now
            expenses = records
            settings = .default
            return
        }

        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        app = Self.decodeString(from: container, keys: ["app", "name"]).ifEmpty("Expenses")
        exportedAt = Self.decodeDate(from: container, keys: ["exportedAt", "createdAt"]) ?? .now
        expenses = Self.decodeRecords(from: container)

        let nestedSettings =
            Self.decodeSettings(from: container, keys: ["settings", "options"]) ?? .default
        let rootSettings = AppSettings(
            categoryOptions: Self.decodeStringArray(from: container, keys: ["categoryOptions", "categories"]),
            aircraftOptions: Self.decodeStringArray(from: container, keys: ["aircraftOptions", "aircraft"]),
            tripOptions: Self.decodeStringArray(from: container, keys: ["tripOptions", "trips"])
        )
        settings = nestedSettings.merging(rootSettings)
    }

    private static func decodeRecords(from container: KeyedDecodingContainer<FlexibleCodingKey>) -> [ExpenseRecord] {
        for keyName in ["expenses", "records", "entries", "items"] {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let records = try? container.decode([ExpenseRecord].self, forKey: key) {
                return records
            }
        }

        return []
    }

    private static func decodeSettings(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> AppSettings? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let settings = try? container.decode(AppSettings.self, forKey: key) {
                return settings
            }
        }

        return nil
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> String {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let value = try? container.decode(String.self, forKey: key) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ""
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> Date? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let date = try? container.decode(Date.self, forKey: key) {
                return date
            }

            if let string = try? container.decode(String.self, forKey: key) {
                let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let date = ISO8601DateFormatter().date(from: value) ?? dayFormatter.date(from: value) {
                    return date
                }
            }
        }

        return nil
    }

    private static func decodeStringArray(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) -> [String] {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let values = try? container.decode([String].self, forKey: key) {
                return values
            }
        }

        return []
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension AppSettings {
    func normalized() -> AppSettings {
        AppSettings(
            categoryOptions: ExpenseStore.normalizedOptions(categoryOptions, fallback: ExpenseCategory.defaultOptions),
            aircraftOptions: ExpenseStore.normalizedOptions(aircraftOptions, fallback: []),
            tripOptions: ExpenseStore.recentOptions(tripOptions, limit: 10)
        )
    }

    func merging(_ other: AppSettings) -> AppSettings {
        AppSettings(
            categoryOptions: ExpenseStore.normalizedOptions(categoryOptions + other.categoryOptions, fallback: ExpenseCategory.defaultOptions),
            aircraftOptions: ExpenseStore.normalizedOptions(aircraftOptions + other.aircraftOptions, fallback: []),
            tripOptions: ExpenseStore.recentOptions(tripOptions + other.tripOptions, limit: 10)
        )
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
