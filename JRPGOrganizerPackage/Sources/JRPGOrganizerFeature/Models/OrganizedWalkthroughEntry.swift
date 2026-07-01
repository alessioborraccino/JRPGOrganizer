import Foundation
import SwiftData

@Model
public final class OrganizedWalkthroughEntry {
    public static let currentOrganizerVersion = 3

    @Attribute(.unique) public var id: UUID
    public var sortOrder: Int
    public var chapterTitle: String
    public var guideSection: String
    public var sourceURL: String
    public var location: String
    public var title: String
    public var body: String
    public var isCompleted: Bool
    public var sourceEntryIDsJSON: String
    public var organizerVersion: Int
    public var imageURL: String?
    public var imageCaption: String?

    public var entryKindRaw: String
    public var contentKindRaw: String

    public var game: SavedGame?

    public init(
        id: UUID = UUID(),
        sortOrder: Int,
        chapterTitle: String,
        guideSection: String,
        sourceURL: String,
        location: String,
        entryKind: WalkthroughEntryKind,
        contentKind: OrganizedContentKind,
        title: String,
        body: String,
        isCompleted: Bool = false,
        sourceEntryIDsJSON: String,
        organizerVersion: Int = OrganizedWalkthroughEntry.currentOrganizerVersion,
        imageURL: String? = nil,
        imageCaption: String? = nil
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.chapterTitle = chapterTitle
        self.guideSection = guideSection
        self.sourceURL = sourceURL
        self.location = location
        self.entryKindRaw = entryKind.rawValue
        self.contentKindRaw = contentKind.rawValue
        self.title = title
        self.body = body
        self.isCompleted = isCompleted
        self.sourceEntryIDsJSON = sourceEntryIDsJSON
        self.organizerVersion = organizerVersion
        self.imageURL = imageURL
        self.imageCaption = imageCaption
    }

    public var entryKind: WalkthroughEntryKind {
        get { WalkthroughEntryKind(rawValue: entryKindRaw) ?? .callout }
        set { entryKindRaw = newValue.rawValue }
    }

    public var contentKind: OrganizedContentKind {
        get { OrganizedContentKind(rawValue: contentKindRaw) ?? .note }
        set { contentKindRaw = newValue.rawValue }
    }

    public var mode: WalkthroughEntryMode {
        contentKind.defaultMode
    }

    public var calloutKind: WalkthroughCalloutKind? {
        contentKind.calloutKind
    }

    public var progressSignature: String {
        [
            "\(organizerVersion)",
            sourceEntryIDsJSON,
            entryKindRaw,
            contentKindRaw,
            title,
            body,
            imageURL ?? "",
        ].joined(separator: "|")
    }
}
