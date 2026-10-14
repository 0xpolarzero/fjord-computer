import AppKit
import SwiftUI
import WebKit

struct ComputerViewerSheet: View {
    let viewer: SiloWireViewerOpenResult
    let scripts: [ComputerViewerScriptCommand]
    let mockPreview: Bool
    let onScriptExecuted: (ComputerViewerScriptCommand) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .foregroundStyle(CDS.Text.secondary)
                Text(viewer.name).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                Spacer()
                ActionButton("Close screen") { onClose() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Rectangle().fill(CDS.Settings.divider).frame(height: 1)
            if mockPreview {
                MockLinuxDesktop(name: viewer.name)
                    .frame(minWidth: 760, minHeight: 500)
            } else {
                LinuxComputerWebView(viewer: viewer, scripts: scripts, onScriptExecuted: onScriptExecuted)
                    .frame(minWidth: 760, minHeight: 500)
            }
        }
        .background(CDS.Surface.s1)
    }
}

private struct MockLinuxDesktop: View {
    let name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.18, green: 0.20, blue: 0.34),
                                    Color(red: 0.30, green: 0.22, blue: 0.43)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("Activities").font(CDS.sans(10, .medium))
                    Text(name).font(CDS.sans(10, .medium))
                    Spacer()
                    Text("Oct 14  ·  10:42").font(CDS.sans(10))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(.black.opacity(0.28))
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Circle().fill(Color(red: 0.94, green: 0.38, blue: 0.37)).frame(width: 9, height: 9)
                        Circle().fill(Color(red: 0.94, green: 0.72, blue: 0.30)).frame(width: 9, height: 9)
                        Circle().fill(Color(red: 0.31, green: 0.76, blue: 0.48)).frame(width: 9, height: 9)
                        Text("Terminal").font(CDS.sans(10, .medium)).foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 31)
                    .background(.white.opacity(0.08))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("dev@\(name):~$ ls")
                            .foregroundStyle(.white.opacity(0.92))
                        Text("Projects   Downloads   README.md")
                            .foregroundStyle(Color(red: 0.74, green: 0.80, blue: 0.91))
                        Text("dev@\(name):~$ ▍")
                            .foregroundStyle(Color(red: 0.62, green: 0.84, blue: 0.72))
                    }
                    .font(CDS.sans(11).monospaced())
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 510, height: 220)
                .background(Color(red: 0.10, green: 0.11, blue: 0.15), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct LinuxComputerWebView: NSViewRepresentable {
    let viewer: SiloWireViewerOpenResult
    let scripts: [ComputerViewerScriptCommand]
    let onScriptExecuted: (ComputerViewerScriptCommand) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScriptExecuted: onScriptExecuted) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if !viewer.initScript.isEmpty {
            configuration.userContentController.addUserScript(WKUserScript(
                source: viewer.initScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.attach(webView)
        context.coordinator.load(viewer, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.accept(scripts)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        typealias ScriptEvaluator = (String, @escaping () -> Void) -> Void

        private struct Origin: Equatable {
            let scheme: String
            let host: String
            let port: Int?

            init?(_ url: URL) {
                guard url.user == nil, url.password == nil,
                      let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
                self.scheme = scheme
                self.host = host
                port = url.port
            }
        }

        private weak var webView: WKWebView?
        private let injectedEvaluator: ScriptEvaluator?
        private var onScriptExecuted: (ComputerViewerScriptCommand) -> Void
        private var origin: Origin?
        private var receivedScriptIDs: Set<UUID> = []
        private var pendingScripts: [ComputerViewerScriptCommand] = []
        private var isEvaluatingScript = false
        private(set) var pageReady = false

        init(evaluateScript: ScriptEvaluator? = nil,
             onScriptExecuted: @escaping (ComputerViewerScriptCommand) -> Void = { _ in }) {
            injectedEvaluator = evaluateScript
            self.onScriptExecuted = onScriptExecuted
            super.init()
        }

        func attach(_ webView: WKWebView) { self.webView = webView }

        func accept(_ script: String?) {
            guard let script, !script.isEmpty else { return }
            accept([ComputerViewerScriptCommand(connectionId: "", id: UUID(), script: script)])
        }

        func accept(_ commands: [ComputerViewerScriptCommand]) {
            for command in commands where receivedScriptIDs.insert(command.id).inserted {
                pendingScripts.append(command)
            }
            drainScripts()
        }

        func pageDidFinishLoading() {
            pageReady = true
            drainScripts()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            pageDidFinishLoading()
        }

        private func drainScripts() {
            guard pageReady, !isEvaluatingScript, !pendingScripts.isEmpty else { return }
            let command = pendingScripts.removeFirst()
            isEvaluatingScript = true
            let completion: () -> Void = { [weak self] in
                guard let self else { return }
                self.scriptEvaluationFinished(command)
            }
            if let injectedEvaluator {
                injectedEvaluator(command.script, completion)
            } else if let webView {
                webView.evaluateJavaScript(command.script) { _, _ in completion() }
            } else {
                completion()
            }
        }

        private func scriptEvaluationFinished(_ command: ComputerViewerScriptCommand) {
            isEvaluatingScript = false
            onScriptExecuted(command)
            drainScripts()
        }

        func load(_ viewer: SiloWireViewerOpenResult, in webView: WKWebView) {
            guard let url = URL(string: viewer.url), let origin = Origin(url),
                  origin.scheme == "http", origin.host == "127.0.0.1", origin.port != nil,
                  viewer.cookie.httpOnly, viewer.cookie.domain == origin.host,
                  viewer.cookie.path.hasPrefix("/"),
                  let cookie = HTTPCookie(properties: [
                    .domain: viewer.cookie.domain,
                    .path: viewer.cookie.path,
                    .name: viewer.cookie.name,
                    .value: viewer.cookie.value,
                    HTTPCookiePropertyKey(rawValue: "HttpOnly"): "TRUE"
                  ]) else { return }
            self.origin = origin
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            Task { @MainActor [weak webView] in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    cookieStore.setCookie(cookie) { continuation.resume() }
                }
                webView?.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard !action.shouldPerformDownload, let url = action.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.absoluteString == "about:blank" || Origin(url) == origin {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(false)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            completionHandler(nil)
        }
    }
}
