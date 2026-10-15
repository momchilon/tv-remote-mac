import SwiftUI

/// An operate-first surface: familiar physical controls first, the full key catalogue one tab away.
@MainActor
struct ExpandedRemoteView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searching: Bool
    private enum ScrollAnchor: Hashable { case top }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 3) {
                    pageButton("Remote", more: false)
                    pageButton("More controls", more: true)
                }
                .padding(3)
                .background(.white.opacity(0.045), in: Capsule())
                Spacer()
                Text("\(PanelCommand.allCases.count) keys")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }
            if !model.ready { connectionBanner }
            if model.showingMoreControls {
                controlBrowser
            } else {
                ScrollView {
                    everydayRemote.padding(.vertical, 4)
                }
            }
            if model.ready || model.showingMoreControls {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Extended keys vary by TV, input and app.")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private func pageButton(_ title: String, more: Bool) -> some View {
        Button {
            searching = false
            model.showingMoreControls = more
            model.controlQuery = ""
        } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 14).frame(height: 28)
                .foregroundStyle(.white.opacity(model.showingMoreControls == more ? 0.95 : 0.55))
                .background(.white.opacity(model.showingMoreControls == more ? 0.10 : 0), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.showingMoreControls == more ? .isSelected : [])
    }

    private var everydayRemote: some View {
        VStack(spacing: model.ready ? 20 : 14) {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        rocker(title: "VOL", up: .volumeUp, middle: .mute, down: .volumeDown,
                               upSymbol: "plus", middleSymbol: "speaker.slash", downSymbol: "minus")
                        RemoteDirectionPad(model: model, diameter: 152)
                        rocker(title: "CH", up: .channelUp, middle: .guide, down: .channelDown,
                               upSymbol: "chevron.up", middleSymbol: "list.bullet.rectangle", downSymbol: "chevron.down")
                    }
                    HStack(spacing: 8) {
                        faceKey(.back)
                        faceKey(.home)
                        faceKey(.source)
                        faceKey(.exit)
                    }
                }
                .frame(width: 264)
                numberPad
            }
            .frame(maxWidth: .infinity)
            .disabled(!model.ready)

            colourKeys.disabled(!model.ready)

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("PLAYBACK")
                HStack(spacing: 4) {
                    transportKey(.rewind)
                    transportKey(.play)
                    transportKey(.pause)
                    transportKey(.stop)
                    transportKey(.fastForward)
                    transportKey(.record)
                }
                .padding(6)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!model.ready)

            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("TV SHORTCUTS")
                HStack(spacing: 8) {
                    faceKey(.menu)
                    faceKey(.channelList)
                    faceKey(.info)
                    faceKey(.subtitles)
                }
            }
            .disabled(!model.ready)
        }
    }

    private var numberPad: some View {
        VStack(spacing: 10) {
            sectionLabel("CHANNEL NUMBER")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(RemoteControls.numberPad) { control in
                    Button { model.send(control.command) } label: {
                        Group {
                            if control.command == .previousChannel {
                                VStack(spacing: 3) {
                                    Image(systemName: "arrow.uturn.backward").font(.system(size: 12))
                                    Text("PREV").font(.system(size: 8, weight: .medium))
                                }
                            } else {
                                Text(control.title)
                                    .font(.system(size: control.command == .plus100 ? 12 : 20, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(RemoteButtonStyle(restingOpacity: 0.075, radius: 13))
                    .help(control.help).accessibilityLabel(control.title)
                }
            }
        }
        .frame(width: 184)
    }

    private func rocker(title: String, up: PanelCommand, middle: PanelCommand, down: PanelCommand,
                        upSymbol: String, middleSymbol: String, downSymbol: String) -> some View {
        VStack(spacing: 9) {
            sectionLabel(title)
            VStack(spacing: 2) {
                rockerKey(up, symbol: upSymbol)
                rockerKey(middle, symbol: middleSymbol)
                rockerKey(down, symbol: downSymbol)
            }
            .padding(2)
            .background(.white.opacity(0.06), in: Capsule(style: .circular))
            .overlay(Capsule(style: .circular).strokeBorder(.white.opacity(0.06), lineWidth: 0.7))
        }
        .frame(width: 44)
    }

    private func rockerKey(_ command: PanelCommand, symbol: String) -> some View {
        Button { model.send(command) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 40, height: 40)
        }
        .buttonStyle(RemoteButtonStyle(restingOpacity: 0, radius: 20))
        .help(label(for: command)).accessibilityLabel(label(for: command))
    }

    @ViewBuilder private func faceKey(_ command: PanelCommand) -> some View {
        if let control = RemoteControls.control(for: command) {
            Button { model.send(command) } label: {
                VStack(spacing: 6) {
                    Image(systemName: control.symbol).font(.system(size: 13, weight: .medium))
                    Text(control.title).font(.system(size: 10, weight: .medium))
                }
                .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(RemoteButtonStyle(restingOpacity: 0.05, radius: 12))
            .help(control.help).accessibilityLabel(control.title)
        }
    }

    @ViewBuilder private func transportKey(_ command: PanelCommand) -> some View {
        if let control = RemoteControls.control(for: command) {
            Button { model.send(command) } label: {
                VStack(spacing: 7) {
                    Image(systemName: control.symbol).font(.system(size: 14))
                        .foregroundStyle(command == .record ? Color(red: 1, green: 0.38, blue: 0.39) : .white.opacity(0.88))
                    Text(control.title).font(.system(size: 9)).foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(RemoteButtonStyle(restingOpacity: 0, radius: 10))
            .help(control.help).accessibilityLabel(control.title)
        }
    }

    private var colourKeys: some View {
        HStack(spacing: 10) {
            ForEach(RemoteControls.colours) { control in
                let tint = colour(for: control.command)
                Button { model.send(control.command) } label: {
                    HStack(spacing: 7) {
                        Circle().fill(tint).frame(width: 7, height: 7)
                        Text(control.title).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).frame(height: 34)
                }
                .buttonStyle(RemoteButtonStyle(restingOpacity: 0.12, radius: 17, tint: tint))
                .help(control.help).accessibilityLabel(control.title)
            }
        }
    }

    private var controlBrowser: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.48))
                TextField("Find a control or key code", text: $model.controlQuery)
                    .textFieldStyle(.plain).font(.system(size: 12)).focused($searching)
                    .accessibilityLabel("Search remote controls")
                if !model.controlQuery.isEmpty {
                    Button { model.controlQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help("Clear search")
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(searching ? 0.28 : 0.08), lineWidth: 1))

            let sections = RemoteControls.sections(matching: model.controlQuery)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if sections.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .light))
                                Text("No matching controls").font(.system(size: 13, weight: .medium))
                                Text("Try a name such as HDMI, captions or picture.")
                                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 50)
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.group.rawValue).font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.60))
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(section.controls) { control in
                                        Button {
                                            searching = false
                                            model.send(control.command)
                                        } label: {
                                            VStack(spacing: 7) {
                                                Image(systemName: control.symbol).font(.system(size: 14))
                                                Text(control.title).font(.system(size: 10, weight: .medium))
                                                    .lineLimit(2).multilineTextAlignment(.center)
                                            }
                                            .padding(.horizontal, 5).frame(maxWidth: .infinity).frame(height: 59)
                                        }
                                        .buttonStyle(RemoteButtonStyle(restingOpacity: 0.06, radius: 11))
                                        .disabled(!model.ready)
                                        .help(control.help).accessibilityLabel(control.title)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .id(ScrollAnchor.top)
                }
                .onChange(of: model.controlQuery.trimmingCharacters(in: .whitespacesAndNewlines)) { _ in
                    proxy.scrollTo(ScrollAnchor.top, anchor: .top)
                }
            }
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 10) {
            if model.busy { ProgressView().controlSize(.small) }
            else { Image(systemName: "wifi.slash").foregroundStyle(.orange.opacity(0.8)) }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.busy ? "Connecting to TV…" : "TV is not connected")
                    .font(.system(size: 11, weight: .medium))
                Text(model.host.isEmpty && model.connection == .disconnected
                     ? "Set up a TV in connection settings to enable these controls."
                     : model.statusDetail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if !model.busy {
                Button(model.host.isEmpty ? "Set up" : "Reconnect") {
                    if model.host.isEmpty { model.showSettings() } else { model.connect() }
                }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.2)
            .foregroundStyle(.white.opacity(0.55))
    }
    private func label(for command: PanelCommand) -> String {
        RemoteControls.control(for: command)?.title ?? command.rawValue
    }
    private func colour(for command: PanelCommand) -> Color {
        switch command {
        case .red: return Color(red: 1, green: 0.37, blue: 0.39)
        case .green: return Color(red: 0.30, green: 0.83, blue: 0.57)
        case .yellow: return Color(red: 0.98, green: 0.79, blue: 0.30)
        case .blue: return Color(red: 0.33, green: 0.66, blue: 1)
        default: return .white
        }
    }
}

