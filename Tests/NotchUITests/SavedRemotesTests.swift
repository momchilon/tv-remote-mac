import XCTest
@testable import NotchUI

@MainActor
final class SavedRemotesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SavedRemotesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testDisplayLabelsDistinguishTVsWithTheSameName() {
        let first = SavedRemote(host: "192.168.1.20", name: "Samsung TV")
        let second = SavedRemote(host: "192.168.1.21", name: "Samsung TV")
        XCTAssertEqual(first.displayLabel, "Samsung TV · 192.168.1.20")
        XCTAssertNotEqual(first.displayLabel, second.displayLabel)
        XCTAssertEqual(SavedRemote(host: "192.168.1.22", name: "192.168.1.22").displayLabel, "192.168.1.22")
    }

    func testSaveTrimsAndSelectsProfile() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            let remote = store.save(host: " 192.168.1.20\n", name: " Living room \n")
            XCTAssertEqual(remote, SavedRemote(host: "192.168.1.20", name: "Living room"))
            XCTAssertEqual(remote?.id, "192.168.1.20")
            XCTAssertEqual(store.remotes, [remote!])
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
            XCTAssertEqual(defaults.string(forKey: "tvHost"), "192.168.1.20")
        }
    }

    func testInvalidHostsAreRejectedWithoutChangingState() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            store.save(host: "192.168.1.20", name: "TV")
            for host in ["", "tv.local", "::1", "127.0.0.1", "8.8.8.8", "192.168.1", "192.168.1.256", "192.168.01.2", "192.168.1.2:8002", "192.168.1.-1", "192.168.1.２", "192.168.1.2/path"] {
                XCTAssertFalse(SavedRemotesStore.isValidHost(host), host)
                XCTAssertNil(store.save(host: host, name: "Bad"), host)
            }
            XCTAssertEqual(store.remotes, [SavedRemote(host: "192.168.1.20", name: "TV")])
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
            for host in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.0.1", "169.254.1.2"] {
                XCTAssertTrue(SavedRemotesStore.isValidHost(host), host)
            }
        }
    }

    func testProfilesPersistAcrossStoreInstances() throws {
        try withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            store.save(host: "192.168.1.20", name: "Living room")
            store.save(host: "10.0.0.2", name: "Bedroom")
            let data = try XCTUnwrap(defaults.data(forKey: "savedRemotes"))
            XCTAssertEqual(try JSONDecoder().decode([SavedRemote].self, from: data), store.remotes)
            let restored = SavedRemotesStore(defaults: defaults)
            XCTAssertEqual(restored.remotes, store.remotes)
            XCTAssertEqual(restored.selectedHost, "10.0.0.2")
        }
    }

    func testMigratesLegacyHostOnce() {
        withDefaults { defaults in
            defaults.set(" 192.168.1.20\n", forKey: "tvHost")
            let store = SavedRemotesStore(defaults: defaults)
            XCTAssertEqual(store.remotes, [SavedRemote(host: "192.168.1.20", name: "192.168.1.20")])
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
            XCTAssertNotNil(defaults.data(forKey: "savedRemotes"))
            XCTAssertEqual(SavedRemotesStore(defaults: defaults).remotes, store.remotes)
        }
    }

    func testSavingExistingHostRenamesWithoutDuplicateAndSelectsIt() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            store.save(host: "192.168.1.20", name: "Old")
            store.save(host: "10.0.0.2", name: "Bedroom")
            store.save(host: " 192.168.1.20 ", name: " Renamed ")
            XCTAssertEqual(store.remotes, [SavedRemote(host: "192.168.1.20", name: "Renamed"), SavedRemote(host: "10.0.0.2", name: "Bedroom")])
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
            XCTAssertEqual(SavedRemotesStore(defaults: defaults).remotes, store.remotes)
        }
    }

    func testWhitespaceOnlyNameFallsBackToHost() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            XCTAssertEqual(store.save(host: "10.0.0.2", name: " \n\t")?.name, "10.0.0.2")
        }
    }

    func testSelectKnownHostPersistsAndUnknownHostIsIgnored() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            store.save(host: "192.168.1.20", name: "TV")
            store.save(host: "10.0.0.2", name: "TV")
            XCTAssertEqual(store.remotes.count, 2, "Different TVs may share a name")
            store.select(host: "192.168.1.20")
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
            XCTAssertEqual(defaults.string(forKey: "tvHost"), "192.168.1.20")
            XCTAssertEqual(SavedRemotesStore(defaults: defaults).selectedHost, "192.168.1.20")
            store.select(host: "10.0.0.99")
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
        }
    }

    func testRemovingSelectedUsesFirstRemainingThenClearsSelection() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            store.save(host: "192.168.1.20", name: "First")
            store.save(host: "10.0.0.2", name: "Second")
            store.save(host: "10.0.0.3", name: "Third")
            store.remove(host: "10.0.0.3")
            XCTAssertEqual(store.remotes.map(\.host), ["192.168.1.20", "10.0.0.2"])
            XCTAssertEqual(store.selectedHost, "192.168.1.20")
            XCTAssertEqual(SavedRemotesStore(defaults: defaults).selectedHost, "192.168.1.20")
            store.remove(host: "192.168.1.20")
            XCTAssertEqual(store.selectedHost, "10.0.0.2")
            store.remove(host: "10.0.0.2")
            XCTAssertTrue(store.remotes.isEmpty)
            XCTAssertEqual(store.selectedHost, "")
            XCTAssertTrue((defaults.string(forKey: "tvHost") ?? "").isEmpty)
            let restored = SavedRemotesStore(defaults: defaults)
            XCTAssertTrue(restored.remotes.isEmpty)
            XCTAssertEqual(restored.selectedHost, "")
        }
    }

    func testRemovingNonselectedAndUnknownPreservesSelectionAndOtherData() {
        withDefaults { defaults in
            defaults.set("aa:bb:cc:dd:ee:ff", forKey: "mac-192.168.1.20")
            defaults.set("unrelated", forKey: "otherPreference")
            let store = SavedRemotesStore(defaults: defaults)
            store.save(host: "192.168.1.20", name: "First")
            store.save(host: "10.0.0.2", name: "Second")
            store.save(host: "10.0.0.3", name: "Third")
            store.remove(host: "192.168.1.20")
            XCTAssertEqual(store.remotes.map(\.host), ["10.0.0.2", "10.0.0.3"])
            XCTAssertEqual(store.selectedHost, "10.0.0.3")
            store.remove(host: "10.0.0.99")
            XCTAssertEqual(store.selectedHost, "10.0.0.3")
            XCTAssertEqual(SavedRemotesStore(defaults: defaults).selectedHost, "10.0.0.3")
            XCTAssertEqual(defaults.string(forKey: "mac-192.168.1.20"), "aa:bb:cc:dd:ee:ff")
            XCTAssertEqual(defaults.string(forKey: "otherPreference"), "unrelated")
        }
    }

    func testInvalidLegacyHostIsNotMigratedOrSelected() {
        withDefaults { defaults in
            defaults.set("tv.local", forKey: "tvHost")
            let store = SavedRemotesStore(defaults: defaults)
            XCTAssertTrue(store.remotes.isEmpty)
            XCTAssertEqual(store.selectedHost, "")
            XCTAssertTrue((defaults.string(forKey: "tvHost") ?? "").isEmpty)
        }
    }

    func testEmptyStoreHasNoSelection() {
        withDefaults { defaults in
            let store = SavedRemotesStore(defaults: defaults)
            XCTAssertEqual(store.remotes, [])
            XCTAssertEqual(store.selectedHost, "")
        }
    }
}
