# RemoteKit

Native, dependency-free macOS 13+ Swift package (Swift tools 5.9). Products: `RemoteKit` and authentication-only `RemoteCheck`.

## Build / verify

```sh
swift test --build-system native
swift build --build-system native -c release --product RemoteCheck
```

The native build flag is supported but deprecated by Swift 6.4; it keeps this package's incremental test build independent. The parent app may use the default Swift build engine. Tests use Python 3 and system OpenSSL for a loopback TLS/WebSocket fixture on port 8002; neither is a runtime dependency. Do not run network fixture tests in parallel. For isolated diagnostic storage, set `REMOTEKIT_STORAGE_DIRECTORY` to a private directory. Without that environment variable, the CLI uses the app's normal storage.

`RemoteCheck` accepts only `--host`, optional `--timeout` (1–120 seconds; default 45), and `--help`. It prints sanitized status and `authenticated: true/false`; exits 0 only after `ms.channel.connect`, otherwise 1. It never sends keys, wake packets, REST writes, or per-key probes. Running it may show the TV's normal Allow prompt and persists successfully authenticated pairing credentials/pin.

## Exact public API

```swift
public enum RemoteKey: String, CaseIterable, Sendable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT"
    case enter = "KEY_ENTER", back = "KEY_RETURN", home = "KEY_HOME"
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case source = "KEY_SOURCE", power = "KEY_POWER"
}
public enum RemoteStatus: Equatable {
    case disconnected, connecting, awaitingApproval, connected, failed(String)
}
@MainActor public final class SamsungRemote: ObservableObject {
    @Published public private(set) var status: RemoteStatus
    public var isConnected: Bool { get }
    public init(storageDirectory: URL? = nil)
    public func connect(host: String)
    public func disconnect()
    public func send(_ key: RemoteKey)
    public func wake(macAddress: String, host: String)
    public func forget(host: String)
    public var onDeviceInfo: ((String, String?) -> Void)? { get set }
}
```

The public initializer is a convenience initializer. Automatic device-info GET is intentionally omitted; the optional callback is available for API compatibility but is not invoked. Prefill/name the TV in the parent UI. There is no auto-reconnect: the parent owns sleep/wake and explicit reconnect policy.

## Security / behavior

- Only canonical literal RFC1918, IPv4 link-local and loopback hosts; trims outer whitespace. No DNS, public IP, IPv6, URL, port, query or path inputs.
- WSS only, exact configured IP on port 8002. Dedicated ephemeral URLSession and direct session/task authentication delegates. Cookies, credentials, caching, proxies and all redirects disabled. No insecure WS fallback.
- SHA-256 of the leaf DER certificate is compared with the host's saved pin. An unsaved TOFU candidate stays in memory until `ms.channel.connect`. A changed certificate blocks connection with an explicit verify/forget/re-pair message. First-use TOFU cannot prevent a first-contact LAN impersonation; approve the expected remote on the TV.
- Host-scoped token, stable client name and leaf pin live in `~/Library/Application Support/Notch Remote/connections.json`, directory 0700 and file 0600. Atomic fsynced writes; directory/file symlinks, foreign ownership and credential-file hard links are rejected. Corrupt data is not silently overwritten. Never publish this file.
- Preparing a host reads only its saved connection or a fresh record; no external credential files are imported. Forget clears that host's token and pin and resets its client name.
- Controls remain disabled until channel authentication. Pairing deadline 45 seconds; actionable sanitized rejection/timeout/error messages; no automatic reconnect after rejection. Keepalive every 20 seconds, with a 5-second pong watchdog.
- Click keys only, explicit 12-key allowlist. Ordered queue capped at 12 pending keys; 250 ms between sends; excess is ignored. Disconnect/reconnect cancels timers, transport, outstanding work and queued keys. Socket writes are not per-key acknowledgments.
- Wake sends one 102-byte UDP magic packet to the validated TV IP, port 9 (unicast). It never sets connected status or claims that wake-up was verified. Wake support on the physical TV is unverified; unicast may not work when ARP/standby networking is unavailable.
- Parent app must supply its local networking bundle policy/permissions. No UI or parent files are modified by this package.

## Reference material

Implementation was written from tests, not copied from upstream code. Upstream protocol reference: https://github.com/xchwarze/samsung-tv-ws-api . Native transport reference: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask .
