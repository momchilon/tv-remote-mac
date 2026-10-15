import SwiftUI

@MainActor
public struct RemotePanelView: View {
    @ObservedObject private var model: PanelModel
    public init(model: PanelModel) { self.model = model }

    public var body: some View {
        Group {
            if !model.expanded {
                ZStack(alignment: .bottom) {
                    Color.black
                    Capsule().fill(.white.opacity(0.22)).frame(width: 22, height: 2).padding(.bottom, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.expanded = true }
                .accessibilityLabel("Open TV remote")
            } else if model.settings {
                settings
            } else if model.confirmingPower {
                powerConfirmation
            } else {
                remote
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .foregroundStyle(.white)
        .clipShape(PanelShape(radius: model.expanded ? 22 : 5))
        .preferredColorScheme(.dark)
    }

    private var remote: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                    .accessibilityLabel(model.ready ? "Connected" : "Not connected")
                Menu {
                    ForEach(model.savedRemotes) { remote in
                        Button { model.selectRemote(remote) } label: {
                            Label(remote.displayLabel, systemImage: remote.host == model.selectedRemoteHost ? "checkmark" : "tv")
                        }
                    }
                    if !model.savedRemotes.isEmpty { Divider() }
                    Button("Add TV…") { model.addRemote() }
                } label: {
                    Text(model.activeRemoteName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Switch remote")
                Spacer()
                Button { model.toggleFullRemote() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.fullRemote ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        Text(model.fullRemote ? "Compact" : "Full")
                    }
                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).frame(height: 27)
                }
                .buttonStyle(RemoteButtonStyle(restingOpacity: 0.07, radius: 8))
                .help(model.fullRemote ? "Return to compact remote" : "Expand full remote")
                .accessibilityLabel(model.fullRemote ? "Collapse to compact remote" : "Expand full remote")
                icon("gearshape", label: "Connection settings", size: 27) { model.showSettings() }
                icon("power", label: model.ready ? "Turn off TV" : "Wake TV", size: 27) { model.requestPower() }
            }
            .frame(height: 27)
            if model.fullRemote {
                ExpandedRemoteView(model: model).padding(.top, 16)
            } else {
                Spacer(minLength: 8)
                if model.ready {
                    HStack(spacing: 30) {
                        directionPad
                        volume
                    }
                    Spacer(minLength: 9)
                    HStack(spacing: 14) {
                        remoteKey("arrow.uturn.backward", label: "Back", key: .back)
                        remoteKey("house", label: "Home", key: .home)
                        remoteKey("rectangle.on.rectangle", label: "Input source", key: .source)
                    }
                    .frame(height: 32)
                } else {
                    connectionState
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 17)
    }

    private var directionPad: some View {
        RemoteDirectionPad(model: model)
    }

    private var volume: some View {
        VStack(spacing: 4) {
            icon("plus", label: "Volume up", size: 40) { model.send(.volumeUp) }
            icon("speaker.slash", label: "Mute / Unmute", size: 40) { model.send(.mute) }
            icon("minus", label: "Volume down", size: 40) { model.send(.volumeDown) }
        }
        .padding(2)
        .background(.white.opacity(0.065), in: Capsule())
    }

    private var connectionState: some View {
        VStack(spacing: 11) {
            if model.busy {
                ProgressView().controlSize(.small).padding(.bottom, 4)
            } else {
                Image(systemName: "tv").font(.system(size: 25, weight: .light)).foregroundStyle(.white.opacity(0.55))
            }
            Text(statusTitle).font(.system(size: 13, weight: .medium))
            Text(model.statusDetail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.52))
                .multilineTextAlignment(.center).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            if !model.busy {
                HStack(spacing: 10) {
                    if model.canWake {
                        Button("Wake TV") { model.requestPower() }.buttonStyle(TextActionStyle())
                    }
                    Button(model.host.isEmpty ? "Set up" : "Reconnect") {
                        if model.host.isEmpty { model.showSettings() } else { model.connect() }
                    }.buttonStyle(TextActionStyle())
                }.padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                icon("chevron.left", label: "Back to remote", size: 24) { model.leaveSettings() }
                Text("Your remotes").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Add TV") { model.addRemote() }
                    .buttonStyle(.plain).font(.system(size: 11))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.savedRemotes.isEmpty { savedRemotes }
                    HStack {
                        Text("Nearby TVs").font(.system(size: 11, weight: .medium))
                        Spacer()
                        if model.discovering {
                            ProgressView().controlSize(.mini)
                            Button("Stop") { model.cancelDiscovery() }
                                .buttonStyle(.plain).font(.system(size: 11))
                        } else {
                            Button("Find TVs") { model.findTVs() }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                        }
                    }
                    Text(model.discoveryNotice)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.discoveredTVs) { tv in
                        Button { model.selectTV(tv) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "tv").frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tv.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    Text([tv.model, tv.host].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if model.host == tv.host { Image(systemName: "checkmark").font(.system(size: 10)) }
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(RemoteButtonStyle(restingOpacity: 0.06, radius: 8))
                        .accessibilityLabel("Select \(tv.name), \(tv.host)")
                    }
                    Divider().overlay(.white.opacity(0.12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remote name").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        TextField("Living room", text: $model.remoteName)
                            .textFieldStyle(.plain).font(.system(size: 12))
                            .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityLabel("Remote name")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TV IP address").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        TextField("192.168.1.100", text: $model.host)
                            .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                            .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityLabel("TV IP address")
                            .onSubmit { model.connect() }
                    }
                    Text(model.notice.isEmpty ? "Same network. Approve this Mac on your TV if asked." : model.notice)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.connect() } label: {
                        Text("Save & Connect").font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain).foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                }
                .padding(.vertical, 1)
            }
            HStack {
                Button("Re-pair TV") { model.repairTV() }
                    .disabled(model.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Quit") { model.onQuit?() }
            }
            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(20)
    }

    private var savedRemotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved TVs").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            ForEach(model.savedRemotes) { remote in
                HStack(spacing: 5) {
                    Button { model.editRemote(remote) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: remote.host == model.selectedRemoteHost ? "tv.fill" : "tv")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(remote.name).lineLimit(1)
                                if remote.name != remote.host {
                                    Text(remote.host).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Edit \(remote.displayLabel)")
                    .accessibilityLabel("Edit \(remote.displayLabel)")
                    Button { model.selectRemote(remote) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.plain).help("Connect to \(remote.displayLabel)")
                        .accessibilityLabel("Connect to \(remote.displayLabel)")
                    Menu {
                        Button("Remove saved remote", role: .destructive) { model.onRemoveRemote?(remote.host) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Manage \(remote.displayLabel)")
                }
                .font(.system(size: 11)).padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider().overlay(.white.opacity(0.12)).padding(.top, 4)
        }
    }

    private var powerConfirmation: some View {
        VStack(spacing: 18) {
            Image(systemName: "power").font(.system(size: 25, weight: .light)).foregroundStyle(.white.opacity(0.8))
            Text("Turn off TV?").font(.system(size: 14, weight: .medium))
            HStack(spacing: 12) {
                Button("Cancel") { model.confirmingPower = false }.buttonStyle(TextActionStyle())
                Button("Turn off") { model.confirmPowerOff() }.buttonStyle(TextActionStyle())
            }
        }
        .padding(20)
    }

    private func remoteKey(_ symbol: String, label: String, key: PanelCommand) -> some View {
        Button { model.send(key) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 56, height: 32)
        }
        .buttonStyle(RemoteButtonStyle(restingOpacity: 0.055, radius: 10))
        .help(label).accessibilityLabel(label)
    }

    private func icon(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: size, height: size)
        }
        .buttonStyle(RemoteButtonStyle(restingOpacity: 0, radius: size / 2))
        .help(label).accessibilityLabel(label)
    }

