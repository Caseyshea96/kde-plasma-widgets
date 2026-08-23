# Jellyfin Now Playing for KDE Plasma

A Plasma 6 widget showing active Jellyfin streams: what's playing, who's
watching, on what device, playback position, and whether the stream is
direct play or being transcoded. Built as a companion to the Docker
Containers widget — `jellyfin` is one of the containers that widget already
tracks; this one drills into what it's actually doing.

The compact icon shows the count of active streams and a colored dot (green
= at least one stream playing, grey = idle, red = last refresh failed). The
full view lists each active session with title, user, device, position, and
a Direct Play / Transcoding chip.

This is a read-only widget — it does not control playback.

## Setup

This widget needs your own Jellyfin server URL and API key — there's no
sensible default for a secret, so it ships unconfigured and shows a "not
configured" message until you fill these in yourself, the same way any app
that talks to an API key-protected service works.

Right-click the widget → **Configure…** and set:

- **Server URL** — e.g. `http://localhost:8096` (the default, if Jellyfin
  runs on this same machine) or a LAN/Tailscale address.
- **API key** — generate one in Jellyfin: **Dashboard → API Keys →** the
  **+** button. The field is masked (password-style) since it's a secret.
  It's stored in Plasma's own config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`),
  the same place any other widget's settings live — not in this project's
  source files, so it's never at risk of being committed to git.

## Appearance and behavior

Open the widget's settings to also choose among:

- the normal Plasma theme background;
- a translucent Plasma-colored surface with adjustable opacity; or
- a transparent surface.

...and the refresh interval.

## Requirements

- KDE Plasma 6
- `curl`
- A Jellyfin server reachable from this machine, and an API key for it

Verify before installing (replace with your own URL/key):

```bash
curl -sS -f -H "X-Emby-Token: YOUR_KEY" "http://localhost:8096/Sessions"
```

## Install

```bash
chmod +x install.sh
./install.sh
```

Then right-click the Plasma desktop or panel, choose **Add Widgets**, search
for **Jellyfin Now Playing**, and drag it onto the panel or desktop. Then
configure it as described above.

For development, rerun `./install.sh` after edits, then restart Plasma if its
QML cache does not pick up the change. Remove the installed widget with:

```bash
kpackagetool6 --type Plasma/Applet --remove com.casey.plasma.jellyfin
```

## Package

Create a distributable package from the project directory:

```bash
zip -r jellyfin-now-playing.plasmoid metadata.json contents
```
