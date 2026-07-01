import SwiftUI

struct ChapterHeaderRow: View {
    let title: String
    let section: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(JRPGTheme.secondaryText)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(JRPGTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(JRPGTheme.cardBackground, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(JRPGTheme.cardBorder, lineWidth: 1)
        }
    }
}

struct LocationHeaderRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JRPGTheme.accent)
                .frame(width: 24, height: 24)
                .background(JRPGTheme.navigationBackground, in: .circle)

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(JRPGTheme.primaryText)
                .lineLimit(2)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(JRPGTheme.locationHeaderBackground, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(JRPGTheme.cardBorder, lineWidth: 1)
        }
    }
}

struct EntryRow: View {
    let entry: EntrySnapshot
    let displayState: EntryDisplayState
    let onToggleTask: () -> Void
    let onToggleCalloutExpansion: () -> Void
    let onOpenImage: (URL, WalkthroughCalloutKind) -> Void

    var body: some View {
        Group {
            switch entry.entryKind {
            case .task:
                taskRow
            case .callout:
                calloutRow
            }
        }
        .redacted(reason: displayState.isSpoiled ? .placeholder : [])
        .opacity(displayState.isSpoiled ? 0.58 : 1)
        .overlay {
            if displayState.isSpoiled {
                SpoilerShield()
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .allowsHitTesting(!displayState.isSpoiled)
        .accessibilityHidden(displayState.isSpoiled)
        .cardSurface()
        .overlay(alignment: .leading) {
            if displayState.isCurrent {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(JRPGTheme.accent)
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)
            }
        }
        .overlay {
            if displayState.isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(JRPGTheme.accent, lineWidth: 1.75)
                    .transition(.opacity)
            }
        }
        .animation(readerProgressRevealAnimation, value: displayState.isSpoiled)
        .animation(readerProgressRevealAnimation, value: displayState.isCurrent)
    }

