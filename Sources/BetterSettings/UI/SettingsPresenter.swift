//
//  SettingsPresenter.swift
//  BetterSettings
//
//  Owns the settings window's lifecycle so adopters don't have to: lazy
//  creation, bring-to-front activation, optional free-on-close to reclaim RAM,
//  and robust reopen (rebuilds a fresh window whenever the previous one is gone).
//
//  Hold one presenter and call `show()` — repeatedly, in any order — and it
//  always surfaces a live, key, active window.
//

import AppKit

@MainActor
public final class SettingsPresenter {

    public enum CloseBehavior {
        /// Tear down the whole window tree when the user closes it (reclaims the
        /// memory the controllers, gradient layers and images hold), and rebuild
        /// lazily on the next `show()`.
        case releaseOnClose
        /// Keep the controller alive across closes; reopening re-shows the same
        /// window with its state intact.
        case keepAlive
    }

    private let makeConfiguration: () -> SettingsConfiguration
    private let closeBehavior: CloseBehavior
    private let initialTabID: String?

    private var controller: SettingsWindowController?
    private var closeObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - closeBehavior: Whether to free the window tree on close (default) or
    ///     keep it resident.
    ///   - initialTabID: Tab selected the first time the window is built.
    ///   - configuration: Builds the configuration; called each time a window is
    ///     (re)created, so it can reflect current app state.
    public init(
        closeBehavior: CloseBehavior = .releaseOnClose,
        initialTabID: String? = nil,
        configuration: @escaping () -> SettingsConfiguration
    ) {
        self.closeBehavior = closeBehavior
        self.initialTabID = initialTabID
        self.makeConfiguration = configuration
    }

    /// Shows the settings window, bringing it forward as key + active. Creates a
    /// fresh window when none exists, or when a prior one was already closed /
    /// released, so reopening after closing always works.
    public func show(selecting tabID: String? = nil) {
        if controller == nil || controller?.window == nil {
            teardown()
            createController()
        }
        controller?.show(selecting: tabID)
    }

    /// Orders the window out without tearing it down.
    public func hide() {
        controller?.window?.orderOut(nil)
    }

    /// Explicitly tears the window down now (e.g. on app termination).
    public func close() {
        teardown()
    }

    private func createController() {
        let controller = SettingsWindowController(
            configuration: makeConfiguration(),
            initialTabID: initialTabID
        )
        self.controller = controller

        guard closeBehavior == .releaseOnClose, let window = controller.window else { return }

        // Defer teardown until after AppKit's close sequence unwinds (`queue:
        // .main`). `show()` rebuilds lazily on the next open.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.teardown() }
        }
    }

    private func teardown() {
        if let token = closeObserver {
            NotificationCenter.default.removeObserver(token)
            closeObserver = nil
        }
        controller?.tearDownAndReleaseWindow()
        controller = nil
    }
}
