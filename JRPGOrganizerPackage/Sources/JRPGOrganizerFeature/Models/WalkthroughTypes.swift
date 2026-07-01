import SwiftUI

public enum WalkthroughEntryKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case task
    case callout

    public var id: String { rawValue }
}

public enum WalkthroughEntryMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case walkthrough
    case completion
    case reference

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .walkthrough:
            "Story"
        case .completion:
            "Completion"
        case .reference:
            "Reference"
        }
    }

    public var systemImage: String {
        switch self {
        case .walkthrough:
            "figure.walk"
        case .completion:
            "checklist"
        case .reference:
            "book"
        }
    }

    public var tint: Color {
        switch self {
        case .walkthrough:
            JRPGTheme.dragonQuestAccent
        case .completion:
            JRPGTheme.calloutTint(for: .loot)
        case .reference:
            JRPGTheme.secondaryText
        }
    }

    public var background: Color {
        JRPGTheme.modeBackground(for: self)
    }
}

public enum WalkthroughReaderLayer: String, Codable, Sendable {
    case raw
    case organized
}

public enum WalkthroughCalloutKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case important
    case tip
    case battle
    case version
    case warning
    case loot
    case enemy
    case shop
    case quest
    case reference
    case sourceSpoiler
    case image
    case map

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .important:
            "Important"
        case .tip:
            "Tip"
        case .battle:
            "Battle"
        case .version:
            "Definitive Edition"
        case .warning:
            "Warning"
        case .loot:
            "Area Loot"
        case .enemy:
            "Enemies"
        case .shop:
            "Shop"
        case .quest:
            "Quest"
        case .reference:
            "Reference"
        case .sourceSpoiler:
            "Source Spoiler"
        case .image:
            "Image"
        case .map:
            "Map"
        }
    }

    public var systemImage: String {
        switch self {
        case .important:
            "info.circle"
        case .tip:
            "lightbulb"
        case .battle:
            "shield"
        case .version:
            "switch.2"
        case .warning:
            "exclamationmark.triangle"
        case .loot:
            "shippingbox"
        case .enemy:
            "list.bullet.clipboard"
        case .shop:
            "cart"
        case .quest:
            "flag"
        case .reference:
            "book"
        case .sourceSpoiler:
            "eye.slash"
        case .image:
            "photo"
        case .map:
            "map"
        }
    }

    public var tint: Color {
        JRPGTheme.calloutTint(for: self)
    }

    public var background: Color {
        JRPGTheme.calloutBackground(self)
    }
}

public enum OrganizedContentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case storyStep
    case loot
    case enemy
    case boss
    case shop
    case sidequest
    case note
    case image
    case map

    public var id: String { rawValue }

    public var calloutKind: WalkthroughCalloutKind? {
        switch self {
        case .storyStep:
            nil
        case .loot:
            .loot
        case .enemy:
            .enemy
        case .boss:
            .battle
        case .shop:
            .shop
        case .sidequest:
            .quest
        case .note:
            .reference
        case .image:
            .image
        case .map:
            .map
        }
    }

    public var defaultMode: WalkthroughEntryMode {
        switch self {
        case .storyStep, .boss, .sidequest:
            .walkthrough
        case .loot, .shop:
            .completion
        case .enemy, .note, .image, .map:
            .reference
        }
    }
}
