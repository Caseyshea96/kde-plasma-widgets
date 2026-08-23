# Tailscale Status for KDE Plasma

A Plasma 6 widget showing tailnet peers online/offline, exit node status, and
the subnet routes this device advertises. Handy for keeping an eye on things
while experimenting with exit-node or subnet-route configuration.

The compact icon shows a colored dot (green = backend running, grey =
stopped, red = last refresh failed) and the count of online peers. The full
view shows this device's hostname and IPs, the active exit node (if any),
whether this device offers itself as an exit node, advertised subnet routes,
any `tailscale status` health warnings, and a peer list with per-peer online
state, OS, last-seen time, and icons marking the active exit node or peers
that advertise their own routes.

This is a read-only status widget — it does not change exit-node selection,
routes, or any other Tailscale configuration.

## Appearance and behavior

Open the widget's settings to choose among:

- the normal Plasma theme background;
- a translucent Plasma-colored surface with adjustable opacity; or
- a transparent surface.

The settings page also controls the refresh interval, whether offline peers
are shown, and sort order (name vs. online-first).

## Requirements

- KDE Plasma 6
- Tailscale CLI (`tailscale status --json` must work as your desktop user,
  which it does by default — no `sudo` needed)

Verify before installing:

```bash
tailscale status --json
```

## Install

```bash
chmod +x install.sh
./install.sh
```

Then right-click the Plasma desktop or panel, choose **Add Widgets**, search
for **Tailscale Status**, and drag it onto the panel or desktop.

For development, rerun `./install.sh` after edits, then restart Plasma if its
QML cache does not pick up the change. Remove the installed widget with:

```bash
kpackagetool6 --type Plasma/Applet --remove com.casey.plasma.tailscale
```

## Package

Create a distributable package from the project directory:

```bash
zip -r tailscale-status.plasmoid metadata.json contents
```
