import XCTest
@testable import NotchUI

@MainActor
final class ExpandedRemoteTests: XCTestCase {
    func testExpandAndCollapseChangeLayoutWithoutSendingCommands() {
        let model = PanelModel()
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        XCTAssertFalse(model.fullRemote)
        XCTAssertEqual(model.panelWidth, 300)
        XCTAssertEqual(model.panelHeight, 250)
        model.toggleFullRemote()
        XCTAssertTrue(model.fullRemote)
        XCTAssertEqual(model.panelWidth, 520)
        XCTAssertEqual(model.panelHeight, 640)
        XCTAssertFalse(model.expanded, "Changing layout must not open a hidden popover")
        XCTAssertTrue(sent.isEmpty)
        model.toggleFullRemote()
        XCTAssertEqual(model.panelWidth, 300)
        XCTAssertEqual(model.panelHeight, 250)
    }

    func testCollapsingReturnsToMainControlsAndClearsSearch() {
        let model = PanelModel()
        model.toggleFullRemote()
        model.showingMoreControls = true
        model.controlQuery = "HDMI"
        model.toggleFullRemote()
        XCTAssertFalse(model.showingMoreControls)
        XCTAssertTrue(model.controlQuery.isEmpty)
    }

    func testSettingsAndClosingPreserveLayoutChoiceButClearSearch() {
        let model = PanelModel()
        model.toggleFullRemote()
        model.controlQuery = "HDMI"
        model.showSettings()
        XCTAssertEqual(model.panelWidth, 300)
        XCTAssertEqual(model.panelHeight, 480)
        model.leaveSettings()
        XCTAssertEqual(model.panelWidth, 520)
        XCTAssertEqual(model.panelHeight, 640)
        model.close()
        XCTAssertTrue(model.fullRemote)
        XCTAssertFalse(model.expanded)
        XCTAssertEqual(model.controlQuery, "")
        model.toggleFullRemote()
        XCTAssertFalse(model.fullRemote)
        XCTAssertEqual(model.controlQuery, "")
    }
}
