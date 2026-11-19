import UIKit
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency

/// Full-screen ads: one when the app opens (cold start, or coming back after a while),
/// and one an hour while it's in use. An ad never covers an open form or sheet; the hourly
/// one waits until nothing is on top of the main screen.
@MainActor
final class AdManager: NSObject, GADFullScreenContentDelegate {
    static let shared = AdManager()

    // Ad IDs come from Info.plist (set in project.yml). The defaults are Google's public test ads.
    private static func id(_ key: String, _ test: String) -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return v.isEmpty || v.hasPrefix("$(") ? test : v
    }
    private let appOpenID = id("AdUnitAppOpen", "ca-app-pub-3940256099942544/5575463023")
    private let interstitialID = id("AdUnitInterstitial", "ca-app-pub-3940256099942544/4411468910")

    /// Time between hourly ads, and the shortest gap between any two ads.
    private let hourly: TimeInterval = 60 * 60
    private let minimumGap: TimeInterval = 3 * 60
    /// Coming back to the app counts as "opening" it after this long away.
    private let awayCountsAsOpen: TimeInterval = 60

    private var appOpenAd: GADAppOpenAd?
    private var appOpenLoadedAt: Date?
    private var interstitial: GADInterstitialAd?
    private var ready = false
    private var showing = false
    private var wantsLaunchAd = true
    private var backgroundedAt: Date?
    private var timer: Timer?
    private var lastShown: Date? {
        get { UserDefaults.standard.object(forKey: "adLastShown") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "adLastShown") }
    }

    /// Off for the build server's screenshots.
    var enabled: Bool { !LaunchOptions.demo || adCheck }
    /// Build server check that a test ad really appears (skips the tracking question, which would block the screen).
    private var adCheck: Bool { LaunchOptions.args.contains("-adcheck") }

    /// Privacy consent (required in the EU/UK), the tracking question, then the ad SDK.
    func start() async {
        guard enabled, !ready else { return }
        let consent = UMPConsentInformation.sharedInstance
        do {
            try await consent.requestConsentInfoUpdate(with: UMPRequestParameters())
            try await UMPConsentForm.loadAndPresentIfRequired(from: topController())
        } catch {
            // Consent couldn't be checked (offline). Ads wait for a later launch.
        }
        guard consent.canRequestAds else { return }
        if !adCheck, ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        _ = await GADMobileAds.sharedInstance().start()
        ready = true
        await loadAppOpen()
        await loadInterstitial()
        if wantsLaunchAd { showAppOpen() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in AdManager.shared.hourlyCheck() }
        }
    }

    func didEnterBackground() { backgroundedAt = Date() }

    func didBecomeActive() {
        guard enabled else { return }
        if let away = backgroundedAt, Date().timeIntervalSince(away) >= awayCountsAsOpen {
            wantsLaunchAd = true
            showAppOpen()
        }
        backgroundedAt = nil
    }

    // MARK: loading

    private func loadAppOpen() async {
        guard ready else { return }
        do {
            let ad = try await GADAppOpenAd.load(withAdUnitID: appOpenID, request: GADRequest())
            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            appOpenLoadedAt = Date()
        } catch { appOpenAd = nil }
    }

    private func loadInterstitial() async {
        guard ready else { return }
        do {
            let ad = try await GADInterstitialAd.load(withAdUnitID: interstitialID, request: GADRequest())
            ad.fullScreenContentDelegate = self
            interstitial = ad
        } catch { interstitial = nil }
    }

    // MARK: showing

    private var spacedOut: Bool { lastShown.map { Date().timeIntervalSince($0) >= minimumGap } ?? true }

    private func showAppOpen() {
        guard ready, !showing, spacedOut else { return }
        // App open ads expire after four hours.
        guard let ad = appOpenAd, let at = appOpenLoadedAt, Date().timeIntervalSince(at) < 4 * 3600 else {
            Task { await loadAppOpen() }
            return
        }
        guard let vc = topController(), vc.presentedViewController == nil else { return }
        showing = true
        wantsLaunchAd = false
        lastShown = Date()
        appOpenAd = nil
        ad.present(fromRootViewController: vc)
    }

    private func hourlyCheck() {
        guard ready, !showing, UIApplication.shared.applicationState == .active else { return }
        guard lastShown.map({ Date().timeIntervalSince($0) >= hourly }) ?? true else { return }
        guard let ad = interstitial else { Task { await loadInterstitial() }; return }
        // Only when no form, sheet or menu is open, so it never interrupts a buy-in or cash-out.
        guard let vc = topController(), vc.presentedViewController == nil else { return }
        showing = true
        lastShown = Date()
        interstitial = nil
        ad.present(fromRootViewController: vc)
    }

    private func topController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    }

    // MARK: GADFullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        showing = false
        Task {
            if appOpenAd == nil { await loadAppOpen() }
            if interstitial == nil { await loadInterstitial() }
        }
    }
}
