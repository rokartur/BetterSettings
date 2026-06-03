//
//  SettingsContentViewController.swift
//  BetterSettings
//
//  Hosts one content controller per tab. Lazily builds and caches controllers,
//  crossfades between them, and dispatches navigation requests (search jumps)
//  to the active tab.
//

import AppKit
import Combine

@MainActor
final class SettingsContentViewController: NSViewController {

    private let configuration: SettingsConfiguration
    private let router: SettingsRouter

    private let containerView = NSView()
    private var currentTabView: NSView?
    private var currentTabID: String?

    /// Controllers stay cached while the window is open (smoothness-first).
    private var cache: [String: SettingsTabViewController] = [:]

    private var navigationSubscription: AnyCancellable?
    private var lastHandledRequestID: UUID?
    private var transitionGeneration: UInt = 0
    private var pendingNavigationTask: Task<Void, Never>?

    // MARK: - Tab unload (RAM reclaim) — inert unless `tabUnloadPolicy != .keepAll`

    /// Whether any unload bookkeeping runs at all. `.keepAll` keeps every code path
    /// below behind a fast-return guard, so the default behaves exactly as before.
    private lazy var unloadsTabs: Bool =
        configuration.tabUnloadPolicy.keepRecentInactive != .max
        || configuration.tabUnloadPolicy.dropsToActiveWhenWindowResignsKey
    /// Tab IDs in least-recent → most-recent order; the active tab is always last.
    private var mruTabIDs: [String] = []
    private var pendingUnloadTask: Task<Void, Never>?
    private var idleObserverToken: NSObjectProtocol?

