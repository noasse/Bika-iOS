//
//  BikaMacosApp.swift
//  BikaMacos
//
//  Created by noasse on 6/23/26.
//

import SwiftUI

@main
struct BikaMacosApp: App {
    @State private var readingStore: MacReadingStore
    @State private var blockedCategoriesStore: MacBlockedCategoriesStore
    @State private var commentsWindowStore: MacCommentsWindowStore
    @State private var libraryModel: MacLibraryModel
    @AppStorage("macThemeMode") private var themeModeRawValue = MacThemeMode.system.rawValue

    init() {
        AppDependencies.shared.configureForLaunch()
        let readingStore = MacReadingStore()
        let blockedCategoriesStore = MacBlockedCategoriesStore()
        let commentsWindowStore = MacCommentsWindowStore()
        _readingStore = State(initialValue: readingStore)
        _blockedCategoriesStore = State(initialValue: blockedCategoriesStore)
        _commentsWindowStore = State(initialValue: commentsWindowStore)
        _libraryModel = State(
            initialValue: MacLibraryModel(
                readingStore: readingStore,
                blockedCategoriesStore: blockedCategoriesStore
            )
        )
    }

    var body: some Scene {
        WindowGroup("Bika", id: "library") {
            ContentView(model: libraryModel, commentsWindowStore: commentsWindowStore)
                .preferredColorScheme(MacThemeMode(rawValue: themeModeRawValue)?.colorScheme)
                .frame(minWidth: 760, minHeight: 520)
        }

        WindowGroup("阅读器", for: MacReaderLaunchRequest.self) { $request in
            if let request {
                MacReaderWindowView(request: request, readingStore: readingStore) { comicId in
                    libraryModel.readerDidClose(comicId: comicId)
                }
                    .preferredColorScheme(MacThemeMode(rawValue: themeModeRawValue)?.colorScheme)
                    .frame(minWidth: 420, minHeight: 360)
            } else {
                ContentUnavailableView("没有打开的章节", systemImage: "book.closed")
            }
        }
        .defaultSize(width: readerWindowDefaultContentSize.width, height: readerWindowDefaultContentSize.height)

        Window("评论", id: "comments") {
            MacCommentsWindowView(store: commentsWindowStore)
                .preferredColorScheme(MacThemeMode(rawValue: themeModeRawValue)?.colorScheme)
                .frame(minWidth: 520, minHeight: 560)
        }
        .defaultSize(width: 620, height: 680)

        Settings {
            MacSettingsView(themeModeRawValue: $themeModeRawValue, blockedCategoriesStore: blockedCategoriesStore)
        }
    }

    private var readerWindowDefaultContentSize: CGSize {
        MacReaderWindowSizePersistence.restoredContentSize(from: AppDependencies.shared.keyValueStore)
            ?? MacReaderWindowSizePersistence.fallbackContentSize
    }
}
