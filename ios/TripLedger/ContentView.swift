import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ExpenseStore

    @State private var selectedType: RecordType = .expense
    @State private var selectedStatus: LedgerStatus = .toSubmit
    @State private var selectedGrouping: LedgerGrouping = .week
    @State private var editorMode: EditorMode?
    @State private var recordToDelete: ExpenseRecord?
    @State private var alertMessage: String?
    @State private var selectedImportKind: ImportKind = .backup
    @State private var isImportingFile = false
    @State private var isExportingFile = false
    @State private var isShowingArchive = false
    @State private var reportExportKind: ReportExportKind?
    @State private var settingsSheet: SettingsSheetKind?
    @State private var exportDocument = ExportDataDocument()
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = "Expenses Manual Backup.json"
    @State private var exportSuccessMessage = "File exported."

    private var scopedRecords: [ExpenseRecord] {
        store.records
            .filter { $0.archivedAt == nil }
            .scoped(to: selectedType)
    }

    private var filteredRecords: [ExpenseRecord] {
        scopedRecords.filtered(by: selectedStatus).sortedForLedger()
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HomeTopBar(menu: homeMenu)

                    HeaderPanel {
                        editorMode = .new(selectedType)
                    }

                    Picker("Entry type", selection: $selectedType) {
                        ForEach(RecordType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.tripAccent)
                    .padding(8)
                    .background(Color.tripSurface.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    SummaryGrid(
                        selectedType: selectedType,
                        selectedStatus: $selectedStatus,
                        records: scopedRecords
                    )

                    GroupingSelector(selectedGrouping: $selectedGrouping)

                    LedgerSection(
                        selectedType: selectedType,
                        selectedStatus: selectedStatus,
                        selectedGrouping: selectedGrouping,
                        records: filteredRecords,
                        onEdit: { editorMode = .edit($0) },
                        onQuickStatus: quickStatus,
                        onDelete: { recordToDelete = $0 },
                        onMarkGroupSubmitted: store.markGroupSubmitted,
                        onMarkGroupPaid: store.markGroupPaid,
                        onArchiveGroup: store.archivePaidGroup
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .background {
                LinearGradient(
                    colors: [.tripBackground, .tripBackground, .tripBackgroundWarm],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .sheet(item: $editorMode) { mode in
                RecordEditorView(mode: mode) { record in
                    store.upsert(record)
                }
            }
            .sheet(item: $reportExportKind) { kind in
                ReportOptionsSheet(
                    kind: kind,
                    categories: store.reportCategories,
                    airports: store.reportAirports,
                    aircraft: store.reportAircraft
                ) { filter in
                    prepareReportExport(kind: kind, filter: filter)
                }
            }
            .sheet(item: $settingsSheet) { kind in
                EditableOptionsSheet(
                    kind: kind,
                    options: options(for: kind)
                ) { options in
                    switch kind {
                    case .categories:
                        store.updateCategoryOptions(options)
                    case .aircraft:
                        store.updateAircraftOptions(options)
                    case .trips:
                        store.updateTripOptions(options)
                    }
                }
            }
            .sheet(isPresented: $isShowingArchive) {
                ArchiveSheet(
                    records: store.archivedRecords,
                    onRestoreGroup: store.restoreArchivedGroup
                )
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: Binding(
                    get: { recordToDelete != nil },
                    set: { if !$0 { recordToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let recordToDelete {
                        store.delete(recordToDelete)
                    }
                    recordToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    recordToDelete = nil
                }
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: selectedImportKind.allowedContentTypes,
                allowsMultipleSelection: false,
                onCompletion: importFile
            )
            .fileExporter(
                isPresented: $isExportingFile,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                handleExportResult(result, successMessage: exportSuccessMessage)
            }
            .alert("Expenses", isPresented: Binding(
                get: { alertMessage != nil || store.lastError != nil },
                set: { if !$0 { alertMessage = nil; store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? store.lastError ?? "")
            }
    }

    private var homeMenu: some View {
        Menu {
            Button("Import Backup", systemImage: "square.and.arrow.down") {
                presentAfterMenuDismiss {
                    selectedImportKind = .backup
                    isImportingFile = true
                }
            }

            Button("Import CSV File", systemImage: "doc.badge.plus") {
                presentAfterMenuDismiss {
                    selectedImportKind = .csv
                    isImportingFile = true
                }
            }

            Button("Export Backup", systemImage: "archivebox") {
                presentAfterMenuDismiss {
                    prepareBackupExport()
                }
            }

            Button("Export CSV Report", systemImage: "tablecells") {
                presentAfterMenuDismiss {
                    reportExportKind = .csv
                }
            }

            Button("Export PDF Report", systemImage: "doc.richtext") {
                presentAfterMenuDismiss {
                    reportExportKind = .pdf
                }
            }

            Divider()

            Button("Archive", systemImage: "archivebox.fill") {
                presentAfterMenuDismiss {
                    isShowingArchive = true
                }
            }

            Button("Categories", systemImage: "tag") {
                presentAfterMenuDismiss {
                    settingsSheet = .categories
                }
            }

            Button("Aircraft", systemImage: "airplane") {
                presentAfterMenuDismiss {
                    settingsSheet = .aircraft
                }
            }

            Button("Trips", systemImage: "number") {
                presentAfterMenuDismiss {
                    settingsSheet = .trips
                }
            }
        } label: {
            HamburgerMenuIcon()
        }
    }

    private func options(for kind: SettingsSheetKind) -> [String] {
        switch kind {
        case .categories:
            return store.settings.categoryOptions
        case .aircraft:
            return store.settings.aircraftOptions
        case .trips:
            return store.settings.tripOptions
        }
    }

    private func quickStatus(_ record: ExpenseRecord) {
        switch record.status {
        case .toSubmit:
            store.markSubmittedToday(record)
        case .submitted:
            store.markReimbursedToday(record)
        case .reimbursed:
            break
        }
    }

    private func prepareBackupExport() {
        do {
            exportDocument = ExportDataDocument(data: try store.backupData())
            exportContentType = .json
            exportFilename = "Expenses Manual Backup \(Self.fileDateFormatter.string(from: .now)).json"
            exportSuccessMessage = "Backup exported."
            isExportingFile = true
        } catch {
            alertMessage = "Expenses could not create a backup file."
        }
    }

    private func prepareReportExport(kind: ReportExportKind, filter: ReportFilter) {
        let records = store.records(matching: filter)
        guard !records.isEmpty else {
            alertMessage = "No entries match those report options."
            return
        }

        switch kind {
        case .csv:
            exportDocument = ExportDataDocument(data: Data(store.reportCSV(for: records).utf8))
            exportContentType = .commaSeparatedText
            exportFilename = "Expenses Report.csv"
            exportSuccessMessage = "CSV report exported."
            isExportingFile = true
        case .pdf:
            exportDocument = ExportDataDocument(data: PDFReportRenderer.render(
                records: records,
                filterSummary: reportFilterSummary(filter)
            ))
            exportContentType = .pdf
            exportFilename = "Expenses Report.pdf"
            exportSuccessMessage = "PDF report exported."
            isExportingFile = true
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        switch selectedImportKind {
        case .backup:
            importBackup(result)
        case .csv:
            importCSV(result)
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let count = try store.importBackupData(Data(contentsOf: url))
            alertMessage = "Imported \(count) \(count == 1 ? "entry" : "entries")."
        } catch {
            alertMessage = "Expenses could not import that backup."
        }
    }

    private func importCSV(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let count = try store.importCSVData(Data(contentsOf: url))
            alertMessage = "Imported \(count) \(count == 1 ? "entry" : "entries") from CSV."
        } catch {
            alertMessage = "Expenses could not import that CSV file."
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>, successMessage: String) {
        switch result {
        case .success:
            alertMessage = successMessage
        case .failure:
            alertMessage = "Expenses could not export that file."
        }
    }

    private func presentAfterMenuDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
    }

    private func reportFilterSummary(_ filter: ReportFilter) -> String {
        var parts: [String] = []
        if let startDate = filter.startDate, let endDate = filter.endDate {
            parts.append("\(LedgerFormatters.date(startDate)) through \(LedgerFormatters.date(endDate))")
        }
        if !filter.categories.isEmpty {
            parts.append("Categories: \(filter.categories.sorted().joined(separator: ", "))")
        }
        if !filter.airports.isEmpty {
            parts.append("Airports: \(filter.airports.sorted().joined(separator: ", "))")
        }
        if !filter.aircraft.isEmpty {
            parts.append("Aircraft: \(filter.aircraft.sorted().joined(separator: ", "))")
        }
        if filter.archiveScope != .active {
            parts.append(filter.archiveScope.title)
        }
        return parts.isEmpty ? "All entries" : parts.joined(separator: " • ")
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum ImportKind {
    case backup
    case csv

    var allowedContentTypes: [UTType] {
        switch self {
        case .backup:
            return [.json, .plainText, .text, .data]
        case .csv:
            return [.commaSeparatedText, .plainText, .text, .data]
        }
    }
}

enum EditorMode: Identifiable {
    case new(RecordType)
    case edit(ExpenseRecord)

    var id: String {
        switch self {
        case .new(let type):
            return "new-\(type.rawValue)"
        case .edit(let record):
            return "edit-\(record.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .new:
            return "New"
        case .edit(let record):
            return "Edit \(record.recordType.singularTitle)"
        }
    }

    var record: ExpenseRecord {
        switch self {
        case .new(let type):
            ExpenseRecord(recordType: type)
        case .edit(let record):
            record
        }
    }
}

private struct HomeTopBar<MenuContent: View>: View {
    let menu: MenuContent

    var body: some View {
        HStack {
            Text("Expenses")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Spacer()

            menu
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

private struct HeaderPanel: View {
    let onNewRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Image("PrismJetLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 142)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.tripSurfaceStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 14, y: 9)

                    Text("Expenses")
                        .font(.custom("Iowan Old Style", size: 38).weight(.regular))
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                }

                Spacer()
            }

            Button(action: onNewRecord) {
                Label("New", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.tripAccent)
        }
        .padding(16)
        .background {
            LinearGradient(
                colors: [
                    Color.tripBackground,
                    Color(red: 0.075, green: 0.075, blue: 0.075),
                    Color.tripBackgroundWarm
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }
}

private struct SummaryGrid: View {
    let selectedType: RecordType
    @Binding var selectedStatus: LedgerStatus
    let records: [ExpenseRecord]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(LedgerStatus.allCases) { status in
                Button {
                    selectedStatus = status
                } label: {
                    SummaryTile(
                        title: status.heading(for: selectedType),
                        summary: records.summary(for: status),
                        isSelected: selectedStatus == status
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GroupingSelector: View {
    @Binding var selectedGrouping: LedgerGrouping

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(LedgerGrouping.allCases) { grouping in
                Button {
                    selectedGrouping = grouping
                } label: {
                    Text(grouping.title)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedGrouping == grouping ? .white : Color.tripInk)
                        .background(selectedGrouping == grouping ? Color.tripAccent : Color.tripSurface.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.tripLine, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LedgerSection: View {
    let selectedType: RecordType
    let selectedStatus: LedgerStatus
    let selectedGrouping: LedgerGrouping
    let records: [ExpenseRecord]
    let onEdit: (ExpenseRecord) -> Void
    let onQuickStatus: (ExpenseRecord) -> Void
    let onDelete: (ExpenseRecord) -> Void
    let onMarkGroupSubmitted: ([ExpenseRecord]) -> Void
    let onMarkGroupPaid: ([ExpenseRecord]) -> Void
    let onArchiveGroup: ([ExpenseRecord]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedStatus.heading(for: selectedType))
                        .font(.title2.weight(.bold))
                    Text("\(records.count) \(records.count == 1 ? "entry" : "entries") • \(LedgerFormatters.currency(records.reduce(0.0) { $0 + $1.amount }))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if records.isEmpty {
                EmptyLedgerState(status: selectedStatus, recordType: selectedType)
            } else {
                ForEach(ledgerGroups) { group in
                    PayoutGroupView(
                        group: group,
                        status: selectedStatus,
                        onEdit: onEdit,
                        onQuickStatus: onQuickStatus,
                        onDelete: onDelete,
                        onMarkSubmitted: { onMarkGroupSubmitted(group.records) },
                        onMarkPaid: { onMarkGroupPaid(group.records) },
                        onArchive: { onArchiveGroup(group.records) }
                    )
                }
            }
        }
    }

    private var ledgerGroups: [PayoutGroup] {
        let grouped = Dictionary(grouping: records) { record in
            groupDescriptor(for: record)
        }

        return grouped.map { descriptor, groupRecords in
            let sortedRecords = groupRecords.sortedForLedger()
            return PayoutGroup(
                id: "\(selectedGrouping.rawValue)-\(descriptor.key)",
                title: descriptor.title,
                sortDate: descriptor.sortDate ?? sortedRecords.map(sortDate(for:)).max() ?? .distantPast,
                records: sortedRecords
            )
        }
        .sorted {
            if $0.sortDate != $1.sortDate {
                return $0.sortDate > $1.sortDate
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func groupDescriptor(for record: ExpenseRecord) -> GroupDescriptor {
        switch selectedGrouping {
        case .trip:
            let value = record.tripNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return GroupDescriptor(key: value.ifEmpty("none"), title: value.isEmpty ? "No Trip" : "Trip \(value)")
        case .week:
            return weekGroupDescriptor(for: record)
        case .airport:
            let value = record.location.trimmingCharacters(in: .whitespacesAndNewlines)
            return GroupDescriptor(key: value.ifEmpty("none").lowercased(), title: value.isEmpty ? "No Airport" : value)
        case .aircraft:
            let value = record.aircraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return GroupDescriptor(key: value.ifEmpty("none").lowercased(), title: value.isEmpty ? "No Aircraft" : value)
        case .vendor:
            let value = record.displayMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
            return GroupDescriptor(key: value.lowercased(), title: value)
        case .category:
            let value = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            return GroupDescriptor(key: value.ifEmpty("none").lowercased(), title: value.isEmpty ? "No Category" : value)
        }
    }

    private func weekGroupDescriptor(for record: ExpenseRecord) -> GroupDescriptor {
        let date: Date
        let title: String

        switch selectedStatus {
        case .toSubmit:
            date = Calendar.current.startOfWeek(containing: record.date)
            title = "Week \(LedgerFormatters.date(date))"
        case .submitted:
            date = Calendar.current.startOfDay(for: record.expectedPayoutDate ?? record.submittedDate ?? record.date)
            title = record.recordType == .expense ? LedgerFormatters.weekdayDate(date) : "Payout \(LedgerFormatters.date(date))"
        case .reimbursed:
            date = Calendar.current.startOfDay(for: record.reimbursedDate ?? record.submittedDate ?? record.date)
            title = "Paid \(LedgerFormatters.date(date))"
        }

        return GroupDescriptor(
            key: String(date.timeIntervalSinceReferenceDate),
            title: title,
            sortDate: date
        )
    }

    private func sortDate(for record: ExpenseRecord) -> Date {
        switch selectedStatus {
        case .toSubmit:
            return record.date
        case .submitted:
            return record.submittedDate ?? record.date
        case .reimbursed:
            return record.reimbursedDate ?? record.submittedDate ?? record.date
        }
    }
}

private struct PayoutGroup: Identifiable {
    let id: String
    let title: String
    let sortDate: Date
    let records: [ExpenseRecord]

    var total: Double { records.reduce(0.0) { $0 + $1.amount } }
}

private struct GroupDescriptor: Hashable {
    let key: String
    let title: String
    var sortDate: Date?
}

private struct PayoutGroupView: View {
    let group: PayoutGroup
    let status: LedgerStatus
    let onEdit: (ExpenseRecord) -> Void
    let onQuickStatus: (ExpenseRecord) -> Void
    let onDelete: (ExpenseRecord) -> Void
    let onMarkSubmitted: () -> Void
    let onMarkPaid: () -> Void
    let onArchive: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 12) {
                if status == .submitted {
                    Button("Mark Group Paid", systemImage: "checkmark.circle", action: onMarkPaid)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(group.records) { record in
                    RecordCard(
                        record: record,
                        onEdit: { onEdit(record) },
                        onQuickStatus: { onQuickStatus(record) },
                        onDelete: { onDelete(record) }
                    )
                }
            }
            .padding(.top, 12)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("\(group.records.count) \(group.records.count == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                HStack(spacing: 8) {
                    Text(LedgerFormatters.currency(group.total))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .lineLimit(1)

                    if status == .toSubmit {
                        Button("Submit", action: onMarkSubmitted)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.green)
                    } else if status == .reimbursed {
                        Button("Archive", role: .destructive, action: onArchive)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                    }
                }
                .padding(.trailing, 22)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.tripSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 5)
    }
}

private struct ArchiveSheet: View {
    @Environment(\.dismiss) private var dismiss

    let records: [ExpenseRecord]
    let onRestoreGroup: ([ExpenseRecord]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if archiveGroups.isEmpty {
                        EmptyArchiveState()
                    } else {
                        ForEach(archiveGroups) { group in
                            ArchivedGroupView(group: group) {
                                onRestoreGroup(group.records)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.tripBackground.ignoresSafeArea())
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var archiveGroups: [PayoutGroup] {
        let grouped = Dictionary(grouping: records) { record in
            Calendar.current.startOfDay(for: record.reimbursedDate ?? record.archivedAt ?? record.date)
        }

        return grouped.keys.sorted(by: >).map { date in
            PayoutGroup(
                id: "archive-\(date.timeIntervalSinceReferenceDate)",
                title: "Paid \(LedgerFormatters.date(date))",
                sortDate: date,
                records: grouped[date, default: []].sortedForLedger()
            )
        }
    }
}

private struct ArchivedGroupView: View {
    let group: PayoutGroup
    let onRestore: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Restore Group", systemImage: "arrow.uturn.backward", action: onRestore)
                    .buttonStyle(.bordered)

                ForEach(group.records) { record in
                    ArchivedRecordRow(record: record)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.headline)
                    Text("\(group.records.count) \(group.records.count == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(LedgerFormatters.currency(group.total))
                    .font(.headline.monospacedDigit())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.tripSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ArchivedRecordRow: View {
    let record: ExpenseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.displayMerchant)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(LedgerFormatters.currency(record.amount))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.tripAccent)
            }

            Text(meta)
                .font(.caption)
                .foregroundStyle(Color.tripMuted)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var meta: String {
        [
            record.recordType.singularTitle,
            LedgerFormatters.date(record.date),
            record.category,
            record.location,
            record.aircraft
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct EmptyArchiveState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.largeTitle)
                .foregroundStyle(Color.tripAccent)
            Text("No archived groups yet.")
                .font(.headline)
            Text("Paid groups you archive will stay here and can still be exported in reports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.tripSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum ReportExportKind: String, Identifiable {
    case csv
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csv:
            return "Export CSV Report"
        case .pdf:
            return "Export PDF Report"
        }
    }
}

private enum SettingsSheetKind: String, Identifiable {
    case categories
    case aircraft
    case trips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categories:
            return "Categories"
        case .aircraft:
            return "Aircraft"
        case .trips:
            return "Trips"
        }
    }

    var addPlaceholder: String {
        switch self {
        case .categories:
            return "New category"
        case .aircraft:
            return "Tail number"
        case .trips:
            return "Trip number"
        }
    }

    var textCapitalization: TextInputAutocapitalization {
        switch self {
        case .categories:
            return .words
        case .aircraft, .trips:
            return .characters
        }
    }
}

private struct HamburgerMenuIcon: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(Color.tripAccent)
                    .frame(width: 22, height: 3)
            }
        }
        .padding(8)
        .background(Color.tripSurface.opacity(0.12))
        .clipShape(Circle())
        .accessibilityLabel("Menu")
    }
}

private struct ReportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: ReportExportKind
    let categories: [String]
    let airports: [String]
    let aircraft: [String]
    let onExport: (ReportFilter) -> Void

    @State private var includeExpenses = true
    @State private var includeIncentives = true
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate = Date.now
    @State private var selectedCategories: Set<String> = []
    @State private var selectedAirports: Set<String> = []
    @State private var selectedAircraft: Set<String> = []
    @State private var archiveScope: ArchiveReportScope = .active

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry Types") {
                    Toggle("Expenses", isOn: $includeExpenses)
                    Toggle("Incentives", isOn: $includeIncentives)
                }

                Section("Date Range") {
                    Toggle("Limit date range", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, displayedComponents: .date)
                    }
                }

                MultiSelectSection(title: "Categories", options: categories, selection: $selectedCategories)
                MultiSelectSection(title: "Airports", options: airports, selection: $selectedAirports)
                MultiSelectSection(title: "Aircraft", options: aircraft, selection: $selectedAircraft)

                Section("Archive Status") {
                    Picker("Include", selection: $archiveScope) {
                        ForEach(ArchiveReportScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        onExport(filter)
                        dismiss()
                    }
                    .disabled(!includeExpenses && !includeIncentives)
                }
            }
        }
    }

    private var filter: ReportFilter {
        ReportFilter(
            includeExpenses: includeExpenses,
            includeIncentives: includeIncentives,
            startDate: useDateRange ? min(startDate, endDate) : nil,
            endDate: useDateRange ? max(startDate, endDate) : nil,
            categories: selectedCategories,
            airports: selectedAirports,
            aircraft: selectedAircraft,
            archiveScope: archiveScope
        )
    }
}

private struct MultiSelectSection: View {
    let title: String
    let options: [String]
    @Binding var selection: Set<String>

    var body: some View {
        Section {
            if options.isEmpty {
                Text("No \(title.lowercased()) yet. All will be included.")
                    .foregroundStyle(.secondary)
            } else {
                Button(selection.isEmpty ? "All \(title)" : "Clear Selection") {
                    selection.removeAll()
                }

                ForEach(options, id: \.self) { option in
                    Button {
                        if selection.contains(option) {
                            selection.remove(option)
                        } else {
                            selection.insert(option)
                        }
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if selection.contains(option) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.tripAccent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Leave blank to include all \(title.lowercased()).")
        }
    }
}

private struct EditableOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: SettingsSheetKind
    let onSave: ([String]) -> Void

    @State private var draftOptions: [String]
    @State private var newOption = ""

    init(kind: SettingsSheetKind, options: [String], onSave: @escaping ([String]) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _draftOptions = State(initialValue: options)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(kind.addPlaceholder, text: $newOption)
                            .textInputAutocapitalization(kind.textCapitalization)

                        Button("Add") {
                            addOption()
                        }
                        .disabled(newOption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("Changing this list only changes future menu choices. Existing entries keep their saved values.")
                }

                Section(kind.title) {
                    if draftOptions.isEmpty {
                        Text("No saved options yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draftOptions.indices, id: \.self) { index in
                            HStack {
                                TextField("Option", text: Binding(
                                    get: { draftOptions[index] },
                                    set: { draftOptions[index] = $0 }
                                ))
                                .textInputAutocapitalization(kind.textCapitalization)

                                Button(role: .destructive) {
                                    draftOptions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftOptions)
                        dismiss()
                    }
                }
            }
        }
    }

    private func addOption() {
        let trimmed = newOption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if !draftOptions.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            draftOptions.append(trimmed)
        }
        newOption = ""
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
