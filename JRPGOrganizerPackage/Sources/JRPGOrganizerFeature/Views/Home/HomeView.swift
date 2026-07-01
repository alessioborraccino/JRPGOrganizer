import SwiftData
import SwiftUI

public struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedGame.dateDownloaded, order: .reverse) private var savedGames: [SavedGame]
    @State private var importer = GuideImporter()
    @State private var organizer = GuideAIOrganizer()
    @State private var gamePendingDeletion: SavedGame?
    @State private var deletionErrorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ForEach(GuideDefinition.all) { guide in
                    guideCard(guide)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteSwipeAction(for: guide)
                        }
                        .contextMenu {
                            guideCardContextMenu(for: guide)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 8)
            .background(JRPGTheme.appBackground.ignoresSafeArea())
            .navigationTitle("JRPG Organizer")
            .navigationBarTitleDisplayMode(.inline)
            .tint(JRPGTheme.accent)
            .alert("Import Failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    importer.clearError()
                }
            } message: {
                Text(importer.errorMessage ?? "The guide could not be imported.")
            }
            .alert("On-Device Organization Failed", isPresented: organizerErrorBinding) {
                Button("OK", role: .cancel) {
                    organizer.clearError()
                }
            } message: {
                Text(organizer.errorMessage ?? "The guide could not be organized.")
            }
            .confirmationDialog(
                "Delete Walkthrough?",
                isPresented: deletionConfirmationBinding,
                titleVisibility: .visible
            ) {
                if let gamePendingDeletion {
                    Button("Delete Guide", role: .destructive) {
                        deleteWalkthrough(gamePendingDeletion)
                    }
                }

                Button("Cancel", role: .cancel) {
                    gamePendingDeletion = nil
                }
            } message: {
                Text("This removes the imported guide data and reader progress from this device. You can import the guide again later.")
            }
            .alert("Delete Failed", isPresented: deletionErrorBinding) {
                Button("OK", role: .cancel) {
                    deletionErrorMessage = nil
                }
            } message: {
                Text(deletionErrorMessage ?? "The walkthrough could not be deleted.")
            }
            .task {
                await backfillProgressCachesIfNeeded()
            }
        }
    }

    private func importedGame(for guide: GuideDefinition) -> SavedGame? {
        savedGames.first { $0.rootURL == guide.rootURLString }
    }

    private func guideCard(_ guide: GuideDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: guide.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint(for: guide))

                VStack(alignment: .leading, spacing: 4) {
                    Text(guide.title)
                        .font(.headline)
                    Text(guide.sourceDescription)
                        .font(.subheadline)
                        .foregroundStyle(JRPGTheme.secondaryText)
                }

                Spacer()
            }

            let importedGame = importedGame(for: guide)
            if let importedGame {
                ProgressView(value: importedGame.completionProgress)
                    .tint(JRPGTheme.success)

                Text("\(importedGame.completedTaskCount) of \(importedGame.totalTaskCount) checklist steps complete")
                    .font(.caption)
                    .foregroundStyle(JRPGTheme.secondaryText)

                HStack {
                    NavigationLink {
                        GuideReaderView(game: importedGame)
                    } label: {
                        Label("Resume Guide", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(JRPGTheme.accentFill)

                    Button {
                        Task { @MainActor in
                            await importer.importGuide(guide, into: modelContext)
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(importer.isImporting)
                }

                if guide.supportsReaderOrganization {
                    Button {
                        Task { @MainActor in
                            await organizer.organize(importedGame, modelContainer: modelContext.container)
                        }
                    } label: {
                        Label(
                            importedGame.hasOrganizedEntries ? "Reorganize Reader" : "Organize Reader",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(importer.isImporting || organizer.isOrganizing)

                    if importedGame.hasOrganizedEntries {
                        Text("Organized reader available. AI is used only for messy FAQ chunks.")
                            .font(.caption)
                            .foregroundStyle(JRPGTheme.secondaryText)
                    }
                }
            } else {
                Text(importPrompt(for: guide))
                    .font(.subheadline)
                    .foregroundStyle(JRPGTheme.secondaryText)

                Button {
                    Task { @MainActor in
                        await importer.importGuide(guide, into: modelContext)
                    }
                } label: {
                    Label("Import Guide", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(JRPGTheme.accentFill)
                .disabled(importer.isImporting)
            }

            if importer.isImporting(guide) {
                GuideOperationProgressView(
                    statusText: importer.statusMessage ?? "Importing guide...",
                    progress: importer.importProgress,
                    tint: tint(for: guide)
                )
            }

            if let importedGame, organizer.isOrganizing(importedGame) {
                GuideOperationProgressView(
                    statusText: organizer.statusMessage ?? "Organizing on device...",
                    progress: organizer.organizationProgress,
                    tint: JRPGTheme.accent
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func deleteSwipeAction(for guide: GuideDefinition) -> some View {
        if let importedGame = importedGame(for: guide) {
            Button(role: .destructive) {
                gamePendingDeletion = importedGame
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!canDelete(guide, game: importedGame))
        }
    }

    @ViewBuilder
    private func guideCardContextMenu(for guide: GuideDefinition) -> some View {
        if let importedGame = importedGame(for: guide) {
            Button(role: .destructive) {
                gamePendingDeletion = importedGame
            } label: {
                Label("Delete Walkthrough", systemImage: "trash")
            }
            .disabled(!canDelete(guide, game: importedGame))
        }
    }

    private func canDelete(_ guide: GuideDefinition, game: SavedGame) -> Bool {
        !importer.isImporting && !importer.isImporting(guide) && !organizer.isOrganizing(game)
    }

    private func deleteWalkthrough(_ game: SavedGame) {
        guard !importer.isImporting, !organizer.isOrganizing(game) else {
            gamePendingDeletion = nil
            return
        }

        do {
            modelContext.delete(game)
            try modelContext.save()
            gamePendingDeletion = nil
        } catch {
            modelContext.rollback()
            deletionErrorMessage = error.localizedDescription
            gamePendingDeletion = nil
        }
    }

    private func importPrompt(for guide: GuideDefinition) -> String {
        switch guide.importKind {
        case .dragonQuestXIWalkthrough:
            "Import the chronological walkthrough with inline info boxes and maps."
        case .neoseekerFAQWalkthrough:
            "Import the original HTML FAQ/Walkthrough."
        }
    }

    private func tint(for guide: GuideDefinition) -> Color {
        switch guide.id {
        case GuideDefinition.finalFantasyVII.id:
            JRPGTheme.finalFantasyAccent
        default:
            JRPGTheme.dragonQuestAccent
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            importer.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                importer.clearError()
            }
        }
    }

    private var organizerErrorBinding: Binding<Bool> {
        Binding {
            organizer.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                organizer.clearError()
            }
        }
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding {
            gamePendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                gamePendingDeletion = nil
            }
        }
    }

    private var deletionErrorBinding: Binding<Bool> {
        Binding {
            deletionErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                deletionErrorMessage = nil
            }
        }
    }

    private func backfillProgressCachesIfNeeded() async {
        let service = ProgressCacheBackfillService(modelContainer: modelContext.container)
        try? await service.backfillIfNeeded()
    }

}

private struct GuideOperationProgressView: View {
    let statusText: String
    let progress: Double
    let tint: Color

    private var boundedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JRPGTheme.primaryText)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(boundedProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(JRPGTheme.secondaryText)
            }

            ProgressView(value: boundedProgress)
                .tint(tint)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}
