import XCTest
import AppKit
import SwiftUI
@testable import NotchUI

@MainActor
final class PanelViewTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1",
                          "UI tests require explicit opt-in: RUN_UI_TESTS=1")
    }

    func testRemoteRendersAtActualNotchSize() throws {
        let model = PanelModel()
        model.expanded = true
        model.connection = .ready
        try render(model, name: "remote", height: 250)
    }

    func testSettingsRenderAtActualNotchSize() throws {
        let model = PanelModel()
        model.host = "192.168.1.100"
        model.showSettings()
        try render(model, name: "settings", height: 292)
    }

    func testOfflineAndApprovalStatesRender() throws {
        let model = PanelModel()
        model.expanded = true
        try render(model, name: "offline", height: 250)
        model.connection = .approval
        try render(model, name: "approval", height: 250)
    }

    func testPowerConfirmationRendersWithoutSendingCommand() throws {
        let model = PanelModel()
        model.expanded = true
        model.connection = .ready
        model.requestPower()
        try render(model, name: "confirm-power", height: 250)
    }

    private func render(_ model: PanelModel, name: String, height: CGFloat) throws {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: RemotePanelView(model: model))
        view.sizingOptions = []
        let frame = NSRect(x: -10000, y: -10000, width: 300, height: height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrame(frame, display: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.bounds.width, 300)
        XCTAssertEqual(view.bounds.height, height)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tv-remote-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        XCTAssertGreaterThan(data.count, 1500)
    }
}
