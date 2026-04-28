import MediaPlayer
import Testing
import UIKit

/// Regression tests for `AudioPlayerManager` integration with MediaPlayer.
struct AudioPlayerManagerTests {

    // MPMediaItemArtwork calls its request handler on a background queue.
    // When the handler is defined inside a @MainActor method, Swift 6 silently
    // inherits MainActor isolation, causing a runtime crash
    // (_dispatch_assert_queue_fail) when MediaPlayer invokes it off-main.
    // The fix is to mark the closure @Sendable.
    @Test func artworkRequestHandlerCanBeCalledOffMainActor() async {
        let image = UIImage()
        let artwork = MPMediaItemArtwork(
            boundsSize: CGSize(width: 100, height: 100)
        ) { @Sendable _ in image }

        let result = await Task.detached {
            artwork.image(at: CGSize(width: 50, height: 50))
        }.value

        #expect(result != nil)
    }
}
