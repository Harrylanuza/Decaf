import SwiftUI
import SwiftData

@main
struct DecafApp: App {
    let container: ModelContainer
    // @State keeps a single NetworkMonitor instance alive across SwiftUI's
    // body re-evaluations of the App struct, which is a value type.
    @State private var network = NetworkMonitor()

    init() {
        do {
            container = try ModelContainer(for: FavoriteItem.self)
        } catch {
            // Persistent store could not be created (e.g. corrupted on-disk database,
            // out of disk space, or a failed schema migration after an update).
            // Fall back to an in-memory store so the app remains usable; the user
            // loses their saved favorites for this session but the app does not crash.
            do {
                container = try ModelContainer(
                    for: FavoriteItem.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                // If even an in-memory container fails, there is nothing safe to do.
                fatalError("SwiftData could not be initialised: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .preferredColorScheme(.light)
                .environment(network)
        }
    }
}
