import SwiftUI

struct TableOfContentsView: View {
    let items: [TableOfContentsItem]
    let currentSortOrder: Int?
    let onSelect: (TableOfContentsItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        let isCurrent = item.sortOrder == currentSortOrder
                        Button {
                            dismiss()
                            onSelect(item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isCurrent ? "bookmark.fill" : "book.closed")
                                    .foregroundStyle(JRPGTheme.accent)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(JRPGTheme.primaryText)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(JRPGTheme.secondaryText)
                                    }
                                }

                                Spacer()

                                if isCurrent {
                                    Label("Current", systemImage: "bookmark.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(JRPGTheme.accent)
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 8)
                                        .background(JRPGTheme.navigationBackground, in: .capsule)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(JRPGTheme.secondaryText)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isCurrent ? JRPGTheme.locationHeaderBackground : JRPGTheme.cardBackground,
                                in: .rect(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isCurrent ? JRPGTheme.accent : JRPGTheme.cardBorder, lineWidth: isCurrent ? 1.5 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(isCurrent ? "Current chapter" : "Open chapter")
                    }
                }
                .padding()
            }
            .background(JRPGTheme.appBackground.ignoresSafeArea())
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .tint(JRPGTheme.accent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
