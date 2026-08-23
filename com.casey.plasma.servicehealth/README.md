# Service Health for KDE Plasma

A Plasma 6 widget showing at-a-glance status for a configurable list of
systemd services. Built as a companion to the Docker Containers and
Tailscale Status widgets — it covers the daemon layer underneath both
(`docker.service`, `tailscaled.service`) plus other home-server services
(`smbd`, `nmbd`, `cups` by default).

The compact icon shows a colored dot (green = all configured services
active, red = at least one failed, grey = something else — inactive,
activating, not installed) and the count of healthy services. The full view
lists each configured service with its friendly description, current state
(running / failed / inactive / not installed), and whether it's enabled to
start on boot.

This is a read-only status widget — it does not start, stop, or restart
services. Doing so would normally require a Polkit authentication prompt per
action, which is a bigger scope than a status widget; if you want that,
consider it a possible follow-up rather than something this widget does.

## Appearance and behavior

Open the widget's settings to choose among:

- the normal Plasma theme background;
- a translucent Plasma-colored surface with adjustable opacity; or
- a transparent surface.

The settings page also controls the refresh interval and the list of
monitored services — a comma-separated list of systemd unit names
(`.service` is added automatically if omitted), e.g.
`tailscaled,docker,smbd,nmbd,cups`.

## Requirements

- KDE Plasma 6
- `systemctl` (part of systemd) — reading unit status with `systemctl show`
  needs no special privileges

Verify before installing:

```bash
systemctl show tailscaled.service docker.service --property=Id,ActiveState
```

## Install

```bash
chmod +x install.sh
./install.sh
```

Then right-click the Plasma desktop or panel, choose **Add Widgets**, search
for **Service Health**, and drag it onto the panel or desktop.

For development, rerun `./install.sh` after edits, then restart Plasma if its
QML cache does not pick up the change. Remove the installed widget with:

```bash
kpackagetool6 --type Plasma/Applet --remove com.casey.plasma.servicehealth
```

## Package

Create a distributable package from the project directory:

```bash
zip -r service-health.plasmoid metadata.json contents
```
