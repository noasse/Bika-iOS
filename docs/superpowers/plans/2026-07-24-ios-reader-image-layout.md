# iOS Reader Image Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS vertical reader use one decoded-image aspect ratio for both SwiftUI row layout and UIKit image rendering while preserving existing reader behavior.

**Architecture:** `DecodedImageAsset` exposes the aspect ratio of the actual decoded `UIImage`. Visible loading and prefetching propagate that ratio into `ComicReaderView`, and `ZoomingImageScrollView` receives the same ratio for frame calculation and fit-width visibility gating. The existing cache, request coalescing, decoding targets, zoom gestures, modes, chapter loading, and progress persistence remain intact.

**Tech Stack:** Swift, SwiftUI, UIKit, ImageIO, XCTest, Xcode test plans.

## Global Constraints

- Only modify the iOS client.
- Preserve horizontal paging, vertical scrolling, double-tap and pinch zoom, downsampling, memory caching, request coalescing, prefetching, chapter switching, and reading progress.
- Use the actual decoded `UIImage` aspect ratio as the sole exact layout value.
- Do not add third-party dependencies or change backend APIs.

---

### Task 1: Define and Test the Exact Layout Ratio

**Files:**
- Modify: `bika/Support/ImageDecoding.swift`
- Test: `bikaTests/ImagePipelineTests.swift`

**Interfaces:**
- Consumes: `DecodedImageAsset.image: UIImage`
- Produces: `DecodedImageAsset.layoutAspectRatio: CGFloat`

- [ ] **Step 1: Write the failing decoded-asset ratio test**

Add a test that creates an asset whose metadata size and rendered image have different ratios:

```swift
func testDecodedAssetLayoutRatioUsesRenderedImageSize() {
    let asset = DecodedImageAsset(
        image: makeImage(size: CGSize(width: 200, height: 500)),
        displaySize: CGSize(width: 200, height: 600)
    )

    XCTAssertEqual(asset.layoutAspectRatio, 2.5, accuracy: 0.001)
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
./scripts/test.sh unit
```

Expected: compilation fails because `DecodedImageAsset` has no `layoutAspectRatio`.

- [ ] **Step 3: Add the exact layout ratio**

Add:

```swift
var layoutAspectRatio: CGFloat {
    guard image.size.width.isFinite,
          image.size.height.isFinite,
          image.size.width > 0,
          image.size.height > 0 else {
        return 1
    }
    return image.size.height / image.size.width
}
```

- [ ] **Step 4: Run the image pipeline tests**

Run:

```bash
./scripts/test.sh unit
```

Expected: the new ratio test and existing image tests pass.

### Task 2: Make UIKit Rendering Consume the Exact Ratio

**Files:**
- Modify: `bika/Views/Helpers/ZoomableImageView.swift`
- Test: `bikaTests/ImagePipelineTests.swift`

**Interfaces:**
- Consumes: `DecodedImageAsset.layoutAspectRatio`
- Produces: `ZoomingImageScrollView.setImage(_:layoutAspectRatio:waitsForFitWidthBounds:)`

- [ ] **Step 1: Write failing layout consistency tests**

Add tests which:

