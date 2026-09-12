# Grok Bot TUI for Omarchy

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Omarchy plugin](https://img.shields.io/badge/Omarchy-plugin-8b8b92?labelColor=1a1b26)](https://omarchy.org)
[![id](https://img.shields.io/badge/id-pixbroker.grokbot-7aa2f7?labelColor=1a1b26)](https://github.com/pixbroker/omarchy-grokbot)
[![Marketplace](https://img.shields.io/badge/marketplace-omarchy-e0af68?labelColor=1a1b26)](https://github.com/omacom/omarchy-plugin-marketplace)
[![TUI](https://img.shields.io/badge/TUI-grokbot--tui-9ece6a?labelColor=1a1b26)](https://github.com/pixbroker/grok-bot-rust)
[![GitHub last commit](https://img.shields.io/github/last-commit/pixbroker/omarchy-grokbot)](https://github.com/pixbroker/omarchy-grokbot)

Unofficial community bar widget for the **native Rust Grok Bot TUI** (`grokbot-tui`).

Click the face for an inbox of latest bot messages. Click a row to open that bot in the Rust TUI. The face sleeps in muted grey when idle and animates in foreground when something is unread or working.

**Omarchy theme.** The widget uses the shell palette (`Color.muted`, `Color.foreground`, `Color.bar.background`) so it restyles when you `omarchy theme set`. The TUI reads the same current theme file (`~/.local/state/omarchy/current/theme/colors.toml`) and reloads live (file watch + SIGUSR2).

This plugin is **not** Grok Bot, and it is **not** an xAI or Cursor product. It is also not the Electron Linux desktop client (`/usr/bin/grokbot`).

## Screenshots

Demo frames only. Fictional bots (`Ada`, `Scout`, `Notes`, `Research`) — not a capture of anyone’s real list, chat, or account.

**Bar — sleeping** (idle, `Color.muted`, eyes shut):

![Sleeping bar face](screenshots/bar-sleep.png)

**Bar — awake** (unread or a bot working, `Color.foreground`):

![Awake bar face](screenshots/bar-awake.png)

**Inbox panel** (click the face):

![Inbox of sample bots](screenshots/panel.png)

**Rust TUI** (`grokbot-tui`):

![Grok Bot TUI with sample bots](screenshots/tui.png)

## Privacy

The widget does not read tokens, chats, emails, or usage APIs. It does **not** poll or exec `grokbot-tui inbox`. It watches `~/.local/state/grok-bot-rust/inbox.json` (schema 2: names, previews, shapes, colours, sections). Prefer `grokbot-tui inbox --local --watch` (desktop app state, no login). Files larger than 64KiB are rejected. Opening a bot uses a Quickshell `Process` **argv** (`omarchy-launch-or-focus-tui`, `--app-id=…`, `grokbot-tui`, `open`, `<id>`). Bot ids are allowlisted (`[A-Za-z0-9._:-]`, max 80). Launch has an 8s timeout. At most 24 bots; string fields clipped. CLI-derived `Text` uses `textFormat: Text.PlainText`. Never `/usr/bin/grokbot`.

> Faces, flourishes, roster ordering and the local-state reader are adapted
> from [omabot](https://github.com/njpatel/omabot) by Neil Patel (Apache-2.0).
> `Avatar.qml` is Apache-2.0; see `NOTICE` and `LICENSE-APACHE`.

## What you need

- Omarchy with `omarchy-shell`
- **`grokbot-tui`**, installed from the pinned git revision below (Cargo.lock, `--locked`)

### grokbot-tui (immutable, source-verifiable)

This is the only supported install. It fetches [pixbroker/grok-bot-rust](https://github.com/pixbroker/grok-bot-rust) at a **fixed commit** and builds with `--locked`:

```bash
cargo install --git https://github.com/pixbroker/grok-bot-rust.git \
  --rev 11f991bbbae21bc810461e4f6fd7dedc30e213d6 \
  --locked \
  --bin grokbot-tui
```

That places `~/.cargo/bin/grokbot-tui`. The widget also accepts `~/.local/bin/grokbot-tui`. Then:

```bash
mkdir -p ~/.config/systemd/user
# from the grok-bot-rust tree:
cp contrib/systemd/grokbot-inbox.service ~/.config/systemd/user/
systemctl --user enable --now grokbot-inbox.service
```

That unit runs `grokbot-tui inbox --local --watch` (desktop app blobs, no login). The TUI writes the same file while it is open. `grokbot-tui inbox --watch` is the logged-in gateway writer.

Verify:

```bash
command -v grokbot-tui
test -s ~/.local/state/grok-bot-rust/inbox.json
```

Do not copy an unsigned local `target/release` build, and do not use Electron `/usr/bin/grokbot`.

## Install

Plugins run unsandboxed inside `omarchy-shell`. Read this repository first.

```bash
omarchy plugin add https://github.com/pixbroker/omarchy-grokbot.git --enable
```

```bash
omarchy plugin remove pixbroker.grokbot
```

## Use

- Click the outlined mark: inbox panel
- Beside the mark: up to three bots that want you (avatars), or a count, or nothing. Middle-click cycles.
- Click a row: open that bot in **`grokbot-tui`**. Right-click the mark opens the TUI with no bot selected.
- Hover the bar: those avatars look up, one after another
- Panel keys: `j`/`k` move · `Enter` open · `g` order (attention / channels / flat) · `h` redact · `r` metric · `Esc` close
- Demo roster for screenshots: `omarchy-shell pixbroker.grokbot demo` (same 14-bot table as `grokbot-tui demo`)
- Follows the Omarchy theme (same `colors.toml` as the TUI)

## Settings

| Key | Default | What it does |
| --- | --- | --- |
| barMetric | avatars | Beside the mark: `avatars`, `count`, or `none` |
| ordering | attention | Panel order: `attention`, `channels`, or `flat` |
| groupBySection | true | When ordering is channels, show sidebar section headers |
| maxBarAvatars | 3 | How many wanting bots sit beside the mark (1–6) |
| command | grokbot-tui | Basename `grokbot-tui` or an absolute path ending in `/grokbot-tui` |
| appId | org.omarchy.grokbot-tui | Window id used to focus an existing TUI |

## Validate

```bash
omarchy plugin validate .
```
