# Expanded remote — v0.3

Click **Full** in the compact remote's header to open the full remote. Click **Compact** to return. The preference survives closing the popover for the current app session; it does not automatically open the popover or persist across app restarts.

## Layout

- **Remote:** navigation ring with OK, separate VOL/CH rockers, a 0–9 number pad with +100 and previous channel, Back/Home/Source/Exit, coloured A/B/C/D keys, six playback/record controls, TV menu, channel list, information and subtitles.
- **More controls:** grouped, searchable controls for playback extras, TV menus, inputs, picture, sound/accessibility, multi-view/PiP, media and timers. Search accepts human-readable labels and exact `KEY_…` identifiers; primary controls can also be found through search.
- The compact panel remains 300 × 250 points; full mode is 520 × 640 points before screen-height clamping. Full controls scroll on shorter displays. Settings retain their own 300 × 480 layout.
- Circular navigation, capsule rockers/colour keys and rounded-rectangle number/function keys deliberately distinguish different control families. Native SF text, hover/pressed feedback, accessibility labels, non-colour A/B/C/D labels and Reduce Motion support are retained.
- Offline controls are disabled. Set up/Reconnect and the separate power/wake action remain available.

## Keyboard

Only when this app's popover owns the keyboard:

- Arrows: navigation; Return/numpad Enter: OK; Delete: Back.
- `+`/`−`: volume; M: mute.
- Number row/numpad 0–9: number keys.
- Page Up/Down: next/previous channel.
- Escape: close the Mac popover, not the TV application.

Editing a settings/search field must not also transmit remote keys. Power confirmation suppresses remote keyboard commands.

## Mapping and limitations

The allowlist contains **114 distinct wire commands**: 113 ordinary controls plus the existing confirmed power command. `PanelCommand` aliases `RemoteKey`, so UI and transport cannot silently drift into different command sets.

Wire identifiers were cross-checked against the primary source code of the community projects **samsung-tv-control** and **samsung-tv-ws-api**. The latter also supplies modern mappings such as Ambient and Multi-view.[1][2]

This is a catalogue of known Samsung mappings, **not a declaration that every key works on every Tizen model**. It deliberately includes model-dependent and older Samsung controls to provide broader coverage. A successful network write is not proof of a physical TV action; unsupported keys can do nothing. Actual behavior must be checked on the particular TV, input and application.

No unknown `KEY_EXT…` values, factory/service commands, automatic retuning or alternate unconfirmed power paths are included. The power button still requires confirmation. No voice/microphone streaming, per-app-ID launcher, TV capability detection or fetched channel directory has been added. The App list and Channel list keys request those screens on the TV itself.

## Verification

- Exact allowlist and JSON framing for all 114 commands.
- All 113 non-power keys sent in order through the actual TLS/WebSocket transport to a loopback fixture, not a physical TV.
- Catalogue coverage, uniqueness, search, symbols, authenticated/offline gating, power confirmation, keyboard text-entry protection and layout state tests.
- Opt-in offscreen native renders cover compact/full/short-screen layouts, long TV names, control browsing/search, no results, offline/approval, settings and confirmation.
- Full status-item/click tests remain separately opt-in; offscreen rendering does not authorize desktop automation.

These controls are included in v0.3. Updating from v0.1 or v0.2 retains existing saved TV pairing data.

## Sources

[1] https://raw.githubusercontent.com/Toxblh/samsung-tv-control/master/src/keys.ts — samsung-tv-control key catalogue
[2] https://raw.githubusercontent.com/xchwarze/samsung-tv-ws-api/master/samsungtvws/remote.py — samsung-tv-ws-api Remote methods
