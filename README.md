# Bika-iOS

A SwiftUI-based iOS comic reader project focused on browsing, reading, commenting, and progress recovery.

> Status: actively maintainable  
> Platform: iOS 18.0+  
> Stack: SwiftUI, `@Observable`, async/await, Xcode Test Plan

## Overview

Bika-iOS is a full-featured mobile reading client built around a real user flow instead of isolated demos.  
The project covers the core experience of a comic reader app:

- discover content through categories, ranking, and search
- inspect comic details, tags, authors, and recommendations
- read chapters with progress persistence and resume support
- browse comments and child comments
- manage favourites, reading history, theme, and image quality

Besides being a working app project, the repository is also useful as a reference for:

- SwiftUI app architecture with `@Observable`
- async/await driven networking and state updates
- reusable paginated list patterns
- mock-first testing for unit and UI smoke coverage

## Features

- Category browsing with paginated comic lists
- Ranking pages for multiple time ranges
- Search with sorting, pagination, and result restoration
- Comic detail pages with metadata, episodes, comments entry, and recommendations
- Reader with horizontal paging and vertical scrolling modes
- Reading progress persistence and continue-reading recovery
- Comment and child-comment browsing with like and reply actions
- Favourites and reading history
- Theme mode, image quality, and content filtering settings

## Highlights

### Reusable paginated list flow

Multiple comic result pages share the same pagination behavior, restoration logic, and error handling through:

- [ComicResultsViewModel.swift](bika/ViewModels/ComicResultsViewModel.swift)
- [PaginatedComicResultsView.swift](bika/Views/Helpers/PaginatedComicResultsView.swift)

### Split detail screen composition

The detail page is organized into dedicated sections instead of one oversized view file:

- [ComicDetailView.swift](bika/Views/ComicDetailView.swift)
- [ComicDetailSections.swift](bika/Views/ComicDetailSections.swift)

### Reader progress recovery

The reading flow persists chapter and page position so users can jump back in quickly:

- [ComicReaderView.swift](bika/Views/ComicReaderView.swift)
- [ReadingProgressManager.swift](bika/Views/Helpers/ReadingProgressManager.swift)

### Mock-first testing infrastructure

The app can switch to fixture-backed dependencies for repeatable automated tests:

- [AppDependencies.swift](bika/Support/AppDependencies.swift)
- [MockURLProtocol.swift](bika/Support/MockURLProtocol.swift)
- [SmokeFixtureRouter.swift](bika/Support/SmokeFixtureRouter.swift)

## Project Structure

```text
.
├── bika/                  # Application source code
├── bikaTests/             # Unit tests
├── bikaUITests/           # UI smoke tests
├── scripts/test.sh        # Unified local test entry
├── TESTING.md             # Testing guide
├── bika项目文档.md         # Architecture and maintenance notes
└── .github/workflows/     # CI workflows
```

Within `bika/`, the source tree is organized by responsibility:

- `Models`: response models and decoding rules
- `Network`: endpoints, client, signing, and API errors
- `Support`: dependency setup, mocks, navigation restoration, image helpers
- `ViewModels`: page state and async business flow
- `Views`: screens and page composition
- `Views/Helpers`: shared UI, pagination, images, and managers

## Getting Started

### Requirements

- Xcode `26.4`
- iOS Simulator
- Default simulator target: `iPhone 17`

### Common Commands

```bash
chmod +x ./scripts/test.sh
./scripts/test.sh build-for-testing
./scripts/test.sh unit
./scripts/test.sh ui-smoke
./scripts/test.sh all
```

## Testing

The repository currently uses two automated test layers:

- `Unit`
- `UI Smoke`

Tests are mock-based by default, so they do not require a real backend or live account.

More details:

- [TESTING.md](TESTING.md)

## CI

GitHub Actions workflow:

- [.github/workflows/ios-tests.yml](.github/workflows/ios-tests.yml)

Current checks on `push` and `pull_request`:

- `unit`
- `ui-smoke`

## Roadmap

Current maintenance direction:

- continue reusing the shared paginated list pattern for new comic list pages
- keep shrinking direct singleton usage inside views
- expand unit coverage around ViewModels and support utilities
- keep failure paths visible instead of silently degrading critical actions

## Documentation

- Testing guide: [TESTING.md](TESTING.md)
- Architecture and maintenance notes: [bika项目文档.md](bika项目文档.md)

## License

No license file is currently included in this repository.
