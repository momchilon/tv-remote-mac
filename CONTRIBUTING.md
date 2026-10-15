# Contributing

TV Remote for Mac starts with Samsung support. Requests and contributions for **any TV brand/model** are welcome.

## Request a TV

Use the TV support request issue template. Include the brand/model, approximate year/OS, desired controls and whether you can test a build. Never post pairing tokens, serial numbers, MAC addresses or private network details.

## Code changes

1. Open an issue for a new TV backend or a larger change so the approach can be discussed first.
2. Fork the repository and work on a branch.
3. Keep the menu-bar UI small and click-only. Avoid background services, telemetry, accounts and unnecessary dependencies.
4. Put protocol/network logic in a separate, testable component. `RemoteKit` contains the current Samsung implementation; the app currently wires directly to `SamsungRemote`, so a multi-brand abstraction would be a future change.
5. Add tests using local fixtures. Default tests must never issue commands to a real TV or automate someone's desktop.
6. Run the default tests and build commands in the README. UI tests require explicit opt-in with `RUN_UI_TESTS=1` and an appropriate desktop session.
7. Open a pull request describing the change, tested TV/model/firmware, and remaining limitations. Distinguish a successful socket write from physically confirmed TV behavior.

## Security and compatibility

Preserve scoped TLS trust, per-host pairing, private credential permissions and bounded key queues. Do not add service-menu, reset, calibration or installation commands to the normal remote UI. Never commit real credentials, machine-local paths, build directories or personal device identifiers.

Keep the bundle identifier and existing storage compatible unless a migration is part of the change. Released binaries must match the tagged source version.

Contributions are made under the repository's MIT license.
