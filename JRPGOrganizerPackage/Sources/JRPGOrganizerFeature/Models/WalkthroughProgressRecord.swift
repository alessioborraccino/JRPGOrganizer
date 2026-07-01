import Foundation
import SwiftData

@Model
public final class WalkthroughProgressRecord {
    @Attribute(.unique) public var id: String
    public var gameID: UUID
    public var readerLayerRaw: String
    public var entryID: UUID
    public var entrySignature: String
    public var isCompleted: Bool
    public var updatedAt: Date

    public var game: SavedGame?

    public init(
        id: String? = nil,
        gameID: UUID,
        readerLayer: WalkthroughReaderLayer,
        entryID: UUID,
        entrySignature: String,
        isCompleted: Bool,
        updatedAt: Date = .now
    ) {
        self.id = id ?? Self.makeID(gameID: gameID, readerLayerRaw: readerLayer.rawValue, entryID: entryID)
        self.gameID = gameID
        self.readerLayerRaw = readerLayer.rawValue
        self.entryID = entryID
        self.entrySignature = entrySignature
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }

    public var readerLayer: WalkthroughReaderLayer {
        get { WalkthroughReaderLayer(rawValue: readerLayerRaw) ?? .raw }
        set { readerLayerRaw = newValue.rawValue }
    }

    public static func makeID(
        gameID: UUID,
        readerLayerRaw: String,
        entryID: UUID
    ) -> String {
        "\(gameID.uuidString)|\(readerLayerRaw)|\(entryID.uuidString)"
    }
}
