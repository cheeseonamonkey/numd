# numd

**Num Lock as a numpad modifier.** A small Linux evdev/uinput daemon written in Nim, with no third-party runtime dependencies.

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
or [Releases](../../releases).

```sh
sudo apt install ./numd_*.deb
sudoedit /etc/numd/config.ini
numd --check /etc/numd/config.ini
sudo modprobe uinput  # only if /dev/uinput is missing
sudo systemctl enable --now numd
journalctl -u numd -f
```

The package deliberately **does not enable/start** the service at install.
The service uses root for evdev input access and uinput device creation;
it grabs the physical keyboard exclusively. Avoid running another remapper
against the same device.

After editing config, run `numd --check` and `sudo systemctl restart numd`.

## Build/test

Requires Nim 2.2+, a C compiler, Linux headers, and dpkg tools:

```sh
nim c -r --out:build/core-tests tests/test_core.nim
nim c -d:release --out:build/numd src/numd.nim
build/numd --check config/numd.ini
bash packaging/build-deb.sh 0.1.0
```

CI tests, compiles, and publishes an amd64 Debian package as an artifact;
`v*` tags attach the Debian package to a GitHub release.

## Limitations

- Num Lock's **physical keyboard LED** may not track the virtual toggled state.
- Shortcuts are tap pulses, not held key combinations.
- No arbitrary shell execution, hot config reload, or multi-keyboard
  coordination. Physical modifiers held simultaneously may alter shortcuts.
- No hardware input test was possible on the headless development VPS.
