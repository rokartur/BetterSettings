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
        // Drives the "Show Details" toggle animation against this tab's rows.
        SettingsDetailsAnimationCoordinator.shared.setActiveTabView(newView)

        guard let oldView, animate else {
            newView.alphaValue = 1
            oldView?.removeFromSuperview()
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
            }
        }
    }

    func tearDown() {
        navigationSubscription?.cancel()
        navigationSubscription = nil
        pendingNavigationTask?.cancel()
        pendingNavigationTask = nil
        SettingsDetailsAnimationCoordinator.shared.setActiveTabView(nil)
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
    }

    // MARK: - Controller factory

    private func controller(for tabID: String) -> SettingsTabViewController {
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
}
