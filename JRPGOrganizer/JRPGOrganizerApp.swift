import SwiftUI
import SwiftData
import JRPGOrganizerFeature

@main
struct JRPGOrganizerApp: App {
    private let modelContainer: ModelContainer

    @MainActor
    init() {
        JRPGNavigationAppearance.install()
        modelContainer = Self.makeModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            let schema = Schema([
                SavedGame.self,
                WalkthroughEntry.self,
                OrganizedWalkthroughEntry.self,
                WalkthroughProgressRecord.self,
            ])
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            let storeURL = applicationSupportURL.appending(path: "default.store")
            let configuration = ModelConfiguration(
                "JRPGOrganizer",
                schema: schema,
                url: storeURL
            )
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unresolved error loading model container: \(error)")
        }
    }
}
