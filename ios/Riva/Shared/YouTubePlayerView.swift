import SwiftUI
import WebKit

/// Embeds a YouTube video inline using WKWebView.
/// Pass the 11-character video ID (the part after `?v=`).
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        let embedURL = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1")!
        webView.load(URLRequest(url: embedURL))
    }
}
