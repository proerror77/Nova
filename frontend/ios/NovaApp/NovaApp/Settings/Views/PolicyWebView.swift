import SwiftUI
import WebKit

/// ST03 - Policy WebView (template)
struct PolicyWebView: View {
    let url: URL
    var body: some View {
        WebView(url: url)
            .navigationTitle("Policy")
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) { uiView.load(URLRequest(url: url)) }
}