    init(configuration: SettingsConfiguration, router: SettingsRouter) {
        self.configuration = configuration
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let background = NSView()
        background.wantsLayer = true
        self.view = background
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        view.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        navigationSubscription = router.$navigationRequest
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                self?.handleNavigationRequest(request)
            }
    }

    func showTab(_ tabID: String) {
        guard tabID != currentTabID else { return }

        transitionGeneration &+= 1
        let generation = transitionGeneration
        let oldView = currentTabView
        let animate = oldView != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let newView = controller(for: tabID).view
        installTabViewIfNeeded(newView)
        removeInactiveTabViews(keeping: [oldView, newView].compactMap { $0 })
        containerView.layoutSubtreeIfNeeded()

        currentTabView = newView
        currentTabID = tabID
        installIdlePolicyObserverIfNeeded()

        guard let oldView, animate else {
            newView.alphaValue = 1
            oldView?.removeFromSuperview()
            scheduleUnloadEnforcement()
            return
        }

        newView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            newView.animator().alphaValue = 1
            oldView.animator().alphaValue = 0
        } completionHandler: { [weak self, weak oldView, weak newView] in
            MainActor.assumeIsolated {
                guard let self, let newView,
                      self.transitionGeneration == generation,
                      self.currentTabView === newView else { return }
                oldView?.removeFromSuperview()
                self.scheduleUnloadEnforcement()
            }
        }
    }

    func tearDown() {
        navigationSubscription?.cancel()
        navigationSubscription = nil
        pendingNavigationTask?.cancel()
        pendingNavigationTask = nil
        pendingUnloadTask?.cancel()
        pendingUnloadTask = nil
        if let idleObserverToken {
            NotificationCenter.default.removeObserver(idleObserverToken)
            self.idleObserverToken = nil
        }
        mruTabIDs.removeAll()
        currentTabView?.removeFromSuperview()
        currentTabView = nil
        currentTabID = nil
        for (_, controller) in cache {
            controller.prepareForMemoryRelease()
            if controller.isViewLoaded { controller.view.removeFromSuperview() }
            controller.removeFromParent()
        }
        cache.removeAll()
        lastHandledRequestID = nil
        containerView.subviews.forEach { $0.removeFromSuperview() }
        SettingsRowView.releaseSharedCaches()
    }

    // MARK: - Controller factory

    private func controller(for tabID: String) -> SettingsTabViewController {
        touchMRU(tabID)
        if let cached = cache[tabID] { return cached }
        guard let tab = configuration.tab(for: tabID) else {
            fatalError("No tab registered for id \(tabID)")
        }
        let controller = configuration.contentProvider(tab, router)
        cache[tabID] = controller
        addChild(controller)
        return controller
    }

    private func handleNavigationRequest(_ request: SettingsNavigationRequest) {
        guard lastHandledRequestID != request.requestID else { return }
        lastHandledRequestID = request.requestID

        let didSwitchTab = currentTabID != request.tabID
        if didSwitchTab {
            showTab(request.tabID)
        } else {
            _ = controller(for: request.tabID)
        }

        let navigator = controller(for: request.tabID)
        pendingNavigationTask?.cancel()
        let expectedTab = request.tabID
        pendingNavigationTask = Task { @MainActor [weak self] in
            if didSwitchTab { await Task.yield() }
            guard let self, !Task.isCancelled,
                  self.currentTabID == expectedTab,
                  self.currentTabView != nil else { return }
            navigator.handleNavigationRequest(request)
        }
    }

    private func installTabViewIfNeeded(_ tabView: NSView) {
        tabView.translatesAutoresizingMaskIntoConstraints = false
        if tabView.superview !== containerView {
            containerView.addSubview(tabView)
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: containerView.topAnchor),
                tabView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                tabView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                tabView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            return
        }
        containerView.addSubview(tabView, positioned: .above, relativeTo: nil)
    }

    private func removeInactiveTabViews(keeping viewsToKeep: [NSView]) {
        let keep = Set(viewsToKeep.map(ObjectIdentifier.init))
        for subview in containerView.subviews where !keep.contains(ObjectIdentifier(subview)) {
            subview.removeFromSuperview()
        }
    }

    // MARK: - Tab unload

    private func touchMRU(_ tabID: String) {
        guard unloadsTabs else { return }
        if let index = mruTabIDs.firstIndex(of: tabID) { mruTabIDs.remove(at: index) }
        mruTabIDs.append(tabID)
    }

    /// Defers eviction one runloop turn so a heavy `prepareForMemoryRelease` never
    /// shares a frame with the just-finished crossfade. Coalesces repeated calls.
    private func scheduleUnloadEnforcement(dropToActiveOnly: Bool = false) {
        guard unloadsTabs else { return }
        pendingUnloadTask?.cancel()
        pendingUnloadTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.enforceUnloadPolicy(dropToActiveOnly: dropToActiveOnly)
        }
    }

    private func enforceUnloadPolicy(dropToActiveOnly: Bool) {
        guard unloadsTabs, let currentTabID else { return }
        let keepInactive = dropToActiveOnly ? 0 : configuration.tabUnloadPolicy.keepRecentInactive
        guard keepInactive != .max else { return }

        var keep: Set<String> = [currentTabID]
        if keepInactive > 0 {
            for tabID in mruTabIDs.reversed() where tabID != currentTabID {
                keep.insert(tabID)
                if keep.count >= keepInactive + 1 { break }
            }
        }

        for (tabID, controller) in cache where !keep.contains(tabID) {
            evict(controller, tabID: tabID)
        }
    }

    private func evict(_ controller: SettingsTabViewController, tabID: String) {
        // Never tear down a controller whose view is still on screen (e.g. the old
        // view mid-crossfade) — that would visibly snap the animation.
        if controller.isViewLoaded, controller.view.superview === containerView { return }
        controller.prepareForMemoryRelease()
        if controller.isViewLoaded { controller.view.removeFromSuperview() }
        controller.removeFromParent()
        cache.removeValue(forKey: tabID)
        if let index = mruTabIDs.firstIndex(of: tabID) { mruTabIDs.remove(at: index) }
    }

    private func installIdlePolicyObserverIfNeeded() {
        guard unloadsTabs,
              configuration.tabUnloadPolicy.dropsToActiveWhenWindowResignsKey,
              idleObserverToken == nil,
              let window = view.window else { return }
        idleObserverToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleUnloadEnforcement(dropToActiveOnly: true)
            }
        }
    }
}
