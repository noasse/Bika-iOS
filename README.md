[简体中文](README.zh-CN.md)

# Bika-iOS

A SwiftUI-based iOS comic reader that brings browsing, search, detail, reading, comments, favourites, and progress recovery into one cohesive app flow.

> Status: actively maintainable  
> Platform: iOS 18.0+  
> Stack: SwiftUI, `@Observable`, async/await, Xcode Test Plan

## Overview

Bika-iOS is built around real reading workflows instead of isolated UI demos. The project covers the full path from discovery to long-session reading:

- browse comics through categories and leaderboards
- search with sorting, pagination, and state restoration
- inspect comic details, episodes, tags, authors, and recommendations
- continue reading from persisted chapter and page position
- follow comments and child comments
- manage favourites, history, theme, and image quality preferences

The repository also serves as a practical SwiftUI reference project for:

- `@Observable`-based state management
- async/await networking and page-level state transitions
- reusable paginated result screens
- mock-driven unit and UI smoke testing

## Features

- Category browsing with paginated comic result lists
- Ranking pages with multiple time ranges
- Search results with sorting, page switching, and restoration
- Comic detail pages with metadata, episode entry, recommendations, and comment navigation
- Reader with horizontal paging and vertical scrolling modes
- Reading progress persistence and continue-reading recovery
- Comment and child-comment browsing with like and reply actions
- Favourites, history, theme mode, image quality, and content filtering settings

## Architecture Highlights

### Shared paginated comic results

Several list-based pages reuse a common pagination pattern instead of each carrying a separate state machine.

- [ComicResultsViewModel.swift](bika/ViewModels/ComicResultsViewModel.swift)
- [PaginatedComicResultsView.swift](bika/Views/Helpers/PaginatedComicResultsView.swift)

### Composed comic detail screen

The comic detail experience is organized as smaller dedicated sections instead of a single oversized view file.

- [ComicDetailView.swift](bika/Views/ComicDetailView.swift)
- [ComicDetailSections.swift](bika/Views/ComicDetailSections.swift)

### Progress recovery and reading continuity

The reader persists chapter and page position so users can return directly to where they left off.

- [ComicReaderView.swift](bika/Views/ComicReaderView.swift)
- [ReadingProgressManager.swift](bika/Views/Helpers/ReadingProgressManager.swift)

### Injectable dependencies and mock-first tests

The app can switch to fixture-backed dependencies for repeatable local and CI verification.

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
- `Network`: endpoints, API client, signing, and error definitions
- `Support`: dependency setup, mocks, navigation restoration, storage, and helpers
- `ViewModels`: page state, pagination flow, and async business logic
- `Views`: screens and feature composition
- `Views/Helpers`: shared UI, reader support, pagination, and image helpers

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

Tests are mock-based by default, so they do not require a live backend or real account.

More details:

- [TESTING.md](TESTING.md)

## CI

GitHub Actions workflow:

- [.github/workflows/ios-tests.yml](.github/workflows/ios-tests.yml)

Checks currently run on `push` and `pull_request`:

- `unit`
- `ui-smoke`

## Roadmap

Current maintenance direction:

- keep migrating more list-style pages onto the shared paginated results pattern
- continue shrinking direct singleton usage inside views
- expand unit coverage around ViewModels and support utilities
- keep critical failure paths visible instead of silently degrading user actions

## Documentation

- Testing guide: [TESTING.md](TESTING.md)
- Architecture and maintenance notes: [bika项目文档.md](bika项目文档.md)

## License

No license file is currently included in this repository.
