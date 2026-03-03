import SwiftUI
import SwiftData

struct ArtworkCard: View {
    let artwork: Artwork
    @State private var titleExpanded = false

    // Double-tap save confirmation state
    @State private var cupOpacity: Double = 0
    @State private var cupScale: CGFloat = 0.75
    @State private var cupOffset: CGFloat = 0

    @Environment(\.modelContext) private var context
    @Query private var matches: [FavoriteItem]

    init(artwork: Artwork) {
        self.artwork = artwork
        let id = artwork.id
        _matches = Query(filter: #Predicate<FavoriteItem> { $0.artworkID == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            image
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            caption
        }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            FavoriteButton(artwork: artwork)
                .safeAreaPadding(.top)
        }
    }

    // MARK: - Subviews

    private var image: some View {
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
                Text(artwork.title)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(titleExpanded ? nil : 1)
                    .truncationMode(.tail)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            titleExpanded.toggle()
                        }
                    }

                Text(artwork.artistName)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.body)

                if !artwork.date.isEmpty {
                    Text(artwork.date)
                        .font(.system(.caption2))
                        .foregroundStyle(Theme.muted)
                }

                Text(artwork.credit)
                    .font(.system(.caption2).italic())
                    .foregroundStyle(Theme.muted.opacity(0.75))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Double-tap save

    private func performDoubleTap() {
        if matches.isEmpty {
            context.insert(FavoriteItem(from: artwork))
        }
        animateSaveCup()
    }

    private func animateSaveCup() {
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
        Task {
            try? await Task.sleep(for: .milliseconds(350))
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