- pass an image with ratio `2.5`;
- pass a conflicting external display size;
- assert the image view height is `bounds.width * 2.5`;
- assert fit-width rendering remains hidden while bounds height does not match;
- resize bounds to the expected height and assert the image becomes visible;
- assert viewport rendering remains visible immediately.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
xcodebuild -project bika.xcodeproj -scheme bika -testPlan bika -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -derivedDataPath /tmp/bika-derived CODE_SIGNING_ALLOWED=NO test -only-testing:bikaTests/ImagePipelineTests
```

Expected: compilation fails because the new `setImage` interface does not exist.

- [ ] **Step 3: Store and use the explicit ratio**

Change `ZoomingImageScrollView` to retain a validated layout ratio and calculate:

```swift
let fitHeight = boundsSize.width * layoutAspectRatio
```

For fit-width pages, keep `readerImageView.isHidden` true until:

```swift
abs(boundsSize.height - fitHeight) < 1
```

For viewport pages, show the image immediately and preserve centering.

- [ ] **Step 4: Pass the ratio from the coordinator**

In `Coordinator.display`, call:

```swift
scrollView.setImage(
    asset.image,
    layoutAspectRatio: asset.layoutAspectRatio,
    waitsForFitWidthBounds: parent.sizing.isFitWidth
)
parent.onImageAspectRatio?(asset.layoutAspectRatio)
```

- [ ] **Step 5: Run the focused tests**

Run the focused `ImagePipelineTests` command from Step 2.

Expected: all image pipeline tests pass.

### Task 3: Unify SwiftUI Reader Layout and Prefetch Results

**Files:**
- Modify: `bika/Views/ComicReaderView.swift`
- Modify: `bika/Views/Helpers/ZoomableImageView.swift`
- Test: `bikaTests/ReaderViewModelTests.swift`

**Interfaces:**
- Consumes: `ZoomableImageView.onImageAspectRatio: ((CGFloat) -> Void)?`
- Produces: `ReaderVerticalImageLayout.pageHeight(viewportWidth:exactAspectRatio:estimatedAspectRatio:fallbackAspectRatio:)`

- [ ] **Step 1: Replace size-based tests with ratio-based tests**

Test exact ratio priority, estimate fallback, default ratio fallback, and invalid ratio handling:

```swift
let height = ReaderVerticalImageLayout.pageHeight(
    viewportWidth: 320,
    exactAspectRatio: 3,
    estimatedAspectRatio: 1.25
)
XCTAssertEqual(height, 960, accuracy: 0.01)
```

- [ ] **Step 2: Run the reader layout tests and verify failure**

Run:

```bash
xcodebuild -project bika.xcodeproj -scheme bika -testPlan bika -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -derivedDataPath /tmp/bika-derived CODE_SIGNING_ALLOWED=NO test -only-testing:bikaTests/ReaderViewModelTests
```

Expected: compilation fails because the ratio-based signature does not exist.

- [ ] **Step 3: Store ratios instead of sizes**

In `ComicReaderView`:

```swift
@State private var imageAspectRatios: [String: CGFloat] = [:]
@State private var sampledAspectRatios: [String: CGFloat] = [:]
```

Use a stable identity composed from the episode ID and page ID. Update layout callbacks and reset logic to write ratios rather than `CGSize`.

- [ ] **Step 4: Return ratios from prefetch**

Change `ReaderImagePrefetchResult` to contain:

```swift
let layoutAspectRatio: CGFloat
```

Return `asset.layoutAspectRatio` for both cached and newly loaded assets.

- [ ] **Step 5: Update the height calculation**

Use exact ratio first, sampled median second, and `1.5` as the last fallback:

```swift
return viewportWidth * resolvedAspectRatio
```

- [ ] **Step 6: Run reader and image tests**

Run:

```bash
./scripts/test.sh unit
```

Expected: all iOS unit tests pass.

### Task 4: Verify Preserved Reader Behavior

**Files:**
- Test: `bikaTests/ImagePipelineTests.swift`
- Test: `bikaTests/ReaderViewModelTests.swift`
- Test: `bikaUITests/BikaSmokeUITests.swift` only if an existing assertion requires adjustment

**Interfaces:**
- Consumes: completed image and reader layout behavior
- Produces: regression evidence for the complete change

- [ ] **Step 1: Run the full iOS unit suite**

Run:

```bash
./scripts/test.sh unit
```

Expected: all `bikaTests` tests pass.

- [ ] **Step 2: Build the iOS application**

Run:

```bash
xcodebuild -project bika.xcodeproj -scheme bika -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/bika-reader-layout-build CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Inspect the final diff**

Run:

```bash
git diff --check
git diff -- bika/Support/ImageDecoding.swift bika/Views/Helpers/ZoomableImageView.swift bika/Views/ComicReaderView.swift bikaTests/ImagePipelineTests.swift bikaTests/ReaderViewModelTests.swift
```

Expected: no whitespace errors; changes remain scoped to the iOS image layout flow and its tests.

- [ ] **Step 4: Confirm repository state**

Run:

```bash
git status --short
```

Expected: only the design, plan, targeted iOS source files, and targeted tests are modified.
