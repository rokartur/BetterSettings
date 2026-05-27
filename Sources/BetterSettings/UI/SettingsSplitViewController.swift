//
//  SettingsSplitViewController.swift
//  BetterSettings
//
//  Hosts the source-list sidebar on the left and the content pane on the right.
//  Locks the divider so swapping tabs of different intrinsic widths can't shift
//  the sidebar.
//

import AppKit
import Combine

@MainActor
final class SettingsSplitViewController: NSSplitViewController {

    private let configuration: SettingsConfiguration
    private let router: SettingsRouter

    private let sidebarVC: SettingsSidebarViewController
    private let contentVC: SettingsContentViewController

    /// Source-list split items render ~2pt narrower than assigned; compensate.
    private let sidebarWidthCompensation: CGFloat = 2
    private var effectiveSidebarThickness: CGFloat {
        configuration.sidebarWidth + sidebarWidthCompensation
    }

    private var routerSubscription: AnyCancellable?

    init(configuration: SettingsConfiguration, router: SettingsRouter) {
        self.configuration = configuration
        self.router = router
        self.sidebarVC = SettingsSidebarViewController(configuration: configuration, router: router)
        self.contentVC = SettingsContentViewController(configuration: configuration, router: router)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = effectiveSidebarThickness
        sidebarItem.maximumThickness = effectiveSidebarThickness
        sidebarItem.holdingPriority = .init(rawValue: NSLayoutConstraint.Priority.required.rawValue - 1)

        let contentWidth = configuration.windowSize.width - effectiveSidebarThickness
        let contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.minimumThickness = contentWidth
        contentItem.maximumThickness = contentWidth

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        splitView.dividerStyle = .thin
        splitView.setPosition(effectiveSidebarThickness, ofDividerAt: 0)

        routerSubscription = router.$selectedTabID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tabID in
                self?.contentVC.showTab(tabID)
                self?.updateWindowTitle(for: tabID)
            }

        contentVC.showTab(router.selectedTabID)
        updateWindowTitle(for: router.selectedTabID)
    }

    /// Pins the sidebar width across tab switches.
    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        dividerIndex == 0 ? effectiveSidebarThickness : proposedPosition
    }

    func selectTab(_ tabID: String) {
        if router.selectedTabID != tabID {
            router.selectedTabID = tabID
            return
        }
        sidebarVC.selectRow(for: tabID)
        updateWindowTitle(for: tabID)
    }

    func tearDown() {
        routerSubscription?.cancel()
        routerSubscription = nil
        sidebarVC.tearDown()
        contentVC.tearDown()
        while let item = splitViewItems.last {
            removeSplitViewItem(item)
        }
        splitView.subviews.forEach { $0.removeFromSuperview() }
    }

    private func updateWindowTitle(for tabID: String) {
        guard let tab = configuration.tab(for: tabID) else { return }
        view.window?.title = configuration.windowTitle(tab)
    }
}
