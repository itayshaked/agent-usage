import SwiftUI

@main
struct CursorUsageBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.warningLevel.symbol)
                Text(store.menuBarTitle)
            }
            .foregroundStyle(store.warningLevel.tint)
        }
        .menuBarExtraStyle(.window)
    }
}
