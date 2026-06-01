//
//  SettingsSidebarViewController.swift
//  BetterSettings
//
//  Source-list sidebar: a search field above an NSTableView that shows either
//  the tab list (macOS-style gradient icon badges + rounded selection) or, while
//  searching, scored search results with a "Tab · Section" subtitle. An optional
//  footer toggles row subtitle visibility ("Show Details").
//

import AppKit
import Combine
import QuartzCore

@MainActor
final class SettingsSidebarViewController: NSViewController,
    NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate {

    private enum Metrics {
        static let horizontalPadding: CGFloat = 9
        static let trailingPadding: CGFloat = 6
        static let searchTopInset: CGFloat = 10
        static let searchOffsetBelowTrafficLights: CGFloat = 26
        static let searchBottomSpacing: CGFloat = 12
        static let searchHeight: CGFloat = 28
        static let tabWidth: CGFloat = 195
        static let tabHeight: CGFloat = 32
        static let searchResultHeight: CGFloat = 44
        static let contentPadding: CGFloat = 6
        static let sourceListInsetCompensation: CGFloat = 16
        static let iconContainerSize: CGFloat = 20
        static let iconSize: CGFloat = 16
        static let iconCornerRadius: CGFloat = 5
        static let titleFontSize: CGFloat = 13
        static let subtitleFontSize: CGFloat = 11
        static let searchDebounce: TimeInterval = 0.18
    }

    private enum Row: Hashable {
        case tab(String)
        case setting(SettingsSearchResult)
        case empty
    }

    private static let cellID = NSUserInterfaceItemIdentifier("BetterSettingsSidebarCell")
    private static let rowID = NSUserInterfaceItemIdentifier("BetterSettingsSidebarRow")
    private static let columnID = NSUserInterfaceItemIdentifier("BetterSettingsSidebarColumn")

    private let configuration: SettingsConfiguration
    private let router: SettingsRouter

    private let searchField = NSSearchField()
    private let tableView = ReclickableTableView()
    private let scrollView = NSScrollView()
    private let detailsToggle = NSSwitch()
    private let detailsLabel = NSTextField(labelWithString: "")
    private var searchTopConstraint: NSLayoutConstraint?

    private let searchIndex: SettingsSearchIndex
    private var rows: [Row] = []
    private var searchQuery = ""
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var routerSubscription: AnyCancellable?
    private var windowActivityObservers: [NSObjectProtocol] = []
    private var isProgrammaticSelection = false

    private var tabsByID: [String: SettingsTab] = [:]
    // Tab icon set is fixed and immutable, but configure(cell:) runs on every
    // scroll-recycle / reloadData / selection. Cache the rendered SF Symbol image
    // and the bridged gradient NSColors per tab so they aren't rebuilt each time.
    private var tabIconImageByID: [String: NSImage] = [:]
    private var gradientColorsByID: [String: (start: NSColor, end: NSColor)] = [:]

    init(configuration: SettingsConfiguration, router: SettingsRouter) {
        self.configuration = configuration
        self.router = router
        self.searchIndex = SettingsSearchIndex(items: configuration.searchItems)
        super.init(nibName: nil, bundle: nil)
        for tab in configuration.tabs {
            tabsByID[tab.id] = tab
            gradientColorsByID[tab.id] = (tab.iconStyle.gradientStart.nsColor, tab.iconStyle.gradientEnd.nsColor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSearchField()
        setupTableView()
        if configuration.showsDetailsToggle { setupDetailsToggle() } else { pinScrollViewBottomToView() }
        applySearch(query: "")

        routerSubscription = router.$selectedTabID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] tabID in
                self?.selectRow(for: tabID)
            }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installWindowActivityObservers()
        refreshVisibleRowStyles()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeWindowActivityObservers()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateSearchTopInsetRelativeToTrafficLights()
    }

    // MARK: - Setup

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.controlSize = .large
        searchField.placeholderString = configuration.searchPlaceholder
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .default
    }

    private func setupTableView() {
        tableView.onSelectedRowReclicked = { [weak self] row in
            self?.handleRepeatedClick(on: row)
        }

        let column = NSTableColumn(identifier: Self.columnID)
        column.isEditable = false
        column.width = Metrics.tabWidth
        column.minWidth = 0
        column.maxWidth = .greatestFiniteMagnitude
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = Metrics.tabHeight
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsEmptySelection = true
        tableView.floatsGroupRows = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        view.addSubview(searchField)
        view.addSubview(scrollView)

        let topConstraint = searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: Metrics.searchTopInset)
        searchTopConstraint = topConstraint

        NSLayoutConstraint.activate([
            topConstraint,
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.horizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.horizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: Metrics.searchHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Metrics.searchBottomSpacing),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func pinScrollViewBottomToView() {
        scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12).isActive = true
    }

    private func setupDetailsToggle() {
        detailsLabel.stringValue = configuration.showDetailsLabel
        detailsLabel.font = .systemFont(ofSize: 12)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        detailsToggle.controlSize = .mini
        detailsToggle.translatesAutoresizingMaskIntoConstraints = false
        detailsToggle.target = self
        detailsToggle.action = #selector(detailsToggleChanged(_:))
        detailsToggle.state = SettingsDetails.isOn ? .on : .off

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailsLabel)
        container.addSubview(detailsToggle)
        NSLayoutConstraint.activate([
            detailsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailsLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            detailsToggle.leadingAnchor.constraint(greaterThanOrEqualTo: detailsLabel.trailingAnchor, constant: 6),
            detailsToggle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailsToggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 22),
        ])

        view.addSubview(container)
        NSLayoutConstraint.activate([
            scrollView.bottomAnchor.constraint(equalTo: container.topAnchor, constant: -8),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.horizontalPadding + 4),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.horizontalPadding),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    @objc private func detailsToggleChanged(_ sender: NSSwitch) {
        let isOn = sender.state == .on
        let shouldAnimate = view.window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        guard shouldAnimate else {
            SettingsDetails.write(isOn)
            NotificationCenter.default.post(
                name: .betterSettingsShowDetailsDidChange,
                object: nil,
                userInfo: ["isOn": isOn]
            )
            return
        }

        let coordinator = SettingsDetailsAnimationCoordinator.shared
        let animationGeneration = coordinator.beginToggleAnimation()
        let scrollAnchor = coordinator.captureScrollAnchor()

        coordinator.prepareActiveTabLayoutForAnimation()
        SettingsDetails.write(isOn)

        let baseUserInfo: [String: Any] = ["isOn": isOn, "animationGeneration": animationGeneration]

        // Phase 1: fade subtitles out (no-op when revealing).
        NotificationCenter.default.post(
            name: .betterSettingsShowDetailsDidChange,
            object: nil,
            userInfo: baseUserInfo.merging([
                "animationPhase": SettingsDetailsAnimationCoordinator.ToggleAnimationPhase.subtitleFade.rawValue
            ]) { _, new in new }
        )

        let runLayoutTransition = {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = SettingsDetailsAnimationCoordinator.sectionResizeDuration(for: isOn)
                context.timingFunction = SettingsDetailsAnimationCoordinator.sectionResizeTiming(for: isOn)
                context.allowsImplicitAnimation = true

                // Phase 2: animate section heights inside this group.
                NotificationCenter.default.post(
                    name: .betterSettingsShowDetailsDidChange,
                    object: nil,
                    userInfo: baseUserInfo.merging([
                        "animationPhase": SettingsDetailsAnimationCoordinator.ToggleAnimationPhase.layoutTransition.rawValue
                    ]) { _, new in new }
                )

                coordinator.flushLayouts()
                coordinator.animateScrollCompensation(from: scrollAnchor)
            }, completionHandler: {
                Task { @MainActor in
                    coordinator.finishToggleAnimation(generation: animationGeneration)
                }
            })
        }

        let delay = SettingsDetailsAnimationCoordinator.layoutPhaseDelay(for: isOn)
        if delay <= 0 {
            guard coordinator.isAnimatingToggle(generation: animationGeneration) else { return }
            runLayoutTransition()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard coordinator.isAnimatingToggle(generation: animationGeneration) else { return }
            runLayoutTransition()
        }
    }

    private func updateSearchTopInsetRelativeToTrafficLights() {
        guard let searchTopConstraint else { return }
        var topInset = Metrics.searchTopInset
        if let window = view.window, let closeButton = window.standardWindowButton(.closeButton) {
            let frameInView = view.convert(closeButton.bounds, from: closeButton)
            let topToButtonBottom = max(0, view.bounds.maxY - frameInView.minY)
            topInset = min(max(topToButtonBottom + Metrics.searchOffsetBelowTrafficLights, Metrics.searchTopInset), 140)
        }
        if abs(searchTopConstraint.constant - topInset) > 0.5 {
            searchTopConstraint.constant = topInset
        }
    }

    // MARK: - Search

    private var isSearchActive: Bool { !searchQuery.isEmpty }
    private var isSelectionEmphasized: Bool { view.window?.isKeyWindow == true }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field == searchField else { return }
        queueSearchUpdate(for: field.stringValue)
    }

    private func queueSearchUpdate(for query: String) {
        searchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applySearch(query: query)
        }
        searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.searchDebounce, execute: workItem)
    }

    private func applySearch(query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if searchQuery.isEmpty {
            rows = configuration.tabs.map { .tab($0.id) }
        } else {
            let results = searchIndex.search(query: searchQuery)
            rows = results.isEmpty ? [.empty] : results.map { .setting($0) }
        }

        tableView.reloadData()
        if isSearchActive {
            tableView.deselectAll(nil)
        } else {
            selectRow(for: router.selectedTabID)
        }
        refreshVisibleRowStyles()
    }

    // MARK: - Selection

    func selectRow(for tabID: String) {
        guard !isSearchActive else { return }
        guard let index = rows.firstIndex(of: .tab(tabID)) else { return }
        if tableView.selectedRow != index {
            isProgrammaticSelection = true
            defer { isProgrammaticSelection = false }
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        }
        refreshVisibleRowStyles()
    }

    private func handleSelection(for row: Row) {
        switch row {
        case .tab(let id): router.navigateToTabTop(id)
        case .setting(let result): router.navigateToSearchResult(result)
        case .empty: tableView.deselectAll(nil)
        }
    }

    private func handleRepeatedClick(on row: Int) {
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .tab(let id) where !isSearchActive: router.navigateToTabTop(id)
        case .setting(let result) where isSearchActive: router.navigateToSearchResult(result)
        default: break
        }
    }

    func tearDown() {
        searchDebounceWorkItem?.cancel()
        searchDebounceWorkItem = nil
        routerSubscription?.cancel()
        routerSubscription = nil
        removeWindowActivityObservers()
        tableView.onSelectedRowReclicked = nil
        tableView.delegate = nil
        tableView.dataSource = nil
        searchField.delegate = nil
        rows.removeAll()
        tabIconImageByID.removeAll()
        gradientColorsByID.removeAll()
        scrollView.documentView = nil
        view.subviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Window activity (selection emphasis)

    private func installWindowActivityObservers() {
        // Scope to this window so foreign windows' key/resign transitions don't
        // wake the observer. Installed from viewDidAppear, where the window exists.
        guard windowActivityObservers.isEmpty, let window = view.window else { return }
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification]
        windowActivityObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshVisibleRowStyles()
                }
            }
        }
    }

    private func removeWindowActivityObservers() {
        windowActivityObservers.forEach(NotificationCenter.default.removeObserver)
        windowActivityObservers.removeAll()
    }

    private func refreshVisibleRowStyles() {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.location != NSNotFound, visible.length > 0 else { return }
        let emphasized = isSelectionEmphasized
        let upper = min(NSMaxRange(visible), rows.count)
        guard visible.location < upper else { return }
        for row in visible.location..<upper {
            (tableView.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView)?.selectionEmphasized = emphasized
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarCellView)?
                .applySelectionStyle(isSelected: tableView.selectedRow == row, isEmphasized: emphasized)
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return Metrics.tabHeight }
        if case .setting = rows[row] { return Metrics.searchResultHeight }
        return Metrics.tabHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row) else { return false }
        if case .empty = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = (tableView.makeView(withIdentifier: Self.rowID, owner: nil) as? SidebarRowView) ?? makeRowView()
        rowView.selectionEmphasized = isSelectionEmphasized
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? SidebarCellView) ?? makeCell()
        configure(cell: cell, for: rows[row])
        cell.applySelectionStyle(isSelected: tableView.selectedRow == row, isEmphasized: isSelectionEmphasized)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if isProgrammaticSelection {
            refreshVisibleRowStyles()
            return
        }
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        handleSelection(for: rows[row])
        refreshVisibleRowStyles()
    }

    // MARK: - Cell

    private func makeCell() -> SidebarCellView {
        let cell = SidebarCellView(
            iconContainerSize: Metrics.iconContainerSize,
            iconCornerRadius: Metrics.iconCornerRadius,
            contentPadding: Metrics.contentPadding,
            titleFontSize: Metrics.titleFontSize,
            subtitleFontSize: Metrics.subtitleFontSize
        )
        cell.identifier = Self.cellID
        return cell
    }

    private func makeRowView() -> SidebarRowView {
        let rowView = SidebarRowView(
            maxContentWidth: Metrics.tabWidth,
            leadingInset: Metrics.horizontalPadding,
            trailingInset: Metrics.trailingPadding
        )
        rowView.identifier = Self.rowID
        return rowView
    }

    private func configure(cell: SidebarCellView, for row: Row) {
        switch row {
        case .tab(let id):
            guard let tab = tabsByID[id] else { return }
            let gradient = gradientColorsByID[id]
                ?? (tab.iconStyle.gradientStart.nsColor, tab.iconStyle.gradientEnd.nsColor)
            cell.configureAsTab(
                title: tab.title,
                iconImage: tabSymbolImage(for: tab),
                iconScale: clampedIconSize(for: tab.iconStyle),
                gradientStart: gradient.start,
                gradientEnd: gradient.end,
                isBeta: tab.isBeta
            )
        case .setting(let result):
            cell.configureAsSearchResult(
                title: result.sidebarDisplayText,
                subtitle: result.localizedTabAndSectionTitle
            )
        case .empty:
            cell.configureAsEmpty(text: configuration.noResultsText)
        }
    }

    private func clampedIconSize(for style: SettingsTabIconStyle) -> CGFloat {
        let clampedScale = max(0.7, min(style.symbolScale, 2.0))
        return min(Metrics.iconContainerSize - 2, Metrics.iconSize * clampedScale)
    }

    private func tabSymbolImage(for tab: SettingsTab) -> NSImage? {
        if let cached = tabIconImageByID[tab.id] { return cached }
        let style = tab.iconStyle
        let pointSize = clampedIconSize(for: style)
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let colorConfig: NSImage.SymbolConfiguration
        switch style.symbolColorMode {
        case .hierarchical:
            colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: style.symbolColor.nsColor)
        case .monochrome:
            colorConfig = NSImage.SymbolConfiguration(paletteColors: [style.symbolColor.nsColor])
        }
        let config = sizeConfig.applying(colorConfig)
        let image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        if let image { tabIconImageByID[tab.id] = image }
        return image
    }
}

// MARK: - Reclickable table view

private final class ReclickableTableView: NSTableView {
    var onSelectedRowReclicked: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let selectedBefore = selectedRow
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        guard clicked >= 0, selectedBefore == clicked, selectedRow == clicked else { return }
        onSelectedRowReclicked?(clicked)
    }
}
