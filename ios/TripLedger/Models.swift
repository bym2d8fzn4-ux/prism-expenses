import Foundation

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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeID(from: container)
        recordType = try container.decodeIfPresent(RecordType.self, forKey: .recordType) ?? .expense
        amount = Self.decodeDouble(from: container, forKey: .amount) ?? 0
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ExpenseCategory.miscellaneous.rawValue
        tripNumber = try container.decodeIfPresent(String.self, forKey: .tripNumber) ?? ""
        date = Self.decodeDate(from: container, forKey: .date) ?? .now
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        aircraft = try container.decodeIfPresent(String.self, forKey: .aircraft) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        submittedDate = Self.decodeDate(from: container, forKey: .submittedDate)
        reimbursedDate = Self.decodeDate(from: container, forKey: .reimbursedDate)
        archivedAt = Self.decodeDate(from: container, forKey: .archivedAt)
        receiptImageFilename = try container.decodeIfPresent(String.self, forKey: .receiptImageFilename)
        legacyPhotoDataURL = try container.decodeIfPresent(String.self, forKey: .legacyPhotoDataURL)
        createdAt = Self.decodeDate(from: container, forKey: .createdAt) ?? .now
        updatedAt = Self.decodeDate(from: container, forKey: .updatedAt) ?? createdAt
    }

    private static func decodeID(from container: KeyedDecodingContainer<CodingKeys>) -> UUID {
        if let id = try? container.decode(UUID.self, forKey: .id) {
            return id
        }

        if let idString = try? container.decode(String.self, forKey: .id),
           let id = UUID(uuidString: idString) {
            return id
        }

        return UUID()
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }

        if let value = try? container.decode(String.self, forKey: key) {
            let cleaned = value.replacingOccurrences(of: #"[^0-9.-]"#, with: "", options: .regularExpression)
            return Double(cleaned)
        }

        return nil
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }

        guard let rawValue = try? container.decode(String.self, forKey: key) else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if let date = isoFormatter.date(from: value) ?? fractionalISOFormatter.date(from: value) {
            return date
        }

        return dayFormatter.date(from: value)
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryOptions = try container.decodeIfPresent([String].self, forKey: .categoryOptions) ?? ExpenseCategory.defaultOptions
        aircraftOptions = try container.decodeIfPresent([String].self, forKey: .aircraftOptions) ?? []
        tripOptions = try container.decodeIfPresent([String].self, forKey: .tripOptions) ?? []
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