    private var statusColor: Color {
        if model.ready { return Color(red: 0.34, green: 0.79, blue: 0.55) }
        if model.busy { return .orange }
        return .white.opacity(0.3)
    }
    private var statusTitle: String {
        switch model.connection {
        case .ready: return "Connected"
        case .connecting: return "Connecting…"
        case .approval: return "Allow on your TV"
        case .failed: return "Couldn’t connect"
        case .disconnected: return "TV is offline"
        }
    }
}

struct RemoteButtonStyle: ButtonStyle {
    var restingOpacity: Double
    var radius: CGFloat
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        RemoteButtonFace(configuration: configuration, restingOpacity: restingOpacity, radius: radius, tint: tint)
    }
}

private struct RemoteButtonFace: View {
    let configuration: ButtonStyle.Configuration
    let restingOpacity: Double
    let radius: CGFloat
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        configuration.label
            .foregroundStyle(.white.opacity(hovered || configuration.isPressed ? 1 : 0.86))
            .background(tint.opacity(configuration.isPressed ? 0.25 : (hovered && isEnabled ? 0.15 : restingOpacity)), in: RoundedRectangle(cornerRadius: radius, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .circular).strokeBorder(tint.opacity(restingOpacity == 0 ? 0 : (hovered && isEnabled ? 0.23 : 0.10)), lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .opacity(isEnabled ? 1 : 0.40)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

private struct TextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.09), in: Capsule())
    }
}

private struct PanelShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let top = min(7, radius)
        let bottom = min(radius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: top, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: top), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - bottom), control: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: top))
        path.addQuadCurve(to: CGPoint(x: top, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}
