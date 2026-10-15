import Foundation
import Darwin
import RemoteKit

/// Authentication diagnostic only. It never calls send(_:) or wake(...).
@main
struct RemoteCheck {
    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print("Usage: RemoteCheck --host PRIVATE_IPV4 [--timeout SECONDS]")
            print("Read-only authentication check; timeout defaults to 45 seconds (range 1...120).")
            exit(0)
        }
        var host: String?
        var timeout: TimeInterval = 45
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--host", "--timeout"].contains(option), !seen.contains(option), index + 1 < arguments.count else { invalidArguments() }
            seen.insert(option)
            let value = arguments[index + 1]
            if option == "--host" { host = value }
            else {
                guard let number = Double(value), number.isFinite, (1...120).contains(number) else { invalidArguments() }
                timeout = number
            }
            index += 2
        }
        guard let host else { invalidArguments() }
        let directory = ProcessInfo.processInfo.environment["REMOTEKIT_STORAGE_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let remote = SamsungRemote(storageDirectory: directory)
        remote.connect(host: host)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        var previous: RemoteStatus?
        while true {
            let status = remote.status
            if status != previous {
                switch status {
                case .disconnected: print("status: disconnected")
                case .connecting: print("status: connecting")
                case .awaitingApproval: print("status: awaitingApproval")
                case .connected: print("status: connected")
                case .failed(let reason): print("status: failed: \(reason)")
                }
                fflush(stdout)
                previous = status
            }
            if status == .connected {
                print("authenticated: true")
                remote.disconnect()
                exit(0)
            }
            if case .failed = status {
                print("authenticated: false")
                remote.disconnect()
                exit(1)
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                print("status: failed: Diagnostic timed out; check the TV and approve its connection prompt, then connect explicitly again.")
                print("authenticated: false")
                remote.disconnect()
                exit(1)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func invalidArguments() -> Never {
        print("status: failed: Usage: RemoteCheck --host PRIVATE_IPV4 [--timeout SECONDS (1...120)]")
        print("authenticated: false")
        exit(1)
    }
}
