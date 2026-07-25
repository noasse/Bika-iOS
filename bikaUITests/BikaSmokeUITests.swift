import XCTest

final class BikaSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchPaginationSortAndBackNavigation() throws {
        let app = launchApp(resetState: true)

        openSearchAndRunQuery(in: app)
        let firstResult = app.buttons["search.result.comic-search-1"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))

        let nextPageButton = app.buttons["pagination.next"]
        XCTAssertTrue(nextPageButton.waitForExistence(timeout: 3))
        nextPageButton.tap()

        let gammaResult = app.buttons["search.result.comic-search-3"]
        XCTAssertTrue(gammaResult.waitForExistence(timeout: 5))
        gammaResult.tap()
        XCTAssertTrue(app.buttons["comicDetail.openComments"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(gammaResult.waitForExistence(timeout: 5))

        let likedSortButton = app.buttons["search.sort.ld"]
        XCTAssertTrue(likedSortButton.waitForExistence(timeout: 3))
        likedSortButton.tap()

        XCTAssertTrue(app.staticTexts["爱心榜首"].waitForExistence(timeout: 5))
    }

    func testCommentsAndChildCommentsOpenWithoutInfiniteLoading() throws {
        let app = launchApp(resetState: true)

        openComicDetail(in: app)

        let commentsButton = app.buttons["comicDetail.openComments"]
        XCTAssertTrue(commentsButton.waitForExistence(timeout: 5))
        commentsButton.tap()

        let firstComment = app.staticTexts["第一页第一条评论"]
        XCTAssertTrue(firstComment.waitForExistence(timeout: 5))
        let lowerComment = app.staticTexts["第一页第八条评论"]
        for _ in 0..<6 where !lowerComment.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lowerComment.waitForExistence(timeout: 5))
        XCTAssertTrue(lowerComment.isHittable)
        lowerComment.tap()

        XCTAssertTrue(app.staticTexts["子评论内容"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["评论"].waitForExistence(timeout: 5))
        XCTAssertTrue(lowerComment.waitForExistence(timeout: 5))
        XCTAssertTrue(lowerComment.isHittable)
        XCTAssertFalse(firstComment.isHittable)
    }

    func testImageCacheCanBeInspectedAndCleared() throws {
        let app = launchApp(resetState: true)

        openSettings(in: app)

        XCTAssertTrue(app.staticTexts["settings.imageCacheSize"].waitForExistence(timeout: 5))
        let clearButton = app.buttons["settings.clearImageCache"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        let confirmButton = app.buttons["清理"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts["settings.imageCacheMessage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["settings.imageCacheMessage"].label, "图片缓存已清理")
    }

    func testSettingsShowsImageDiagnosticsAndPrivacyWarningBeforeExport() {
        let app = launchApp(resetState: true)
        openSettings(in: app)

        let count = app.staticTexts["settings.imageDiagnostics.count"]
        for _ in 0..<6 where !count.exists {
            app.swipeUp()
        }
        XCTAssertTrue(count.waitForExistence(timeout: 5))

        app.buttons["settings.imageDiagnostics.export"].tap()

        XCTAssertTrue(
            app.staticTexts["导出文件包含完整图片 URL，请只发送给可信对象。"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["继续导出"].exists)
        app.buttons["取消"].tap()
    }

    func testReaderProgressRestoresAfterRelaunch() throws {
        var app = launchApp(resetState: true)

        openComicDetail(in: app)

        let episodeButton = app.buttons["comicDetail.episode.1"]
        XCTAssertTrue(episodeButton.waitForExistence(timeout: 5))
        episodeButton.tap()

        let toggleModeButton = app.buttons["reader.toggleMode"]
        XCTAssertTrue(toggleModeButton.waitForExistence(timeout: 5))
        toggleModeButton.tap()

        let nextEpisodeButton = app.buttons["reader.nextEpisode"]
        XCTAssertTrue(nextEpisodeButton.waitForExistence(timeout: 5))
        nextEpisodeButton.tap()

        XCTAssertTrue(app.staticTexts["第2话"].waitForExistence(timeout: 5))
        app.buttons["reader.close"].tap()

        app.terminate()

        app = launchApp(resetState: false)
        openComicDetail(in: app)

        let continueReadingButton = app.buttons["comicDetail.continueReading"]
        XCTAssertTrue(continueReadingButton.waitForExistence(timeout: 5))
        continueReadingButton.tap()

        XCTAssertTrue(app.staticTexts["第2话"].waitForExistence(timeout: 5))
    }

    func testReaderCenterTapHidesAndShowsToolbar() throws {
        let app = launchApp(resetState: true)

        openComicDetail(in: app)

        let episodeButton = app.buttons["comicDetail.episode.1"]
        XCTAssertTrue(episodeButton.waitForExistence(timeout: 5))
        episodeButton.tap()

        let closeButton = app.buttons["reader.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1/2"].waitForExistence(timeout: 5))

        let readerCenter = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        readerCenter.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 2))

        readerCenter.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
    }

    func testImageQualityPersistsAndRecordedByMockRequests() throws {
        var app = launchApp(resetState: true)

        openSettings(in: app)

        let highQualityButton = app.buttons["settings.imageQuality.high"]
        XCTAssertTrue(highQualityButton.waitForExistence(timeout: 5))
        highQualityButton.tap()

        app.terminate()

        app = launchApp(resetState: false)
        openSearchAndRunQuery(in: app)
        XCTAssertTrue(app.buttons["search.result.comic-search-1"].waitForExistence(timeout: 5))

        openSettings(in: app)

        let recordedQualityValue = app.staticTexts["settings.lastMockImageQualityValue"]
        for _ in 0..<6 where !recordedQualityValue.exists {
            app.swipeUp()
        }
        XCTAssertTrue(recordedQualityValue.waitForExistence(timeout: 5))
        XCTAssertEqual(recordedQualityValue.label, "high")
    }

    func testAuthorResultsReturnToListAfterOpeningComicDetail() throws {
        let app = launchApp(resetState: true)

        openComicDetail(in: app)

        let authorButton = app.buttons["测试作者"]
        XCTAssertTrue(authorButton.waitForExistence(timeout: 5))
        authorButton.tap()

        let authorResult = app.buttons["author.result.comic-search-1"]
        XCTAssertTrue(authorResult.waitForExistence(timeout: 5))
        authorResult.tap()

        XCTAssertTrue(app.buttons["comicDetail.openComments"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(authorResult.waitForExistence(timeout: 5))
    }

    func testFavouritesReturnToListAfterOpeningComicDetail() throws {
        let app = launchApp(resetState: true)

        app.tabBars.buttons["我的"].tap()

        let favouritesButton = app.buttons["我的收藏"]
        XCTAssertTrue(favouritesButton.waitForExistence(timeout: 5))
        favouritesButton.tap()

        let favouriteResult = app.buttons["favourites.result.comic-favourite-1"]
        XCTAssertTrue(favouriteResult.waitForExistence(timeout: 5))
        favouriteResult.tap()

        XCTAssertTrue(app.buttons["comicDetail.openComments"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(favouriteResult.waitForExistence(timeout: 5))
    }

    @discardableResult
    private func launchApp(resetState: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-authenticated"]
        if resetState {
            app.launchArguments += ["-ui-reset-state"]
        }
        app.launchEnvironment["UI_TEST_SCENARIO"] = "smoke"
        app.launchEnvironment["UI_TEST_STORE_SUITE"] = "com.noasse.bika.ui-tests"
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["搜索"].waitForExistence(timeout: 8))
        return app
    }

    private func openSearchAndRunQuery(in app: XCUIApplication) {
        app.tabBars.buttons["搜索"].tap()

        let searchField = app.textFields["search.keywordField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("smoke\n")
    }

    private func openComicDetail(in app: XCUIApplication) {
        openSearchAndRunQuery(in: app)
        let firstResult = app.buttons["search.result.comic-search-1"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))
        firstResult.tap()
    }

    private func openSettings(in app: XCUIApplication) {
        app.tabBars.buttons["我的"].tap()

        let settingsButton = app.buttons["profile.openSettings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
    }
}