    private var taskRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    if let stepNumber = entry.stepNumber {
                        Text("Step \(stepNumber)")
                    } else {
                        Label("Bookmark Step", systemImage: "bookmark")
                    }
                }
                .font(.caption)
                .foregroundStyle(JRPGTheme.accent)

                Spacer(minLength: 8)

                if displayState.isCurrent {
                    Label("Current", systemImage: "bookmark.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JRPGTheme.accent)
                }
            }

            ReaderBodyText(
                text: visibleBody,
                font: .body,
                foregroundColor: JRPGTheme.primaryText,
                isStruckThrough: false
            )

            expansionButton

            if !displayState.isCurrent {
                HStack {
                    Spacer(minLength: 12)
                    Button(action: onToggleTask) {
                        Label("Set Current", systemImage: "bookmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Set this step as current")
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .animation(readerExpansionAnimation, value: displayState.isExpanded)
    }

    private var calloutRow: some View {
        let kind = effectiveCalloutKind
        return VStack(alignment: .leading, spacing: 8) {
            Label(kind.label, systemImage: kind.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind.tint)

            if usesStructuredDetails(for: kind) {
                CalloutDetailsView(kind: kind, title: entry.title, details: visibleBody)
                expansionButton
            } else {
                if let title = visibleCalloutTitle(for: kind) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }

                imageView(for: kind)

                if !isMediaCallout(kind), !entry.body.isEmpty {
                    ReaderBodyText(
                        text: visibleBody,
                        font: .subheadline,
                        foregroundColor: JRPGTheme.primaryText
                    )
                    expansionButton
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.background, in: .rect(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(calloutBorder(for: kind), lineWidth: 1.25)
        }
        .contentShape(.rect)
        .onTapGesture {
            handleMediaTap(for: kind)
        }
        .padding(.vertical, 2)
        .animation(readerExpansionAnimation, value: displayState.isExpanded)
    }

    private var visibleBody: String {
        entry.isBodyExpandable && !displayState.isExpanded ? entry.previewBody : entry.body
    }

    @ViewBuilder
    private var expansionButton: some View {
        if entry.isBodyExpandable {
            Button(action: onToggleCalloutExpansion) {
                Label(
                    displayState.isExpanded ? "Show Less" : "Show More",
                    systemImage: displayState.isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                )
                .contentTransition(.opacity)
            }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(JRPGTheme.accent)
        }
    }

    private func isMediaCallout(_ kind: WalkthroughCalloutKind) -> Bool {
        entry.imageURL != nil && (kind == .image || kind == .map)
    }

    private func usesStructuredDetails(for kind: WalkthroughCalloutKind) -> Bool {
        switch kind {
        case .loot, .enemy, .shop, .quest:
            true
        case .important, .tip, .battle, .version, .warning, .reference, .sourceSpoiler, .image, .map:
            false
        }
    }

    private var effectiveCalloutKind: WalkthroughCalloutKind {
        let kind = entry.calloutKind ?? .reference
        guard kind == .enemy, !looksLikeEnemyCallout else {
            return kind
        }
        return .reference
    }

    private var looksLikeEnemyCallout: Bool {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !isGenericImportedTitle(title),
           title == "enemy" || title == "enemies" || title.hasPrefix("enemies ") {
            return true
        }

        return startsWithLabel(body, labels: ["enemy", "enemies", "enemies to encounter", "monsters"])
            || body.contains("enemies:")
            || body.contains("enemies -")
            || body.contains("enemies to encounter:")
    }

    private func visibleCalloutTitle(for kind: WalkthroughCalloutKind) -> String? {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title != kind.label,
              !isGenericImportedTitle(title.lowercased()) else {
            return nil
        }
        return title
    }

    private func isGenericImportedTitle(_ title: String) -> Bool {
        title == "story step"
            || title == "completion"
            || title == "reference"
            || title == "checklist"
    }

    private func startsWithLabel(_ text: String, labels: [String]) -> Bool {
        labels.contains { label in
            text == label
                || text.hasPrefix("\(label):")
                || text.hasPrefix("\(label) -")
                || text.hasPrefix("\(label) ")
        }
    }

    private func calloutBorder(for kind: WalkthroughCalloutKind) -> Color {
        JRPGTheme.calloutBorder(for: kind)
    }

    private var mediaURL: URL? {
        guard let imageURL = entry.imageURL else { return nil }
        return URL(string: imageURL)
    }

    private func handleMediaTap(for kind: WalkthroughCalloutKind) {
        guard isMediaCallout(kind), let mediaURL else { return }
        if displayState.isExpanded {
            onOpenImage(mediaURL, kind)
        } else {
            onToggleCalloutExpansion()
        }
    }

    @ViewBuilder
    private func imageView(for kind: WalkthroughCalloutKind) -> some View {
        if let imageURL = entry.imageURL, let url = URL(string: imageURL) {
            if displayState.isExpanded {
                GuideImageThumbnail(url: url, kind: kind)
                    .accessibilityLabel("Enlarge \(kind.label)")
            } else {
                HStack(spacing: 10) {
                    Image(systemName: kind.systemImage)
                        .font(.headline)
                        .foregroundStyle(kind.tint)
                    Text("Show \(kind.label)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JRPGTheme.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(JRPGTheme.recessedBackground, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Show \(kind.label)")
            }

            if !isMediaCallout(kind), let imageCaption = entry.imageCaption, !imageCaption.isEmpty, imageCaption != entry.body {
                Text(imageCaption)
                    .font(.caption)
                    .foregroundStyle(JRPGTheme.secondaryText)
            }
        }
    }
}

struct SpoilerShield: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text("Future Content")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(JRPGTheme.primaryText)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(JRPGTheme.cardBackground.opacity(0.92), in: .capsule)
        .overlay {
            Capsule()
                .stroke(JRPGTheme.cardBorder, lineWidth: 1)
        }
    }
}

struct CalloutDetailsView: View {
    let kind: WalkthroughCalloutKind
    let title: String
    let details: String

    private var fallbackText: String {
        guard details.isEmpty else { return details }

        switch kind {
        case .loot:
            return "No loot details were imported for this row."
        case .enemy:
            return "No enemy details were imported for this row."
        case .shop:
            return "No shop details were imported for this row."
        case .quest:
            return "No quest details were imported for this row."
        case .important, .tip, .battle, .version, .warning, .reference, .sourceSpoiler, .image, .map:
            return ""
        }
    }

    var body: some View {
        let displayText = fallbackText
        let sourceBlocks = GuideBodyMarkup.blocks(from: displayText)
        let hasSourceStructure = sourceBlocks.contains { block in
            switch block {
            case .table, .sourceList:
                return true
            case .paragraph:
                return false
            }
        }
        let listItems = hasSourceStructure ? [] : displayText.readerListItems()

        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty, title != kind.label {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            Group {
                if hasSourceStructure {
                    ReaderSourceBlocksView(
                        blocks: sourceBlocks,
                        font: .callout.weight(.medium),
                        foregroundColor: JRPGTheme.primaryText,
                        paragraphSpacing: 6
                    )
                } else if listItems.isEmpty {
                    ReaderBodyText(
                        text: fallbackText,
                        font: .callout.weight(.medium),
                        foregroundColor: JRPGTheme.primaryText,
                        paragraphSpacing: 6
                    )
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(listItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text("•")
                                    .font(.callout.weight(.bold))
                                    .foregroundStyle(JRPGTheme.secondaryText)
                                Text(item)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(JRPGTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(JRPGTheme.recessedBackground, in: .rect(cornerRadius: 7, style: .continuous))
        }
    }
}
