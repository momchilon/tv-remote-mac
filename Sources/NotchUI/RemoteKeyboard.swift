import Foundation

extension PanelModel {
    /// Local to the focused popover. A text editor always owns its keystrokes.
    @discardableResult
    public func handleKey(_ code: UInt16, editingText: Bool) -> Bool {
        guard ready, !settings, !confirmingPower, !editingText else { return false }
        let command: PanelCommand
        switch code {
        case 126: command = .up
        case 125: command = .down
        case 123: command = .left
        case 124: command = .right
        case 36, 76: command = .enter
        case 51: command = .back
        case 24: command = .volumeUp
        case 27: command = .volumeDown
        case 46: command = .mute
        case 29, 82: command = .digit0
        case 18, 83: command = .digit1
        case 19, 84: command = .digit2
        case 20, 85: command = .digit3
        case 21, 86: command = .digit4
        case 23, 87: command = .digit5
        case 22, 88: command = .digit6
        case 26, 89: command = .digit7
        case 28, 91: command = .digit8
        case 25, 92: command = .digit9
        case 116: command = .channelUp
        case 121: command = .channelDown
        default: return false
        }
        send(command)
        return true
    }
}
