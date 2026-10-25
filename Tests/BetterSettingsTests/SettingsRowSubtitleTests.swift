import AppKit
import XCTest
@testable import BetterSettings

/// A row's subtitle lives in a fixed-height, `clipsToBounds` container whose
/// height is measured from the text, so the measurement has to use the width the
/// label is actually laid out in. The row is wider than its text column by the
/// icon, the stack spacing and the accessory: measure against the row and a
/// subtitle that wraps inside that band is reported one line short, then loses
/// that line to the clip. Longer translations of a fitting English string land
/// in exactly that band, so this is a localization bug as much as a layout one.
///
/// The measurement width is observable: it is published as the label's
/// `preferredMaxLayoutWidth`.
@MainActor
final class SettingsRowSubtitleTests: XCTestCase {

    func testSubtitleIsMeasuredAtTheWidthItIsLaidOutIn() async throws {
        // Long enough to wrap in any column this row can get, so the measured
        // width is the column's real width rather than the text's own.
        let subtitle = String(repeating: "wrap this subtitle onto several lines ", count: 6)
        let row = SettingsRowView(icon: "gear", title: "Defaults for every shortcut",
                                  subtitle: subtitle, accessory: NSSwitch())

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        window.contentView = host
        host.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            row.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        // The real column width is only known once the row is in a window, so
        // the height resolution runs a run-loop turn later — and settling the
        // height changes the column width again, so let it converge.
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        host.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(subtitleLabel(in: row), "subtitle label not found")
        let container = try XCTUnwrap(label.superview)

        XCTAssertLessThan(container.bounds.width, row.bounds.width,
                          "row is not wider than its text column — fixture is meaningless")
        XCTAssertGreaterThan(label.bounds.height, (label.font?.boundingRectForFont.height ?? 0) * 1.5,
                             "fixture did not wrap")
        XCTAssertEqual(label.preferredMaxLayoutWidth, container.bounds.width, accuracy: 1,
                       "subtitle height was measured against the wrong view's width")
    }

    // Media Keys "Compact mode": short subtitle, accessory in a plain container. The column
    // used to size to its text and ping-pong with preferredMaxLayoutWidth until AppKit threw.
    func testTextColumnTakesTheRowsSlackNextToAPlainContainerAccessory() async throws {
        let toggle = NSSwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        let accessory = NSView()
        accessory.addSubview(toggle)
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            toggle.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            toggle.topAnchor.constraint(equalTo: accessory.topAnchor),
            toggle.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
        ])
        let row = SettingsRowView(title: "Compact mode",
                                  subtitle: "Show only the player icon and volume slider",
                                  accessory: accessory)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        window.contentView = host
        host.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            row.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        let column = try XCTUnwrap(subtitleLabel(in: row)?.superview)
        let slack = row.bounds.width - accessory.frame.maxX
        XCTAssertEqual(accessory.frame.width, toggle.fittingSize.width, accuracy: 1,
                       "the accessory container took the column's slack")
        XCTAssertEqual(slack, 0, accuracy: 1, "the accessory is not at the trailing edge")
        XCTAssertGreaterThan(column.bounds.width, 400, "the column sized to its text, not the row")
    }

    // BetterAudio's Automation tab re-sent 8 unchanged subtitles on every appear; each one
    // laid out the whole page, so the tab took over a second to show.
    func testUnchangedSubtitleDoesNotLayOutThePage() async throws {
        let subtitle = "Switch devices when one of these apps becomes active"
        let row = SettingsRowView(title: "Meeting apps", subtitle: subtitle, accessory: NSSwitch())

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let host = LayoutCountingView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        window.contentView = host
        host.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            row.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        host.needsLayout = true
        host.layoutCount = 0
        row.update(subtitle: subtitle)

        XCTAssertEqual(host.layoutCount, 0, "an unchanged subtitle forced a page layout")
    }

    func testCollapsedTitleCentersOnTheAccessoryAndExpandedTitleTopAligns() async throws {
        let suiteName = "SettingsRowSubtitleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let originalDefaults = SettingsDetails.defaults
        SettingsDetails.defaults = defaults
        defer {
            SettingsDetails.defaults = originalDefaults
            defaults.removePersistentDomain(forName: suiteName)
        }

        for isOn in [false, true] {
            SettingsDetails.write(isOn)
            let accessory = NSSwitch()
            let row = SettingsRowView(title: "Show BetterAudio HUDs",
                                      subtitle: "Show a HUD when the volume changes",
                                      accessory: accessory)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                                  styleMask: [.titled], backing: .buffered, defer: true)
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
            window.contentView = host
            host.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                row.topAnchor.constraint(equalTo: host.topAnchor),
            ])
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                await Task.yield()
            }

            let title = try XCTUnwrap(titleLabel(in: row))
            let titleFrame = title.convert(title.bounds, to: row)
            let accessoryFrame = accessory.convert(accessory.bounds, to: row)
            XCTAssertEqual(accessoryFrame.maxY, row.bounds.maxY, accuracy: 1, "the accessory left the top")
            if isOn {
                XCTAssertEqual(titleFrame.maxY, row.bounds.maxY, accuracy: 1, "expanded title left the top")
            } else {
                XCTAssertEqual(titleFrame.midY, accessoryFrame.midY, accuracy: 1, "collapsed title is not centered")
            }
        }
    }

    private func titleLabel(in row: SettingsRowView) -> NSTextField? {
        var fields: [NSTextField] = []
        func walk(_ view: NSView) {
            for subview in view.subviews {
                if let field = subview as? NSTextField { fields.append(field) }
                walk(subview)
            }
        }
        walk(row)
        return fields.max { ($0.font?.pointSize ?? 0) < ($1.font?.pointSize ?? 0) }
    }

    /// The subtitle is the smaller of the row's two labels.
    private func subtitleLabel(in row: SettingsRowView) -> NSTextField? {
        var fields: [NSTextField] = []
        func walk(_ view: NSView) {
            for subview in view.subviews {
                if let field = subview as? NSTextField { fields.append(field) }
                walk(subview)
            }
        }
        walk(row)
        return fields.min { ($0.font?.pointSize ?? 0) < ($1.font?.pointSize ?? 0) }
    }
}

private final class LayoutCountingView: NSView {
    var layoutCount = 0

    override func layout() {
        layoutCount += 1
        super.layout()
    }
}
