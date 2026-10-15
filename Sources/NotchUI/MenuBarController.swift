import AppKit
import SwiftUI
import Combine

/// A click-only menu-bar popover. No floating window, pointer monitor or hover timer.
@MainActor
public final class MenuBarController: NSObject, NSPopoverDelegate {
    public static let iconSymbol = "appletvremote.gen4"
    public let popover = NSPopover()
    public let statusItem: NSStatusItem
    private let model: PanelModel
    private var subscriptions = Set<AnyCancellable>()
    private var keyMonitor: Any?

    public init(model: PanelModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let hosting = NSHostingView(rootView: RemotePanelView(model: model))
        hosting.sizingOptions = []
        let viewController = NSViewController()
        viewController.view = hosting
        popover.contentViewController = viewController
        resize(settings: model.settings, fullRemote: model.fullRemote)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: Self.iconSymbol, accessibilityDescription: "TV remote")?
                .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            image?.isTemplate = true
            button.image = image
            button.toolTip = "TV Remote — click to open"
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.$settings.combineLatest(model.$fullRemote).dropFirst().sink { [weak self] settings, fullRemote in
            self?.resize(settings: settings, fullRemote: fullRemote)
        }
            .store(in: &subscriptions)
        model.$expanded.dropFirst().sink { [weak self] expanded in
            guard let self, !expanded, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }.store(in: &subscriptions)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown,
                  event.window === self.popover.contentViewController?.view.window,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            // Text entry (including control search) must never also send TV keys.
            let editingText = (event.window?.firstResponder as? NSTextView)?.isEditable == true
            if event.keyCode == 53 { self.popover.performClose(nil); return nil }
            return self.model.handleKey(event.keyCode, editingText: editingText) ? nil : event
        }
    }

    @objc public func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else { open(settings: model.host.isEmpty) }
    }

    public func open(settings: Bool = false) {
        guard let button = statusItem.button else { return }
        model.expanded = true
        model.settings = settings
        model.confirmingPower = false
        resize(settings: settings, fullRemote: model.fullRemote)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    public func popoverDidClose(_ notification: Notification) { model.close() }

    public func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        subscriptions.removeAll()
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func resize(settings: Bool, fullRemote: Bool) {
        let availableHeight = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let size = NSSize(width: PanelModel.width(settings: settings, fullRemote: fullRemote),
                          height: min(PanelModel.height(settings: settings, fullRemote: fullRemote), max(250, availableHeight - 40)))
        popover.contentViewController?.view.setFrameSize(size)
        popover.contentSize = size
    }

    @objc private func iconClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp, let button = statusItem.button {
            popover.performClose(nil)
            let menu = NSMenu()
            let open = menu.addItem(withTitle: "Open remote", action: #selector(openRemote), keyEquivalent: "")
            open.target = self
            let settings = menu.addItem(withTitle: "Connection…", action: #selector(openSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit TV Remote", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else { toggle() }
    }

    @objc private func openRemote() { open() }
    @objc private func openSettings() { open(settings: true) }
    @objc private func quit() { model.onQuit?() }

}
