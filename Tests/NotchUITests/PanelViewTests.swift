import XCTest
import AppKit
import SwiftUI
@testable import NotchUI

@MainActor
final class PanelViewTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1" || ProcessInfo.processInfo.environment["RUN_RENDER_TESTS"] == "1",
                          "Offscreen previews require RUN_RENDER_TESTS=1; desktop UI tests require RUN_UI_TESTS=1")
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
        try render(model, name: "settings", height: 480)
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

    func testFullRemoteRendersWithNumbersColoursAndChannelControls() throws {
        let model = PanelModel()
        model.expanded = true
        model.connection = .ready
        model.toggleFullRemote()
        try render(model, name: "full-remote", height: 640, width: 520)
        try render(model, name: "full-remote-small-screen", height: 480, width: 520)
    }

    func testControlBrowserAndSearchRenderWithoutSendingCommands() throws {
        let model = PanelModel()
        model.expanded = true
        model.connection = .ready
        model.fullRemote = true
        model.showingMoreControls = true
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        try render(model, name: "more-controls", height: 640, width: 520)
        for query in ["HDMI", "picture", "multi-view", "no such button"] {
            model.controlQuery = query
            try render(model, name: "search-" + query.replacingOccurrences(of: " ", with: "-"), height: 640, width: 520)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testExpandedOfflineAndLongRemoteNamesRender() throws {
        let model = PanelModel()
        model.expanded = true
        model.fullRemote = true
        model.savedRemotes = [SavedRemote(host: "192.168.1.100", name: "Living room Samsung television with a long name")]
        model.selectedRemoteHost = "192.168.1.100"
        model.host = model.selectedRemoteHost
        try render(model, name: "full-offline", height: 640, width: 520)
        model.host = ""
        try render(model, name: "full-setup", height: 640, width: 520)
        model.host = model.selectedRemoteHost
        model.connection = .ready
        try render(model, name: "full-long-name", height: 640, width: 520)
        model.fullRemote = false
        try render(model, name: "compact-long-name", height: 250)
    }

    func testSearchUpdatesWithinExistingOffscreenHost() throws {
        let model = PanelModel()
        model.expanded = true
        model.fullRemote = true
        model.showingMoreControls = true
        model.connection = .ready
        try render(model, name: "search-live-update", height: 640, width: 520) {
            model.controlQuery = "HDMI"
        }
    }

    private func render(_ model: PanelModel, name: String, height: CGFloat, width: CGFloat = 300, update: (() -> Void)? = nil) throws {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: RemotePanelView(model: model))
        view.sizingOptions = []
        let frame = NSRect(x: -10000, y: -10000, width: width, height: height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        window.setFrame(frame, display: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        if let update {
            update()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        }
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.bounds.width, width)
        XCTAssertEqual(view.bounds.height, height)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let directory = ProcessInfo.processInfo.environment["REMOTE_PREVIEW_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("tv-remote-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        print("PREVIEW " + directory.appendingPathComponent(name + ".png").path)
        XCTAssertGreaterThan(data.count, 1500)
    }
}
