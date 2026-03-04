import SwiftUI
import SwiftData

struct ArtworkCard: View {
    let artwork: Artwork
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
                image
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                caption
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.background)
            .clipped()
        }
        // Single overlay spanning the full card width keeps both buttons in the
        // same render pass, avoiding z-order ambiguity between separate overlays.
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                ShareButton(artwork: artwork)
                Spacer()
                FavoriteButton(artwork: artwork)
            }
        }
    }

    // MARK: - Subviews

    private var image: some View {
        // GeometryReader at the card root (in body) already locks the total card
        // height, so every AsyncImage phase just needs to fill the available space.
        // scaledToFit centres the painting at its natural aspect ratio within the
        // fixed frame, with linen showing in the remaining space — like a wall mount.
        AsyncImage(url: artwork.imageURL) { phase in
            switch phase {
            case .empty:
                BrewingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Gentle shadow lifts the painting off the linen ground.
                    .shadow(color: Theme.ink.opacity(0.10), radius: 18, x: 0, y: 6)
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                Color.clear
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        // Make the full padded area respond to gestures, not just the image pixels.
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
