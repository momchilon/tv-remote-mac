import Foundation

/// Presentation metadata is kept separate from the transport's single command allowlist.
enum RemoteControlGroup: String, CaseIterable {
    case navigation = "Navigation & channels"
    case numbers = "Number pad"
    case colours = "Colour keys"
    case playback = "Playback & recording"
    case television = "TV & menus"
    case inputs = "Direct inputs · model-dependent"
    case picture = "Picture · model-dependent"
    case sound = "Sound & accessibility"
    case multiview = "Multi-view & PiP · model-dependent"
    case extras = "Media & timers · model-dependent"

    var isPrimary: Bool { self == .navigation || self == .numbers || self == .colours }
}

struct RemoteControl: Identifiable {
    let command: PanelCommand
    let title: String
    let symbol: String
    let group: RemoteControlGroup
    var id: String { command.rawValue }
    var help: String { "\(title) — \(command.rawValue). Support depends on the TV, input and active app." }

    init(_ command: PanelCommand, _ title: String, _ symbol: String, _ group: RemoteControlGroup) {
        self.command = command; self.title = title; self.symbol = symbol; self.group = group
    }
}

struct RemoteControlSection: Identifiable {
    let group: RemoteControlGroup
    let controls: [RemoteControl]
    var id: String { group.rawValue }
}

