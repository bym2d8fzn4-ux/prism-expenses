import Foundation

struct FlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum RecordType: String, Codable, CaseIterable, Identifiable {
    case expense
    case incentive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            return "Expenses"
        case .incentive:
            return "Incentives"
        }
    }

    var singularTitle: String {
        switch self {
        case .expense:
            return "Expense"
        case .incentive:
            return "Incentive"
        }
    }
}

enum LedgerStatus: String, Codable, CaseIterable, Identifiable {
    case toSubmit
    case submitted
    case reimbursed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toSubmit:
            return "Not Submitted"
        case .submitted:
            return "Submitted"
        case .reimbursed:
            return "Paid"
        }
    }

    func heading(for type: RecordType) -> String {
        switch self {
        case .toSubmit:
            return "Not Submitted"
        case .submitted:
            return "Submitted"
        case .reimbursed:
            return "Paid"
        }
    }
}

enum ArchiveReportScope: String, Codable, CaseIterable, Identifiable {
    case active
    case archived
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return "Active"
        case .archived:
            return "Archived"
        case .all:
            return "Active + Archived"
        }
    }
}

enum LedgerGrouping: String, CaseIterable, Identifiable {
    case trip
    case week
    case airport
    case aircraft
    case vendor
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip:
            return "Trip"
        case .week:
            return "Week"
        case .airport:
            return "Airport"
        case .aircraft:
            return "Aircraft"
        case .vendor:
            return "Vendor"
        case .category:
            return "Category"
        }
    }
}

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case lodging = "Lodging"
    case meal = "Meal"
    case flight = "Flight"
    case transport = "Transport"
    case supplies = "Supplies"
    case miscellaneous = "Miscellaneous"

    var id: String { rawValue }
}

