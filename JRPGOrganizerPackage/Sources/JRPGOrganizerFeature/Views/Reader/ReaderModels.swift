import Foundation

enum ChapterBookmarkPosition {
    case start
    case end
}

struct ChapterSlice: Sendable {
    let title: String
    let subtitle: String?
    let sortOrder: Int
    var rows: [TimelineRow]
}

struct TableOfContentsItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let sortOrder: Int
    let targetRowID: String
}

struct EntryProgressLookup {
    let gameID: UUID
    let layer: WalkthroughReaderLayer
    private let stateByRecordID: [String: EntryProgressState]

    init(gameID: UUID, layer: WalkthroughReaderLayer, records: [WalkthroughProgressRecord]) {
        self.gameID = gameID
        self.layer = layer
        stateByRecordID = records.reduce(into: [:]) { states, record in
            guard record.readerLayer == layer else { return }
            states[record.id] = EntryProgressState(
                entrySignature: record.entrySignature,
                isCompleted: record.isCompleted
            )
        }
    }

    var layerRawValue: String {
        layer.rawValue
    }

    func isCompleted(entryID: UUID, signature: String, fallback: Bool) -> Bool {
        let recordID = WalkthroughProgressRecord.makeID(
            gameID: gameID,
            readerLayerRaw: layer.rawValue,
            entryID: entryID
        )
        guard let state = stateByRecordID[recordID], state.entrySignature == signature else {
            return fallback
        }
        return state.isCompleted
    }
}

struct EntryProgressState {
    let entrySignature: String
    let isCompleted: Bool
}

struct EntrySnapshot: Identifiable, Sendable {
    let id: UUID
    let readerLayerRaw: String
    let sortOrder: Int
    let stepNumber: Int?
    let chapterTitle: String
    let guideSection: String
    let sourceURL: String
    let location: String
    let entryKind: WalkthroughEntryKind
    let mode: WalkthroughEntryMode
    let calloutKind: WalkthroughCalloutKind?
    let contentKind: OrganizedContentKind?
    let title: String
    let body: String
    let imageURL: String?
    let imageCaption: String?
    let previewBody: String
    let isBodyExpandable: Bool
    var isCompleted: Bool
    let progressSignature: String

    init(entry: WalkthroughEntry, progressLookup: EntryProgressLookup) {
        let signature = entry.progressSignature
        id = entry.id
        readerLayerRaw = progressLookup.layerRawValue
        sortOrder = entry.sortOrder
        stepNumber = entry.stepNumber
        chapterTitle = Self.readerChapterTitle(
            sourceURL: entry.sourceURL,
            chapterTitle: entry.chapterTitle,
            guideSection: entry.guideSection,
            location: entry.location
        )
        guideSection = entry.guideSection
        sourceURL = entry.sourceURL
        location = entry.location
        entryKind = entry.entryKind
        mode = entry.mode
        calloutKind = entry.calloutKind
        contentKind = nil
        title = entry.title
        body = entry.body
        imageURL = entry.imageURL
        imageCaption = entry.imageCaption
        isBodyExpandable = !GuideBodyMarkup.hasStructuredMarkup(in: entry.body) && entry.body.count > Self.bodyPreviewLimit
        if isBodyExpandable {
            previewBody = String(entry.body.prefix(Self.bodyPreviewLimit)) + "..."
        } else {
            previewBody = entry.body
        }
        progressSignature = signature
        isCompleted = progressLookup.isCompleted(
            entryID: entry.id,
            signature: signature,
            fallback: entry.isCompleted
        )
    }

    init(entry: OrganizedWalkthroughEntry, progressLookup: EntryProgressLookup) {
        let signature = entry.progressSignature
        id = entry.id
        readerLayerRaw = progressLookup.layerRawValue
        sortOrder = entry.sortOrder
        stepNumber = nil
        chapterTitle = Self.readerChapterTitle(
            sourceURL: entry.sourceURL,
            chapterTitle: entry.chapterTitle,
            guideSection: entry.guideSection,
            location: entry.location
        )
        guideSection = entry.guideSection
        sourceURL = entry.sourceURL
        location = entry.location
        entryKind = entry.entryKind
        mode = entry.mode
        calloutKind = entry.calloutKind
        contentKind = entry.contentKind
        title = entry.title
        body = entry.body
        imageURL = entry.imageURL
        imageCaption = entry.imageCaption
        isBodyExpandable = !GuideBodyMarkup.hasStructuredMarkup(in: entry.body) && entry.body.count > Self.bodyPreviewLimit
        if isBodyExpandable {
            previewBody = String(entry.body.prefix(Self.bodyPreviewLimit)) + "..."
        } else {
            previewBody = entry.body
        }
        progressSignature = signature
        isCompleted = progressLookup.isCompleted(
            entryID: entry.id,
            signature: signature,
            fallback: entry.isCompleted
        )
    }

    private static let bodyPreviewLimit = 360

    private static func readerChapterTitle(
        sourceURL: String,
        chapterTitle: String,
        guideSection: String,
        location: String
    ) -> String {
        guard sourceURL.contains("/faqs/") else {
            return chapterTitle
        }

        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty,
              trimmedLocation != guideSection,
              chapterTitle.localizedCaseInsensitiveContains("FAQ") else {
            return chapterTitle
        }
        return trimmedLocation
    }
}

struct GuideImagePresentation: Identifiable {
    let id: String
    let url: URL
    let kind: WalkthroughCalloutKind

    init(url: URL, kind: WalkthroughCalloutKind) {
        self.url = url
        self.kind = kind
        id = "\(kind.rawValue)-\(url.absoluteString)"
    }
}

enum TimelineRow: Identifiable, Sendable {
    case chapterHeader(title: String, section: String, sortOrder: Int)
    case locationHeader(title: String, sortOrder: Int)
    case entry(EntrySnapshot)

    var id: String {
        switch self {
        case .chapterHeader(let title, let section, let sortOrder):
            "chapter-\(sortOrder)-\(section)-\(title)"
        case .locationHeader(let title, let sortOrder):
            "location-\(sortOrder)-\(title)"
        case .entry(let entry):
            "entry-\(entry.id.uuidString)"
        }
    }
}