enum RemoteControls {
    // Power is deliberately absent: it must use the existing confirmation flow.
    static let all: [RemoteControl] = [
        .init(.up, "Up", "chevron.up", .navigation),
        .init(.down, "Down", "chevron.down", .navigation),
        .init(.left, "Left", "chevron.left", .navigation),
        .init(.right, "Right", "chevron.right", .navigation),
        .init(.enter, "OK / Select", "checkmark", .navigation),
        .init(.back, "Back", "arrow.uturn.backward", .navigation),
        .init(.home, "Home", "house", .navigation),
        .init(.source, "Source", "rectangle.on.rectangle", .navigation),
        .init(.exit, "Exit", "xmark", .navigation),
        .init(.volumeUp, "Volume up", "speaker.plus", .navigation),
        .init(.volumeDown, "Volume down", "speaker.minus", .navigation),
        .init(.mute, "Mute / Unmute", "speaker.slash", .navigation),
        .init(.channelUp, "Channel up", "chevron.up", .navigation),
        .init(.channelDown, "Channel down", "chevron.down", .navigation),
        .init(.guide, "Guide", "list.bullet.rectangle", .navigation),

        .init(.digit1, "1", "1.circle", .numbers),
        .init(.digit2, "2", "2.circle", .numbers),
        .init(.digit3, "3", "3.circle", .numbers),
        .init(.digit4, "4", "4.circle", .numbers),
        .init(.digit5, "5", "5.circle", .numbers),
        .init(.digit6, "6", "6.circle", .numbers),
        .init(.digit7, "7", "7.circle", .numbers),
        .init(.digit8, "8", "8.circle", .numbers),
        .init(.digit9, "9", "9.circle", .numbers),
        .init(.plus100, "+100", "plus", .numbers),
        .init(.digit0, "0", "0.circle", .numbers),
        .init(.previousChannel, "Previous channel", "arrow.uturn.backward", .numbers),

        .init(.red, "A · Red", "a.circle", .colours),
        .init(.green, "B · Green", "b.circle", .colours),
        .init(.yellow, "C · Yellow", "c.circle", .colours),
        .init(.blue, "D · Blue", "d.circle", .colours),

        .init(.rewind, "Rewind", "backward.fill", .playback),
        .init(.play, "Play", "play.fill", .playback),
        .init(.pause, "Pause", "pause.fill", .playback),
        .init(.stop, "Stop", "stop.fill", .playback),
        .init(.fastForward, "Fast forward", "forward.fill", .playback),
        .init(.record, "Record", "record.circle", .playback),
        .init(.repeatPlayback, "Repeat", "repeat", .playback),
        .init(.instantReplay, "Instant replay", "gobackward", .playback),
        .init(.quickReplay, "Quick replay", "backward.end", .playback),

        .init(.menu, "TV menu", "line.3.horizontal", .television),
        .init(.tools, "Tools", "wrench", .television),
        .init(.info, "Info", "info.circle", .television),
        .init(.channelList, "Channel list", "list.number", .television),
        .init(.favourites, "Favourites", "star", .television),
        .init(.liveTV, "Live TV", "tv", .television),
        .init(.tvMode, "TV mode", "tv", .television),
        .init(.digitalTV, "Digital TV", "tv", .television),
        .init(.antenna, "Antenna", "antenna.radiowaves.left.and.right", .television),
        .init(.signalInfo, "Signal info", "antenna.radiowaves.left.and.right", .television),
        .init(.smartHub, "Smart Hub", "square.grid.2x2", .television),
        .init(.appList, "App list", "square.grid.3x3", .television),
        .init(.more, "More / keypad", "ellipsis", .television),
        .init(.help, "Help", "questionmark.circle", .television),
        .init(.ambient, "Ambient", "photo", .television),
        .init(.anynet, "Anynet+", "link", .television),
        .init(.deviceConnect, "Connect device", "cable.connector", .television),

        .init(.hdmi, "Cycle HDMI", "cable.connector", .inputs),
        .init(.hdmi1, "HDMI 1", "1.square", .inputs),
        .init(.hdmi2, "HDMI 2", "2.square", .inputs),
        .init(.hdmi3, "HDMI 3", "3.square", .inputs),
        .init(.hdmi4, "HDMI 4", "4.square", .inputs),
        .init(.av1, "AV 1", "1.square", .inputs),
        .init(.av2, "AV 2", "2.square", .inputs),
        .init(.av3, "AV 3", "3.square", .inputs),
        .init(.component1, "Component 1", "1.square", .inputs),
        .init(.component2, "Component 2", "2.square", .inputs),
        .init(.sVideo1, "S-Video 1", "1.square", .inputs),
        .init(.sVideo2, "S-Video 2", "2.square", .inputs),
        .init(.sVideo3, "S-Video 3", "3.square", .inputs),
        .init(.pc, "PC", "desktopcomputer", .inputs),
        .init(.dvi, "DVI", "cable.connector", .inputs),

        .init(.pictureMode, "Picture mode", "slider.horizontal.3", .picture),
        .init(.pictureSize, "Picture size", "arrow.up.left.and.arrow.down.right", .picture),
        .init(.aspect, "Aspect ratio", "aspectratio", .picture),
        .init(.widescreen, "16:9", "rectangle", .picture),
        .init(.standardAspect, "4:3", "rectangle", .picture),
        .init(.zoom1, "Zoom 1", "1.magnifyingglass", .picture),
        .init(.zoom2, "Zoom 2", "magnifyingglass", .picture),
        .init(.zoomIn, "Zoom in", "plus.magnifyingglass", .picture),
        .init(.zoomOut, "Zoom out", "minus.magnifyingglass", .picture),
        .init(.zoomMove, "Move zoom", "arrow.up.and.down.and.arrow.left.and.right", .picture),
        .init(.panorama, "Panorama", "pano", .picture),
        .init(.dynamicPicture, "Dynamic", "sun.max", .picture),
        .init(.standardPicture, "Standard", "circle.lefthalf.filled", .picture),
        .init(.moviePicture, "Movie", "film", .picture),
        .init(.freezePicture, "Freeze picture", "pause.rectangle", .picture),
        .init(.game, "Game", "gamecontroller", .picture),
        .init(.energySaving, "Energy saving", "leaf", .picture),

        .init(.soundEffect, "Sound effect", "waveform", .sound),
        .init(.surround, "SRS surround", "speaker.wave.3", .sound),
        .init(.audioTrack, "Audio / MTS", "waveform", .sound),
        .init(.mainSubAudio, "Main / sub audio", "speaker.wave.2", .sound),
        .init(.audioDescription, "Audio description", "ear", .sound),
        .init(.captions, "Captions", "captions.bubble", .sound),
        .init(.subtitles, "Subtitles", "text.bubble", .sound),
        .init(.teletext, "Teletext", "doc.text", .sound),
        .init(.teletextSubpage, "Text subpage", "doc.on.doc", .sound),

        .init(.multiView, "Multi-view", "rectangle.split.2x1", .multiview),
        .init(.pip, "PiP on / off", "pip", .multiview),
        .init(.pipChannelUp, "PiP channel +", "chevron.up", .multiview),
        .init(.pipChannelDown, "PiP channel −", "chevron.down", .multiview),
        .init(.pipSwap, "Swap PiP", "arrow.left.arrow.right", .multiview),
        .init(.pipSize, "PiP size", "arrow.up.left.and.arrow.down.right", .multiview),
        .init(.pipScan, "PiP scan", "magnifyingglass", .multiview),

        .init(.mediaLink, "Media link", "play.rectangle", .extras),
        .init(.discMenu, "Disc menu", "opticaldisc", .extras),
        .init(.topMenu, "Top menu", "menubar.rectangle", .extras),
        .init(.dvr, "DVR", "externaldrive", .extras),
        .init(.dvrMenu, "DVR menu", "list.bullet.rectangle", .extras),
        .init(.sleep, "Sleep timer", "moon", .extras),
        .init(.clock, "Show clock", "clock", .extras),
        .init(.timer, "Set timer", "timer", .extras)
    ]

    private static let byCommand = Dictionary(uniqueKeysWithValues: all.map { ($0.command, $0) })
    static func control(for command: PanelCommand) -> RemoteControl? { byCommand[command] }
    static let numberPad = all.filter { $0.group == .numbers }
    static let colours = all.filter { $0.group == .colours }
    private static let orderedSections = RemoteControlGroup.allCases.map { group in
        RemoteControlSection(group: group, controls: all.filter { $0.group == group })
    }
    private static let additionalSections = orderedSections.filter { !$0.group.isPrimary }

    static func sections(matching query: String) -> [RemoteControlSection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return additionalSections }
        return orderedSections.compactMap { section in
            if section.group.rawValue.localizedCaseInsensitiveContains(query) { return section }
            let controls = section.controls.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.command.rawValue.localizedCaseInsensitiveContains(query)
            }
            return controls.isEmpty ? nil : RemoteControlSection(group: section.group, controls: controls)
        }
    }
}
