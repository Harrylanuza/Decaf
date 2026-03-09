import SwiftUI
import SwiftData

struct ArtworkCard: View {
    let artwork: Artwork
    /// Called once when the artwork's image fails to load. The feed uses this
    /// to silently remove the card so the user never sees a broken placeholder.
    var onImageFailure: (() -> Void)? = nil
    // Double-tap save confirmation state
    @State private var cupOpacity: Double = 0
    @State private var cupScale: CGFloat = 0.75
    @State private var cupOffset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    @Environment(\.modelContext) private var context
    @Query private var matches: [FavoriteItem]

    init(artwork: Artwork) {
        self.artwork = artwork
        let id = artwork.id
        _matches = Query(filter: #Predicate<FavoriteItem> { $0.artworkID == id })
    }

    var body: some View {
        // GeometryReader at the card root locks the total card dimensions so
        // neither image-loading phase transitions nor variable-length text can
        // ever alter the card's layout footprint in the scroll view.
        GeometryReader { geo in
            VStack(spacing: 0) {
                image(topInset: geo.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Overlay anchored to the bottom of the image slot places the
                    // buttons just above the hairline that divides image from caption.
                    // No safe-area arithmetic needed — the image slot boundary is the
                    // natural anchor, and the caption below is a separate view.
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 0) {
                            ShareButton(artwork: artwork)
                            Spacer()
                            FavoriteButton(artwork: artwork)
                        }
                        .padding(.bottom, 8)
                    }
                caption
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.background)
            .clipped()
        }
    }

    // MARK: - Subviews

    private func image(topInset: CGFloat) -> some View {
        // GeometryReader measures the exact slot so scaledToFit() receives finite
        // bounds in both axes. Without explicit maxHeight, AsyncImage may propose
        // unbounded height, causing tall narrow paintings to exceed the slot and clip.
        GeometryReader { slot in
            // Guarantee at least 60 pt of clearance from the top of the screen so
            // no painting ever overlaps the Dynamic Island or status bar. The
            // AsyncImage container is framed to the usable region (below the top
            // inset, above 20 pt bottom padding) and then offset down into place,
            // so scaledToFit() centres the painting within that safe zone.
            let topPad = max(topInset, 60)
            let usableHeight = slot.size.height - topPad - 20
            let maxW = slot.size.width - 56   // 28 pt per side

            AsyncImage(url: artwork.imageURL) { phase in
                switch phase {
                case .empty:
                    BrewingView()
                        .frame(maxWidth: maxW, maxHeight: usableHeight)
                        .transition(.opacity)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        // Explicit finite bounds prevent tall paintings from overflowing.
                        .frame(maxWidth: maxW, maxHeight: usableHeight)
                        // Gentle shadow lifts the painting off the linen ground.
                        .shadow(color: Theme.ink.opacity(0.10), radius: 18, x: 0, y: 6)
                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                case .failure:
                    // Transparent placeholder — onAppear fires the removal
                    // callback so the feed can drop this card silently.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { onImageFailure?() }
                @unknown default:
                    Color.clear
                }
            }
            // Frame to the usable region and shift it below the status bar.
            .frame(width: slot.size.width, height: usableHeight)
            .offset(y: topPad)
            // Make the full usable area respond to gestures, not just image pixels.
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                performDoubleTap()
            }
            .overlay {
                // Double-tap save confirmation: cup rises and fades.
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(Theme.ink)
                    .opacity(cupOpacity)
                    .scaleEffect(cupScale)
                    .offset(y: cupOffset)
                    .allowsHitTesting(false)
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hairline separates image from text — like a mount beneath a print.
            Theme.hairline
                .frame(maxWidth: .infinity)
                .frame(height: 0.5)
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 5) {
                // All text is strictly single-line so the caption block has a
                // fixed height and can never push against the GeometryReader frame.
                Text(artwork.title)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(artwork.artistName)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.body)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !artwork.date.isEmpty {
                    Text(artwork.date)
                        .font(.system(.caption2))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(artwork.credit)
                    .font(.system(.caption2).italic())
                    .foregroundStyle(Theme.muted.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Double-tap save

    private func performDoubleTap() {
        // Only save and animate when the artwork isn't already in the cup.
        // (Unlike Instagram's heart, double-tapping a saved painting does nothing —
        // there's no feedback that would be honest here.)
        guard matches.isEmpty else { return }
        let item = FavoriteItem(from: artwork)
        context.insert(item)
        animateSaveCup()
        // Download and cache the image so the cup works offline.
        Task {
            if let path = try? await ImageStore.save(
                imageAt: artwork.imageURL,
                artworkID: artwork.id
            ) {
                // Guard against the race where the user unsaves before the
                // download finishes. SwiftData sets modelContext to nil on
                // deletion, so writing to a deleted item is a no-op here.
                guard item.modelContext != nil else { return }
                item.localImagePath = path
            }
        }
    }

    private func animateSaveCup() {
        // Cancel any in-flight animation from a previous tap so rapid
        // double-taps don't race against each other.
        animationTask?.cancel()

        // Reset to start position.
        cupOpacity = 0
        cupScale   = 0.75
        cupOffset  = 0

        // Phase 1: appear — quick bloom up to full size.
        withAnimation(.easeOut(duration: 0.18)) {
            cupOpacity = 0.72
            cupScale   = 1.0
        }

        // Phase 2: drift up and fade — slow and unhurried.
        animationTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.65)) {
                cupOpacity = 0
                cupScale   = 1.1
                cupOffset  = -18
            }
        }
    }
}

#Preview {
    ArtworkCard(artwork: Artwork(
        id: "437984",
        imageURL: URL(string: "https://images.metmuseum.org/CRDImages/ep/original/DT1567.jpg")!,
        title: "Self-Portrait with a Straw Hat",
        artistName: "Vincent van Gogh",
        date: "1887",
        credit: "The Metropolitan Museum of Art"
    ))
    .ignoresSafeArea()
}
