import SwiftUI
import WebKit

/// Embeds a YouTube video inline using WKWebView and the **IFrame Player
/// API** (the same approach as Google's `youtube-ios-player-helper`).
/// Pass the 11-character video ID (the part after `?v=`).
///
/// A raw `<iframe src="/embed/…">` loaded via `loadHTMLString` frequently
/// refuses playback ("video unavailable", error 150/152) because the embed's
/// referrer/origin handshake fails. Loading the IFrame API script and letting
/// `YT.Player` construct the embed performs that handshake correctly, so
/// embeddable videos play reliably.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only (re)load when the video actually changes; loadHTMLString sets
        // webView.url to the base URL, so a url==nil guard would never hold.
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
          * { margin: 0; padding: 0; }
          html, body { background: #000; height: 100%; overflow: hidden; }
          #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
          var tag = document.createElement('script');
          tag.src = "https://www.youtube.com/iframe_api";
          var first = document.getElementsByTagName('script')[0];
          first.parentNode.insertBefore(tag, first);
          var player;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: '100%',
              height: '100%',
              videoId: '\(videoID)',
              playerVars: {
                playsinline: 1,
                rel: 0,
                modestbranding: 1,
                fs: 1,
                origin: 'https://www.youtube.com'
              }
            });
          }
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedID: String?
    }
}
