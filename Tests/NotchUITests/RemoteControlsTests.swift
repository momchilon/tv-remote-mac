import XCTest
import AppKit
@testable import NotchUI

final class RemoteControlsTests: XCTestCase {
    func testDirectMetadataLookupMatchesCatalogueAndExcludesPower() {
        for control in RemoteControls.all {
            let found = RemoteControls.control(for: control.command)
            XCTAssertEqual(found?.id, control.id)
            XCTAssertEqual(found?.title, control.title)
            XCTAssertEqual(found?.symbol, control.symbol)
        }
        XCTAssertNil(RemoteControls.control(for: .power))
    }

    func testOptimizedSearchPreservesAllCatalogueSearchSemanticsAndOrder() {
        let queries = RemoteControls.all.flatMap { [$0.title, $0.command.rawValue] }
            + RemoteControlGroup.allCases.map(\.rawValue)
        for raw in queries {
            let query = raw.lowercased()
            let expected = RemoteControlGroup.allCases.flatMap { group in
                RemoteControls.all.filter { control in
                    control.group == group && [control.title, control.command.rawValue, group.rawValue].contains {
                        $0.localizedCaseInsensitiveContains(query)
                    }
                }
            }
            XCTAssertEqual(RemoteControls.sections(matching: "  " + query + "  ").flatMap(\.controls).map(\.id), expected.map(\.id), raw)
        }
    }

    func testAllCatalogueSymbolsExistWithoutCreatingAnyWindows() {
        for control in RemoteControls.all {
            XCTAssertNotNil(NSImage(systemSymbolName: control.symbol, accessibilityDescription: nil), control.symbol)
        }
    }

    func testSearchFindsLabelsRawCodesAndPrimaryKeysWithoutExposingPower() {
        XCTAssertEqual(RemoteControls.sections(matching: "  hDmI  ").flatMap(\.controls).map(\.command), [.hdmi, .hdmi1, .hdmi2, .hdmi3, .hdmi4])
        XCTAssertEqual(RemoteControls.sections(matching: "KEY_BLUE").flatMap(\.controls).map(\.command), [.blue])
        XCTAssertEqual(RemoteControls.sections(matching: "previous channel").flatMap(\.controls).map(\.command), [.previousChannel])
        XCTAssertEqual(RemoteControls.sections(matching: "audio description").flatMap(\.controls).map(\.command), [.audioDescription])
        XCTAssertTrue(RemoteControls.sections(matching: "no such button").isEmpty)
        XCTAssertTrue(RemoteControls.sections(matching: "KEY_POWER").isEmpty)
        XCTAssertEqual(RemoteControls.sections(matching: " \n ").flatMap(\.controls).map(\.id), RemoteControls.sections(matching: "").flatMap(\.controls).map(\.id))
    }

    func testEveryAllowedKeyHasExactlyOneLabelledControlExceptConfirmedPower() {
        let controls = RemoteControls.all
        XCTAssertEqual(Set(controls.map(\.command)), Set(PanelCommand.allCases.filter { $0 != .power }))
        XCTAssertEqual(Set(controls.map(\.id)).count, controls.count)
        XCTAssertTrue(controls.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
        XCTAssertEqual(RemoteControls.numberPad.map(\.command), [.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9, .plus100, .digit0, .previousChannel])
        XCTAssertEqual(RemoteControls.colours.map(\.command), [.red, .green, .yellow, .blue])
        let additional = RemoteControls.sections(matching: "").flatMap(\.controls)
        let primary = controls.filter { $0.group.isPrimary }
        XCTAssertEqual(Set((additional + primary).map(\.command)), Set(controls.map(\.command)))
        XCTAssertTrue(additional.allSatisfy { !$0.group.isPrimary })
    }
}
