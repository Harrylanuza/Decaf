import SwiftUI
import UIKit

struct ShareButton: View {
    let artwork: Artwork

    @State private var isPresenting = false
    @State private var shareItems: [Any] = []
    @State private var isFetching = false

    var body: some View {
        Button {
            guard !isFetching else { return }
            Task { await prepareAndShare() }
        } label: {
            Image(systemName: "paperplane")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(isFetching ? Theme.muted.opacity(0.35) : Theme.muted)
                .animation(.easeInOut(duration: 0.15), value: isFetching)
        }
        // 44 × 44 touch target — same as FavoriteButton.
        // 20 pt leading mirrors the cup button's 20 pt trailing pad.
        .frame(width: 44, height: 44)
        .padding(.leading, 20)
        .sheet(isPresented: $isPresenting) {
            ShareSheet(items: shareItems)
                .ignoresSafeArea()
        }
    }

    private func prepareAndShare() async {
        isFetching = true

        let message = """
            "\(artwork.title)" by \(artwork.artistName)

            I saw this painting on Decaf and thought of you.
            """

        // URLSession checks the shared URL cache first, so images already on screen
        // are returned almost instantly. File URLs (for saved-offline favourites) work too.
        if let (data, _) = try? await URLSession.shared.data(from: artwork.imageURL),
           let image = UIImage(data: data) {
            shareItems = [image, message]
        } else {
            shareItems = [message]
        }

        isFetching = false
        isPresenting = true
    }
}

// Thin wrapper so UIActivityViewController can be presented from SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
