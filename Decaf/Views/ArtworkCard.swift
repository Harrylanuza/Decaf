import SwiftUI

struct ArtworkCard: View {
    let artwork: Artwork
    @State private var titleExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            image
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            caption
        }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            FavoriteButton(artwork: artwork)
        }
    }

    // MARK: - Subviews

    private var image: some View {
        AsyncImage(url: artwork.imageURL) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .tint(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    // Gentle shadow lifts the painting off the linen ground.
                    .shadow(color: Theme.ink.opacity(0.10), radius: 18, x: 0, y: 6)
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
