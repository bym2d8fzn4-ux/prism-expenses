import SwiftUI

@main
struct TripLedgerApp: App {
    @StateObject private var store = ExpenseStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.load()
                }
        }
    }
}
