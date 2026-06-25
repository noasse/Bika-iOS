import Foundation

@Observable
final class MacCommentsWindowStore {
    var request: MacCommentsLaunchRequest?

    func open(comicId: String, comicTitle: String) {
        request = MacCommentsLaunchRequest(comicId: comicId, comicTitle: comicTitle)
    }
}
