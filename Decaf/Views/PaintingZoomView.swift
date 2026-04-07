import SwiftUI
import UIKit

// MARK: - Private UIScrollView subclass

/// UIScrollView subclass that owns the image view and handles its own layout.
/// Overriding layoutSubviews ensures the image is correctly sized and centred
/// whenever the bounds change (first layout, rotation, split-screen resize).
final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    /// Called by the coordinator when the user pulls down past the dismiss
    /// threshold while the image is at 1× zoom.
    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        addSubview(imageView)
        // alwaysBounceVertical lets the user pull the image below its natural
        // top edge, which drives the pull-to-dismiss threshold check.
        alwaysBounceVertical = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        sizeImageViewIfNeeded()
    }

    /// Fits the image view inside the scroll view's bounds (aspect-correct),
    /// resets zoom to 1×, and centres the image.
    func sizeImageViewIfNeeded() {
        guard let image = imageView.image,
              bounds.width > 0, bounds.height > 0 else { return }
        let imageAspect  = image.size.width / image.size.height
        let boundsAspect = bounds.width / bounds.height
        let size: CGSize = imageAspect > boundsAspect
            ? CGSize(width: bounds.width,  height: bounds.width  / imageAspect)
            : CGSize(width: bounds.height * imageAspect, height: bounds.height)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        if zoomScale < minimumZoomScale { zoomScale = minimumZoomScale }
        centerImageView()
    }

    /// Keeps the image centred in the scroll view when it is smaller than the
    /// bounds (i.e. at zoom levels below the point where it fills the screen).
    func centerImageView() {
        var f = imageView.frame
        f.origin.x = f.width  < bounds.width  ? (bounds.width  - f.width)  / 2 : 0
        f.origin.y = f.height < bounds.height ? (bounds.height - f.height) / 2 : 0
        imageView.frame = f
    }
}

// MARK: - UIViewRepresentable

/// Wraps ZoomScrollView in SwiftUI. UIKit handles all pinch-to-zoom and pan
/// natively via UIScrollViewDelegate. The image is loaded from the provided URL
/// using URLSession, which serves it from cache if AsyncImage already fetched it.
struct ZoomableImageScrollView: UIViewRepresentable {
    let url: URL?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ZoomScrollView {
        let sv = ZoomScrollView()
        sv.delegate                       = context.coordinator
        sv.minimumZoomScale               = 1.0
        sv.maximumZoomScale               = 4.0
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator   = false
        sv.backgroundColor                = .clear
        sv.bouncesZoom                    = true
        sv.onDismiss                      = onDismiss

        // Double-tap toggles between 1× and 3× zoom at the tap point,
        // consistent with standard iOS photo-viewing behaviour.
        let doubleTap = UITapGestureRecognizer(
            target:  context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)

        return sv
    }

    func updateUIView(_ sv: ZoomScrollView, context: Context) {
        // Keep the closure current (dismiss environment reference is stable,
        // but refreshing it on every update costs nothing).
        sv.onDismiss = onDismiss

        guard let url, context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        // Load from URLSession — the shared cache typically already holds this
        // image from AsyncImage's earlier fetch in ArtworkCard.
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                sv.imageView.image = image
                sv.sizeImageViewIfNeeded()
            }
        }.resume()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var loadedURL: URL?
        /// Guards against calling onDismiss repeatedly while the scroll view
        /// continues to report negative offsets during the dismiss animation.
        private var didDismiss = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerImageView()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Re-centre on every scroll so the image stays in the middle of
            // the scroll view when smaller than the viewport.
            (scrollView as? ZoomScrollView)?.centerImageView()

            // Pull-to-dismiss: fire once when the user drags the image more
            // than 80 pt below its natural top while at 1× zoom.
            guard !didDismiss,
                  let sv = scrollView as? ZoomScrollView,
                  scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01,
                  scrollView.contentOffset.y < -80 else { return }
            didDismiss = true
            sv.onDismiss?()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let sv = recognizer.view as? ZoomScrollView else { return }
            if sv.zoomScale > sv.minimumZoomScale {
                sv.setZoomScale(sv.minimumZoomScale, animated: true)
            } else {
                // Zoom to 3× centred on the tap point.
                let pt = recognizer.location(in: sv.imageView)
                let w  = sv.bounds.width  / 3
                let h  = sv.bounds.height / 3
                sv.zoom(
                    to: CGRect(x: pt.x - w / 2, y: pt.y - h / 2, width: w, height: h),
                    animated: true
                )
            }
        }
    }
}

// MARK: - Full-screen presentation

/// Full-screen dark overlay presenting a zoomable painting.
/// Dismissed by pulling down past 80 pt (at 1× zoom) or tapping the close button.
struct PaintingZoomView: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZoomableImageScrollView(url: url, onDismiss: { dismiss() })
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 60)
            .padding(.leading, 20)
        }
    }
}
