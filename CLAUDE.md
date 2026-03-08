# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

This is a pure Xcode project with no external dependencies (no SPM, no CocoaPods, no Makefile).

- **Open project:** `open Decaf.xcodeproj`
- **Build from CLI:** `xcodebuild build -project Decaf.xcodeproj -scheme Decaf -destination 'platform=iOS Simulator,name=iPhone 16'`
- **No tests exist yet** — there is no test target in the project.

Minimum deployment target is iOS 18. All APIs used require iOS 17+ (`@Observable`, SwiftData, structured concurrency).

## Architecture

**Decaf** is a vertical-paging art discovery app. Users browse public-domain paintings from three museum APIs, save favourites to a local "cup," and view them in a grid.

### Data flow

```
Museum APIs ──► actor Services ──► [Artwork] ──► FeedView ──► ArtworkCard
                                                      │
                                              SwiftData (FavoriteItem)
                                                      │
                                              FavoritesView ──► CupDetailView
```

- **`Artwork`** is a lightweight display struct (not persisted).
- **`FavoriteItem`** is the SwiftData `@Model`. It duplicates the Artwork fields so favourites survive across sessions and can be displayed without network access.
- `FavoriteItem.asArtwork` converts back to `Artwork` for display in `CupDetailView`, which reuses the same `ArtworkCard` as the feed.

### Services (all `actor` singletons)

| Service | API style | Notes |
|---|---|---|
| `MetService` | REST/JSON | American Wing + European Paintings departments |
| `RijksmuseumService` | OAI-PMH XML + IIIF | Must probe `/info.json` per image to validate dimensions before returning |
| `ArtInstituteService` | Elasticsearch JSON | Simplest to add new fields to |

`FeedView.load()` fires all three concurrently with `async let` and shuffles the combined result. `fetchMore()` uses the same pattern; `seenIDs: Set<String>` deduplicates across batches.

### UIPageViewController bridging

The discovery feed is `VerticalPageFeed: UIViewControllerRepresentable`. UIKit owns paging; each page is a `UIHostingController` wrapping `ArtworkCard`. Key constraints:

- `vc.view.tag` stores the page index — this is how the data source and `updateUIViewController` identify pages.
- `Coordinator.currentIndex` is updated by `UIPageViewControllerDelegate` on every completed swipe. `updateUIViewController` uses this (not `pvc.viewControllers?.first`) as the source of truth for position, because the pvc's array can be transiently nil after visibility changes.
- `ContentView` keeps both `FeedView` and `FavoritesView` permanently in a `ZStack` with `opacity`/`allowsHitTesting` — never destroying them on tab switch — so the UIPageViewController retains its page position.

### Safe area handling in ArtworkCard

`ArtworkCard` uses `ignoresSafeArea()` to fill the full screen. Internally, `image(topInset:)` reads `geo.safeAreaInsets.top` from the outer `GeometryReader` and applies `topPad = max(topInset, 60)` so paintings never touch the Dynamic Island. The image container is framed to `usableHeight` and offset down by `topPad`. Applying `.ignoresSafeArea()` directly to the card (not to a wrapping `GeometryReader`) is essential — a wrapper causes double-counting of the inset.

### Theme

All design tokens are in `Theme.swift` as static properties on an `enum Theme`. Colors are warm neutrals (linen background, ink/body/muted text, hairline separator). Use `Theme.*` for all colours and `Theme.hairline` for the 0.5pt separator rule. Serif fonts use `design: .serif`.

### Image caching

`ImageStore` saves JPEGs to `Application Support/SavedImages/` using sanitised, relative paths. `FavoriteItem.localImagePath` stores the relative path. `ThumbnailCell` and `CupDetailView` prefer the local file and fall back to the remote URL — so favourites work offline even if the background download hadn't finished.

### Offline behaviour

`NetworkMonitor` (`@Observable`, injected via environment) uses `NWPathMonitor`. The feed shows a banner when offline with artworks loaded, and a full empty state when offline with no artworks. Saving a favourite inserts the SwiftData record immediately (instant UI response), then downloads the image asynchronously.