struct ExpenseRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var recordType: RecordType = .expense
    var amount: Double = 0
    var merchant: String = ""
    var category: String = ExpenseCategory.miscellaneous.rawValue
    var tripNumber: String = ""
    var date: Date = .now
    var location: String = ""
    var aircraft: String = ""
    var notes: String = ""
    var submittedDate: Date?
    var reimbursedDate: Date?
    var archivedAt: Date?
    var receiptImageFilename: String?
    var legacyPhotoDataURL: String?
    var createdAt: Date = .now
    var updatedAt: Date = .now

    init(
        id: UUID = UUID(),
        recordType: RecordType = .expense,
        amount: Double = 0,
        merchant: String = "",
        category: String = ExpenseCategory.miscellaneous.rawValue,
        tripNumber: String = "",
        date: Date = .now,
        location: String = "",
        aircraft: String = "",
        notes: String = "",
        submittedDate: Date? = nil,
        reimbursedDate: Date? = nil,
        archivedAt: Date? = nil,
        receiptImageFilename: String? = nil,
        legacyPhotoDataURL: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.recordType = recordType
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.tripNumber = tripNumber
        self.date = date
        self.location = location
        self.aircraft = aircraft
        self.notes = notes
        self.submittedDate = submittedDate
        self.reimbursedDate = reimbursedDate
        self.archivedAt = archivedAt
        self.receiptImageFilename = receiptImageFilename
        self.legacyPhotoDataURL = legacyPhotoDataURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recordType
        case amount
        case merchant
        case category
        case tripNumber
        case date
        case location
        case aircraft
        case notes
        case submittedDate
        case reimbursedDate
        case archivedAt
        case receiptImageFilename
        case legacyPhotoDataURL = "photoDataUrl"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        id = Self.decodeID(from: container)
        recordType = Self.decodeRecordType(from: container)
        amount = Self.decodeDouble(
            from: container,
            keys: ["amount", "totalAmount", "total", "finalTotal", "reimbursementAmount"],
            centKeys: ["amountCents", "totalCents"]
        ) ?? 0
        merchant = Self.decodeString(from: container, keys: ["merchant", "vendor", "displayMerchant", "name", "title", "description"])
        category = Self.decodeString(from: container, keys: ["category", "categoryName"]).ifEmpty(ExpenseCategory.miscellaneous.rawValue)
        tripNumber = Self.decodeString(from: container, keys: ["tripNumber", "trip", "tripName", "tripId", "tripNo", "tripNumberValue"])
        date = Self.decodeDate(
            from: container,
            keys: ["date", "expenseDate", "incentiveDate", "transactionDate", "recordDate"]
        ) ?? Self.decodeDate(
            from: container,
            keys: ["submittedDate", "dateSubmitted", "submittedAt", "submissionDate"]
        ) ?? Self.decodeDate(
            from: container,
            keys: ["reimbursedDate", "paidDate", "datePaid", "reimbursedAt", "reimbursementDate"]
        ) ?? .now
        location = Self.decodeString(from: container, keys: ["location", "airport", "airportCode"])
        aircraft = Self.decodeString(from: container, keys: ["aircraft", "tail", "tailNumber", "tailNumberValue"]).uppercased()
        notes = Self.decodeString(from: container, keys: ["notes", "memo", "comment", "comments"])
        submittedDate = Self.decodeDate(from: container, keys: ["submittedDate", "dateSubmitted", "submittedAt", "submissionDate", "submitted"])
        reimbursedDate = Self.decodeDate(from: container, keys: ["reimbursedDate", "paidDate", "datePaid", "reimbursedAt", "reimbursementDate", "paid"])
        archivedAt = Self.decodeDate(from: container, keys: ["archivedAt", "archivedDate", "archiveDate"])
        receiptImageFilename = Self.decodeString(from: container, keys: ["receiptImageFilename"]).nilIfEmpty
        legacyPhotoDataURL = Self.decodeString(
            from: container,
            keys: ["photoDataUrl", "legacyPhotoDataURL", "receiptImageDataUrl", "receiptPhotoDataUrl"]
        ).nilIfEmpty
        createdAt = Self.decodeDate(from: container, keys: ["createdAt", "createdDate"]) ?? .now
        updatedAt = Self.decodeDate(from: container, keys: ["updatedAt", "updatedDate", "modifiedAt"]) ?? createdAt
    }

    private static func decodeID(from container: KeyedDecodingContainer<FlexibleCodingKey>) -> UUID {
        guard let key = FlexibleCodingKey(stringValue: "id") else {
            return UUID()
        }

        if let id = try? container.decode(UUID.self, forKey: key) {
            return id
        }

        if let idString = try? container.decode(String.self, forKey: key) {
            if let id = UUID(uuidString: idString) {
                return id
            }

            if !idString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return deterministicID(from: idString)
            }
        }

        return UUID()
    }

    private static func decodeRecordType(from container: KeyedDecodingContainer<FlexibleCodingKey>) -> RecordType {
        let value = decodeString(from: container, keys: ["recordType", "type", "entryType", "kind"])
        return value.localizedCaseInsensitiveContains("incentive") ? .incentive : .expense
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String],
        centKeys: [String] = []
    ) -> Double? {
        if let cents = decodeNumeric(from: container, keys: centKeys) {
            return cents / 100
        }

        return decodeNumeric(from: container, keys: keys)
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
                return Calendar.current.startOfDay(for: date)
            }

            if let numericValue = try? container.decode(Double.self, forKey: key) {
                let seconds = numericValue > 10_000_000_000 ? numericValue / 1000 : numericValue
                return Calendar.current.startOfDay(for: Date(timeIntervalSince1970: seconds))
            }

            guard let rawValue = try? container.decode(String.self, forKey: key) else {
                continue
            }

            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            if let date = isoFormatter.date(from: value) ?? fractionalISOFormatter.date(from: value) {
                return Calendar.current.startOfDay(for: date)
            }

            if let date = dayFormatters.compactMap({ $0.date(from: value) }).first {
                return date
            }
        }

        return nil
    }

    private static func decodeString(from container: KeyedDecodingContainer<FlexibleCodingKey>, keys: [String]) -> String {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let value = try? container.decode(String.self, forKey: key) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                return String(value)
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }
        }

        return ""
    }

    private static func decodeNumeric(from container: KeyedDecodingContainer<FlexibleCodingKey>, keys: [String]) -> Double? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else {
                continue
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }

            if let value = try? container.decode(Int.self, forKey: key) {
                return Double(value)
            }

            if let value = try? container.decode(String.self, forKey: key) {
                let cleaned = value.replacingOccurrences(of: #"[^0-9.-]"#, with: "", options: .regularExpression)
                if let parsed = Double(cleaned) {
                    return parsed
                }
            }
        }

        return nil
    }

    private static func deterministicID(from value: String) -> UUID {
        func fnvHash(seed: UInt64, bytes: [UInt8]) -> UInt64 {
            bytes.reduce(seed) { partial, byte in
                (partial ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }

        let bytes = Array(value.utf8)
        let first = fnvHash(seed: 14_695_981_039_346_656_037, bytes: bytes)
        let second = fnvHash(seed: 7_803_522_088_215_333_221, bytes: Array(bytes.reversed()))
        var uuidBytes = (0..<8).map { UInt8((first >> ((7 - $0) * 8)) & 0xff) }
        uuidBytes.append(contentsOf: (0..<8).map { UInt8((second >> ((7 - $0) * 8)) & 0xff) })
        uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "M/d/yy", "M/d/yyyy", "M-d-yy", "M-d-yyyy", "MMM d, yyyy", "MMMM d, yyyy"].map { pattern in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    var status: LedgerStatus {
        if reimbursedDate != nil {
            return .reimbursed
        }

        if submittedDate != nil {
            return .submitted
        }

        return .toSubmit
    }

    var displayMerchant: String {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled entry" : merchant
    }

    var expectedPayoutDate: Date? {
        guard let submittedDate else {
            return nil
        }

        if recordType == .incentive {
            return Calendar.current.expectedIncentivePayoutDate(from: submittedDate)
        }

        return Calendar.current.expectedReimbursementFriday(from: submittedDate)
    }
}

struct AppSettings: Codable, Equatable {
    var categoryOptions: [String] = ExpenseCategory.defaultOptions
    var aircraftOptions: [String] = []
    var tripOptions: [String] = []

    static let `default` = AppSettings()

    init(
        categoryOptions: [String] = ExpenseCategory.defaultOptions,
        aircraftOptions: [String] = [],
        tripOptions: [String] = []
    ) {
        self.categoryOptions = categoryOptions
        self.aircraftOptions = aircraftOptions
        self.tripOptions = tripOptions
    }

    enum CodingKeys: String, CodingKey {
        case categoryOptions
        case aircraftOptions
        case tripOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        let decodedCategories = Self.decodeStringArray(from: container, keys: ["categoryOptions", "categories"])
        categoryOptions = decodedCategories.isEmpty ? ExpenseCategory.defaultOptions : decodedCategories
        aircraftOptions = Self.decodeStringArray(from: container, keys: ["aircraftOptions", "aircraft"])
        tripOptions = Self.decodeStringArray(from: container, keys: ["tripOptions", "trips"])
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
}

struct ReportFilter: Equatable {
    var includeExpenses = true
    var includeIncentives = true
    var startDate: Date?
    var endDate: Date?
    var categories: Set<String> = []
    var airports: Set<String> = []
    var aircraft: Set<String> = []
    var archiveScope: ArchiveReportScope = .active

    static let all = ReportFilter()
}

struct LedgerSummary {
    let count: Int
    let total: Double
}

extension Array where Element == ExpenseRecord {
    func scoped(to type: RecordType) -> [ExpenseRecord] {
        filter { $0.recordType == type }
    }

    func filtered(by status: LedgerStatus) -> [ExpenseRecord] {
        filter { $0.status == status }
    }

    func sortedForLedger() -> [ExpenseRecord] {
        sorted {
            if $0.date != $1.date {
                return $0.date > $1.date
            }

            return $0.updatedAt > $1.updatedAt
        }
    }

    func summary(for status: LedgerStatus) -> LedgerSummary {
        let records = filtered(by: status)
        return LedgerSummary(
            count: records.count,
            total: records.reduce(0.0) { $0 + $1.amount }
        )
    }
}

extension Calendar {
    func expectedReimbursementFriday(from submittedDate: Date) -> Date {
        let upcomingFriday = nextFriday(onOrAfter: submittedDate)
        let cutoffMonday = startOfWeek(containing: upcomingFriday)

        if startOfDay(for: submittedDate) <= cutoffMonday {
            return upcomingFriday
        }

        return date(byAdding: .day, value: 7, to: upcomingFriday) ?? upcomingFriday
    }

    func expectedIncentivePayoutDate(from submittedDate: Date) -> Date {
        let components = dateComponents([.year, .month, .day], from: submittedDate)
        let day = components.day ?? 1

        if day <= 15 {
            return date(from: DateComponents(year: components.year, month: components.month, day: 15)) ?? submittedDate
        }

        let firstOfMonth = date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? submittedDate
        let nextMonth = date(byAdding: .month, value: 1, to: firstOfMonth) ?? firstOfMonth
        let nextComponents = dateComponents([.year, .month], from: nextMonth)
        return date(from: DateComponents(year: nextComponents.year, month: nextComponents.month, day: 15)) ?? submittedDate
    }

    private func nextFriday(onOrAfter date: Date) -> Date {
        let start = startOfDay(for: date)
        let weekday = component(.weekday, from: start)
        let daysUntilFriday = (6 - weekday + 7) % 7
        return self.date(byAdding: .day, value: daysUntilFriday, to: start) ?? start
    }

    func startOfWeek(containing date: Date) -> Date {
        let start = startOfDay(for: date)
        let weekday = component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }
}

extension ExpenseCategory {
    static var defaultOptions: [String] {
        allCases.map(\.rawValue)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
