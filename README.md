# system76-typing-backlight

Activity-driven keyboard backlight for System76 laptops on Pop!_OS — turns the keyboard backlight on while you type and off (or down to a low glow) after a configurable idle timeout.

A small GTK settings app lets you tune brightness levels, idle delay, and the master enable from the application launcher — no terminal required after install.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue)
![Status: stable](https://img.shields.io/badge/status-stable-brightgreen)

Built because System76 / Pop!_OS ship no built-in "backlight on typing" feature, and many System76 laptops (including the older Lemur Pro `lemp9`) have no ambient light sensor that could trigger one automatically. This is a deliberately small piece of glue: one daemon, one config writer, one GTK app, one systemd unit, one polkit policy, one `.desktop` entry.

## Features

- **Active brightness** while typing (0 — `max_brightness` of your LED, usually 255)
- **Inactive brightness** after idle (0 = fully off, or set a low glow)
- **Idle timeout** in seconds before dropping from active to inactive
- **Master enable** toggle — when off, the daemon stays running but does not touch the LED
- **GTK settings app** in the application launcher ("Keyboard Backlight (Typing)")
- **Polkit-mediated config writes** — the GUI prompts once for admin auth (cached ~5 min) and the daemon restarts automatically
- **Single interactive setup script** for install, reinstall, uninstall, and status (also supports non-interactive subcommands)
- **LED auto-discovery** under `/sys/class/leds/*kbd_backlight*` — works on most System76 laptops without a code change

## Requirements

- A System76 laptop, or any Linux machine exposing a `*kbd_backlight*` LED under `/sys/class/leds/` with writable `brightness` and a readable `max_brightness`.
- Linux with systemd, polkit, and `python3` plus PyGObject GTK 3 bindings (`python3-gi`, `gir1.2-gtk-3.0`). On Pop!_OS / Ubuntu these are preinstalled; on Fedora install `python3-gobject` and `gtk3`.
- Root access for install (the daemon reads `/dev/input/event*` and writes the LED sysfs node).

Tested on a System76 Lemur Pro (`lemp9`) running Pop!_OS. Reports of other laptops working — or not — are welcome via issues.

## Install

```bash
git clone https://github.com/jwillmer/system76-typing-backlight.git
cd system76-typing-backlight
./kbd-backlight-typing-setup.sh
```

The script self-elevates with `sudo`, copies files into place, writes a default config (only if `/etc/kbd-backlight-typing.conf` does not already exist), enables and starts the systemd service, and registers the polkit policy and `.desktop` entry.

Non-interactive variants:

```bash
./kbd-backlight-typing-setup.sh install
./kbd-backlight-typing-setup.sh status
./kbd-backlight-typing-setup.sh restart
./kbd-backlight-typing-setup.sh uninstall              # also removes /etc/kbd-backlight-typing.conf
sudo KEEP_CONFIG=1 ./kbd-backlight-typing-setup.sh uninstall   # keep config
```

## Configure

Open **Keyboard Backlight (Typing)** from the application launcher. Adjust:

| Setting             | Range            | Default | Meaning                                      |
| ------------------- | ---------------- | ------- | -------------------------------------------- |
| Enabled             | toggle           | on      | Master switch                                |
| Active brightness   | 0–`max`          | 128     | Brightness while typing                      |
| Inactive brightness | 0–`max`          | 0       | Brightness after the idle timeout            |
| Idle seconds        | 1–86400          | 60      | How long before going inactive               |

`max` is read from `/sys/class/leds/*kbd_backlight*/max_brightness` (typically 255 on System76).

Click **Apply** — you'll be prompted for your password, then it's cached so quick re-tunes don't re-prompt. The service restarts and your settings take effect.

The config is at `/etc/kbd-backlight-typing.conf` and can also be edited by hand:

```ini
[settings]
enabled = true
active_brightness = 128
inactive_brightness = 0
idle_seconds = 60
```

After hand-editing, run `sudo systemctl restart kbd-backlight-typing`.

## How it works

- **`kbd-backlight-typing`** — Python daemon, runs as root via systemd. Auto-discovers the keyboard LED, opens every `/dev/input/by-path/*-event-kbd` device, polls them for any input event, and writes brightness values to `/sys/class/leds/<led>/brightness`. It needs root because that sysfs file is root-only by default and reading raw evdev requires `input` group membership.
- **`kbd-backlight-typing-apply`** — privileged config writer, invoked by the GUI through `pkexec`. Validates inputs against the LED's actual `max_brightness`, writes the config file, and restarts the service.
- **`kbd-backlight-typing-gui`** — small GTK 3 / Python app. Reads the config on launch, queries `max_brightness` to size its sliders, and shells out to `pkexec kbd-backlight-typing-apply ...` on save.
- The polkit policy at `/usr/share/polkit-1/actions/com.system76.kbdbacklight.policy` allows the apply helper with `auth_admin_keep`.

## File layout (after install)

```
/usr/local/bin/kbd-backlight-typing                         # daemon
/usr/local/bin/kbd-backlight-typing-apply                   # privileged config writer
/usr/local/bin/kbd-backlight-typing-gui                     # GTK settings app
/etc/systemd/system/kbd-backlight-typing.service
/usr/share/polkit-1/actions/com.system76.kbdbacklight.policy
/usr/share/applications/kbd-backlight-typing.desktop
/etc/kbd-backlight-typing.conf                              # user-editable config
```

## Troubleshooting

**The GUI doesn't appear in the launcher.** GNOME caches `.desktop` files. Log out and back in, or run `update-desktop-database ~/.local/share/applications` (the install path is system-wide, so usually a logout is enough).

**The daemon refuses to start (`no *kbd_backlight* LED found`).** Your laptop's LED is named differently (or absent). Run `ls /sys/class/leds/` — if there is no `*kbd_backlight*` entry, this tool cannot help on your hardware. If the entry exists under a different name, please open an issue with the listing; LED discovery uses a glob and may need a small tweak.

**The daemon refuses to start (`no keyboard event devices found`).** Your kernel's `/dev/input/by-path/*-event-kbd` symlinks are missing. Check `ls /dev/input/by-path/` and `ls /dev/input/`; the daemon could be adapted to scan all `event*` devices but currently relies on the `by-path` symlinks shipped with `udev`.

**The backlight ignores my Fn-key adjustments.** Expected — the next keystroke triggers a write back to the configured "active" level. There's no "respect manual override" mode yet; PRs welcome.

**Service status / logs:**

```bash
systemctl status kbd-backlight-typing
journalctl -u kbd-backlight-typing -f
```

## Privacy

The daemon reads every keystroke (it has to, in order to detect typing activity), but it does **not** log, store, transmit, or interpret keys. It only counts that an event happened. The code is short — read it, not me. There is no network code anywhere in the project.

## Contributing

Bug reports and pull requests welcome. Open an issue first for non-trivial changes so we can discuss the design.

For local development:

```bash
git clone https://github.com/jwillmer/system76-typing-backlight.git
cd system76-typing-backlight
# edit files, then reinstall:
./kbd-backlight-typing-setup.sh install
```

The codebase is intentionally small and dependency-light — please keep it that way.

## License

MIT — see [LICENSE](LICENSE).
