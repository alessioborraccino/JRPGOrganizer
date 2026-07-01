import Foundation
import SwiftData

@Model
public final class WalkthroughEntry {
    @Attribute(.unique) public var id: UUID
    public var sortOrder: Int
    public var stepNumber: Int?
    public var chapterTitle: String
    public var guideSection: String
    public var sourceURL: String
    public var location: String
    public var title: String
    public var body: String
    public var isCompleted: Bool
    public var imageURL: String?
    public var imageCaption: String?

    public var entryKindRaw: String
    public var modeRaw: String
    public var calloutKindRaw: String?

    public var game: SavedGame?

    public init(
        id: UUID = UUID(),
        sortOrder: Int,
        stepNumber: Int? = nil,
        chapterTitle: String,
        guideSection: String,
        sourceURL: String,
        location: String,
        entryKind: WalkthroughEntryKind,
        mode: WalkthroughEntryMode,
        calloutKind: WalkthroughCalloutKind? = nil,
        title: String,
        body: String,
        isCompleted: Bool = false,
        imageURL: String? = nil,
        imageCaption: String? = nil
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.stepNumber = stepNumber
        self.chapterTitle = chapterTitle
        self.guideSection = guideSection
        self.sourceURL = sourceURL
        self.location = location
        self.entryKindRaw = entryKind.rawValue
        self.modeRaw = mode.rawValue
        self.calloutKindRaw = calloutKind?.rawValue
        self.title = title
        self.body = body
        self.isCompleted = isCompleted
        self.imageURL = imageURL
        self.imageCaption = imageCaption
    }

    public var entryKind: WalkthroughEntryKind {
        get { WalkthroughEntryKind(rawValue: entryKindRaw) ?? .task }
        set { entryKindRaw = newValue.rawValue }
    }

    public var mode: WalkthroughEntryMode {
        get { WalkthroughEntryMode(rawValue: modeRaw) ?? .walkthrough }
        set { modeRaw = newValue.rawValue }
    }

    public var calloutKind: WalkthroughCalloutKind? {
        get {
            guard let calloutKindRaw else { return nil }
            return WalkthroughCalloutKind(rawValue: calloutKindRaw)
        }
        set { calloutKindRaw = newValue?.rawValue }
    }

    public var progressSignature: String {
        [
            sourceURL,
            entryKindRaw,
            modeRaw,
            title,
            body,
            imageURL ?? "",
        ].joined(separator: "|")
    }
}