@MainActor
struct RemoteDirectionPad: View {
    @ObservedObject var model: PanelModel
    var diameter: CGFloat = 132
    private var distance: CGFloat { diameter * 43 / 132 }
    private var keySize: CGFloat { diameter > 132 ? 44 : 36 }

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.065))
            Circle().strokeBorder(.white.opacity(0.075), lineWidth: 0.7)
            arrow("chevron.up", "Up", .up).offset(y: -distance)
            arrow("chevron.down", "Down", .down).offset(y: distance)
            arrow("chevron.left", "Left", .left).offset(x: -distance)
            arrow("chevron.right", "Right", .right).offset(x: distance)
            Button { model.send(.enter) } label: {
                Text("OK").font(.system(size: 12, weight: .semibold))
                    .frame(width: distance, height: distance)
            }
            .buttonStyle(RemoteButtonStyle(restingOpacity: 0.12, radius: distance / 2))
            .help("OK / Select").accessibilityLabel("OK / Select")
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrow(_ symbol: String, _ title: String, _ command: PanelCommand) -> some View {
        Button { model.send(command) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: keySize, height: keySize)
        }
        .buttonStyle(RemoteButtonStyle(restingOpacity: 0, radius: keySize / 2))
        .help(title).accessibilityLabel(title)
    }
}
