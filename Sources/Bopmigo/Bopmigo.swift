import SwiftUI
import UIKit

/// In-app feedback for your team. Set up once, then call `Bopmigo.show()`.
///
///     Bopmigo.configure(siteID: "YOUR-SITE-ID")
///
@MainActor
public enum Bopmigo {
    /// When taking a screenshot should offer "Report a problem?".
    public enum ScreenshotPrompt { case never, testersOnly, always }

    static var siteID: String?
    static var host = URL(string: "https://bopmigo.com")!
    static var hideAllText = false
    static var screen: String?
    static var user: [String: String] = [:]
    static var custom: [String: String] = [:]
    static var observer: NSObjectProtocol?
    static var activeObserver: NSObjectProtocol?

    /// Starts Bopmigo. Call once, for example in your App's `init`.
    /// - Parameters:
    ///   - siteID: The ID shown in Bopmigo under your app's install settings.
    ///   - screenshotPrompt: `.testersOnly` (default) asks in TestFlight and debug builds only.
    ///   - host: Leave as is unless you were given a test address.
    public static func configure(siteID: String, screenshotPrompt: ScreenshotPrompt = .testersOnly, host: URL? = nil) {
        self.siteID = siteID
        if let host { self.host = host }
        let ask: Bool
        switch screenshotPrompt {
        case .never: ask = false
        case .always: ask = true
        case .testersOnly: ask = Environment.isTester
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = ask ? NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Presenter.offerAfterScreenshot() }
        } : nil
        Task { await Client.shared.loadConfig(); await Client.shared.sendQueued(); await Presenter.offerReplies() }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        // When the app comes back to the front, tell the person if the team replied.
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await Presenter.offerReplies() }
        }
    }

    /// Opens the list of feedback this person sent, with the team's replies.
    public static func showReplies() { Presenter.present(history: true) }

    /// Opens the feedback sheet over the current screen.
    public static func show() { Presenter.present() }

    /// Names the screen the person is on, so reports say where it happened.
    public static func setScreen(_ name: String?) { screen = name }

    /// Who is reporting, if they are signed in to your app. Optional.
    public static func setUser(id: String? = nil, email: String? = nil, name: String? = nil) {
        user = [:]
        if let id { user["userId"] = id }
        if let email { user["userEmail"] = email }
        if let name { user["userName"] = name }
    }

    /// Extra details attached to every report, for example a plan or build flavor. Up to 20.
    public static func setContext(_ key: String, _ value: String?) {
        let clean = key.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(32)
        custom["custom_\(clean)"] = value
    }

    /// Hides every word in screenshots, not only passwords and private views.
    public static func setHideAllText(_ on: Bool) { hideAllText = on }
}

public extension View {
    /// Covers this view in Bopmigo screenshots.
    func bopmigoPrivate() -> some View { overlay(PrivateMarker().allowsHitTesting(false)) }
    /// Tells Bopmigo which screen this is while it's visible.
    func bopmigoScreen(_ name: String) -> some View { onAppear { Bopmigo.setScreen(name) } }
}

public extension UIView {
    /// Covers this view in Bopmigo screenshots.
    var bopmigoPrivate: Bool {
        get { Redactor.isPrivate(self) }
        set { Redactor.mark(self, newValue) }
    }
}

enum Environment {
    static var isTester: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
