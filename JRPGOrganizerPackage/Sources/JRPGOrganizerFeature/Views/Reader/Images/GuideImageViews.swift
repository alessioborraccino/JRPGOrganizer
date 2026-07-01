import SwiftUI
@preconcurrency import UIKit

struct GuideImageViewer: View {
    let presentation: GuideImagePresentation
    @Environment(\.dismiss) private var dismiss
    @State private var phase: GuideImagePhase = .idle

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            switch phase {
            case .idle, .loading:
                ProgressView()
                    .tint(.white)
            case .loaded(let image):
                ZoomableImageView(image: image)
                    .ignoresSafeArea()
            case .failed:
                Label("Image Unavailable", systemImage: "photo")
                    .font(.headline)
                    .foregroundStyle(.white.secondary)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
            .accessibilityLabel("Close image")
        }
        .task(id: presentation.id) {
            await loadImage()
        }
    }

    private var maxPixelSize: Int {
        presentation.kind == .map ? 2_600 : 2_000
    }

    @MainActor
    private func loadImage() async {
        guard case .idle = phase else { return }
        phase = .loading

        do {
            let imageData = try await GuideImagePipeline.shared.imageData(for: presentation.url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: imageData) else {
                phase = .failed
                return
            }
            phase = .loaded(image)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}

struct GuideImageThumbnail: View {
    let url: URL
    let kind: WalkthroughCalloutKind

    @State private var phase: GuideImagePhase = .idle

    var body: some View {
        imageContainer
            .task(id: url) {
                await loadImage()
            }
    }

    private var thumbnailHeight: CGFloat {
        kind == .map ? 220 : 180
    }

    private var maxPixelSize: Int {
        kind == .map ? 900 : 720
    }

    @ViewBuilder
    private var imageContainer: some View {
        ZStack {
            JRPGTheme.recessedBackground

            switch phase {
            case .idle, .loading:
                ProgressView()
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: thumbnailHeight)
            case .failed:
                Label("Image Unavailable", systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(JRPGTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: thumbnailHeight)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(Color.black.opacity(0.58), in: .circle)
                .padding(8)
        }
    }

    @MainActor
    private func loadImage() async {
        guard case .idle = phase else { return }
        phase = .loading

        do {
            let imageData = try await GuideImagePipeline.shared.imageData(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: imageData) else {
                phase = .failed
                return
            }
            phase = .loaded(image)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }
}

enum GuideImagePhase {
    case idle
    case loading
    case loaded(UIImage)
    case failed
}
