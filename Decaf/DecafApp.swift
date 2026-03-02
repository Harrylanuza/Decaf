import SwiftUI
import SwiftData

@main
struct DecafApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: FavoriteItem.self)
                .preferredColorScheme(.light)
        }
    }
}
