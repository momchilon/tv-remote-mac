import XCTest
import AppKit
@testable import NotchUI

@MainActor
final class MenuBarControllerTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1",
                          "UI tests require explicit opt-in: RUN_UI_TESTS=1")
    }

    func testStartsHiddenWithRemoteIconAndClosesOnOutsideClick() throws {
        _ = NSApplication.shared
        let model = PanelModel()
        let controller = MenuBarController(model: model)
        defer { controller.stop() }
        XCTAssertFalse(controller.popover.isShown)
        XCTAssertFalse(model.expanded)
        XCTAssertEqual(controller.popover.behavior, .transient)
        XCTAssertEqual(controller.popover.contentSize.width, 300)
        XCTAssertEqual(controller.popover.contentSize.height, 250)
        XCTAssertNotNil(NSImage(systemSymbolName: MenuBarController.iconSymbol, accessibilityDescription: nil))
        XCTAssertEqual(MenuBarController.iconSymbol, "appletvremote.gen4")
        XCTAssertNotNil(controller.statusItem.button?.image)
        XCTAssertEqual(controller.statusItem.button?.toolTip, "TV Remote — click to open")
    }

    func testClickOpensUnderItsOwnIconAndSecondClickCloses() throws {
        let model = PanelModel()
        model.host = "192.168.1.100"
        model.connection = .ready
        let controller = MenuBarController(model: model)
        defer { controller.stop() }
        controller.popover.animates = false
        let button = try XCTUnwrap(controller.statusItem.button)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        button.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(controller.popover.isShown)
        let window = try XCTUnwrap(controller.popover.contentViewController?.view.window)
        let anchor = try XCTUnwrap(button.window).convertToScreen(button.convert(button.bounds, to: nil))
        let contentView = try XCTUnwrap(controller.popover.contentViewController?.view)
        let contentFrame = window.convertToScreen(contentView.convert(contentView.bounds, to: nil))
        // The native arrow overlaps the anchor slightly; the controls must not.
        XCTAssertLessThanOrEqual(contentFrame.maxY, anchor.minY)
        XCTAssertLessThanOrEqual(window.frame.minX, anchor.midX)
        XCTAssertGreaterThanOrEqual(window.frame.maxX, anchor.midX)
        button.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(controller.popover.isShown)
        XCTAssertFalse(model.expanded)
    }

    func testSettingsResizePopoverWithoutOpeningIt() {
        let model = PanelModel()
        let controller = MenuBarController(model: model)
        defer { controller.stop() }
        model.settings = true
        XCTAssertEqual(controller.popover.contentSize.height, 480)
        XCTAssertFalse(controller.popover.isShown)
        model.settings = false
        XCTAssertEqual(controller.popover.contentSize.height, 250)
    }

    func testTVStatusUpdatesNeverShowPopover() {
        let model = PanelModel()
        let controller = MenuBarController(model: model)
        defer { controller.stop() }
        for state: PanelConnection in [.connecting, .approval, .ready, .failed("Offline"), .disconnected] {
            model.connection = state
            XCTAssertFalse(controller.popover.isShown)
            XCTAssertFalse(model.expanded)
        }
    }

    func testClosingClearsTransientUIStateWithoutLosingTVSettings() {
        let model = PanelModel()
        let active = SavedRemote(host: "192.168.1.100", name: "Living room")
        model.savedRemotes = [active]
        model.selectedRemoteHost = active.host
        model.host = active.host
        model.connection = .ready
        let controller = MenuBarController(model: model)
        defer { controller.stop() }
        model.showSettings()
        controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertFalse(model.settings)
        XCTAssertFalse(model.expanded)
        XCTAssertEqual(model.host, "192.168.1.100")
        XCTAssertEqual(model.connection, .ready)
    }
}
