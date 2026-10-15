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
                Text("Samsung").font(.system(size: 12, weight: .medium))
                Spacer()
                icon("gearshape", label: "Connection settings", size: 27) { model.showSettings() }
                icon("power", label: model.ready ? "Turn off TV" : "Wake TV", size: 27) { model.requestPower() }
            }
            .frame(height: 27)
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 17)
    }

    private var directionPad: some View {
        ZStack {
            Circle().fill(.white.opacity(0.065))
            icon("chevron.up", label: "Up", size: 36) { model.send(.up) }.offset(y: -43)
            icon("chevron.down", label: "Down", size: 36) { model.send(.down) }.offset(y: 43)
            icon("chevron.left", label: "Left", size: 36) { model.send(.left) }.offset(x: -43)
            icon("chevron.right", label: "Right", size: 36) { model.send(.right) }.offset(x: 43)
            Button { model.send(.enter) } label: {
                Text("OK").font(.system(size: 11, weight: .semibold)).frame(width: 43, height: 43)
            }
            .buttonStyle(RemoteButtonStyle(restingOpacity: 0.10, radius: 23))
            .help("OK / Select").accessibilityLabel("OK / Select")
        }
        .frame(width: 132, height: 132)
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
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                icon("chevron.left", label: "Back to remote", size: 24) { model.settings = false }
                Text("Connection").font(.system(size: 12, weight: .medium))
                Spacer()
            }
            Text("TV IP address").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            TextField("192.168.1.100", text: $model.host)
                .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced))
                .padding(11).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("TV IP address")
                .onSubmit { model.connect() }
            Text(model.notice.isEmpty ? "Same network. Approve this Mac on your TV if asked." : model.notice)
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Button { model.connect() } label: {
                Text("Connect").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain).foregroundStyle(.black)
            .background(.white, in: RoundedRectangle(cornerRadius: 9))
            Spacer(minLength: 0)
            HStack {
                Button("Re-pair TV") { model.onForget?(); model.connect() }
                    .disabled(model.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Quit") { model.onQuit?() }
            }
            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(20)
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

private struct RemoteButtonStyle: ButtonStyle {
    var restingOpacity: Double
    var radius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        RemoteButtonFace(configuration: configuration, restingOpacity: restingOpacity, radius: radius)
    }
}

private struct RemoteButtonFace: View {
    let configuration: ButtonStyle.Configuration
    let restingOpacity: Double
    let radius: CGFloat
    @State private var hovered = false
    var body: some View {
        configuration.label
            .foregroundStyle(.white.opacity(hovered || configuration.isPressed ? 1 : 0.76))
            .background(.white.opacity(configuration.isPressed ? 0.22 : (hovered ? 0.12 : restingOpacity)), in: RoundedRectangle(cornerRadius: radius))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
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
