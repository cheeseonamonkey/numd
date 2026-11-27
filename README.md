# numd

**Num Lock as a numpad modifier.** A small Linux evdev/uinput daemon in Nim with one CLI for setup, configuration, and service management.

- **Tap Num Lock** → ordinary Num Lock toggle.
- **Hold Num Lock + numpad key** → configured keyboard shortcut.
- **Otherwise** → unchanged keyboard/numpad input.
- Works at the input-device level under X11 and Wayland.

## Configuration

Edit `/etc/numd/config.ini`:

```ini
[device]
path = auto

[bindings]
kp7 = "super+7"
kp8 = "super+8"
kp9 = "super+9"
kp4 = "super+left"
kp5 = "super+up"
kp6 = "super+right"
kp1 = "super+1"
kp2 = "super+2"
kp3 = "super+3"
kp0 = "ctrl+alt+t"
kpdot = "printscreen"
```

Shortcut values containing `+` **must be quoted** in the INI file.
Numpad sources: `kp0`–`kp9`, `kpdot`, `kpenter`, `kpplus`,
`kpminus`, `kpslash`, `kpasterisk`. Targets include letters,
digits, F1–F12, arrows, navigation keys, and Ctrl/Alt/Shift/Super modifiers.
These are **key shortcuts**, not built-in window-management actions: bind
them in your desktop/compositor.

`device.path = auto` chooses the first `*-event-kbd` device under
`/dev/input/by-id`, then `/dev/input/by-path`. For multiple keyboards,
specify an explicit stable symlink instead. Device reconnect is supported;
one physical keyboard is handled per daemon instance.

## Debian/Ubuntu install

Download the `.deb` from [CI artifacts](../../actions/workflows/deb.yml)
or [Releases](../../releases), then install and run the setup wizard:

```sh
sudo apt install ./numd_*.deb
sudo numd setup
```

`numd setup` opens the ngum configuration TUI, loads `uinput` if needed,
then enables and starts the system service. The package bundles ngum for the
TUI; no separate TUI install is needed.

```sh
numd status
numd config                 # edit bindings; restarts active service on save
numd logs                   # follow service journal
numd start|stop|restart
numd enable|disable
numd devices
```

The service runs as root because it needs evdev/uinput access and exclusively
grabs the selected physical keyboard. Do not run another remapper against the
same device. `numd` with no arguments prints help; run the daemon directly
with `sudo numd run [config-file]`.

## Build/test

Requires Nim 2.2+, a C compiler, Linux headers, dpkg tools, and the ngum
executable on the build machine:

```sh
nimble test
nimble dist
```

CI tests, compiles, and publishes an amd64 Debian package as an artifact;
`v*` tags attach the Debian package to a GitHub release.

## Limitations

- Num Lock's **physical keyboard LED** may not track the virtual toggled state.
- Shortcuts are tap pulses, not held key combinations.
- No arbitrary shell execution, hot config reload, or multi-keyboard
  coordination. Physical modifiers held simultaneously may alter shortcuts.
- No hardware input test was possible on the headless development VPS.
