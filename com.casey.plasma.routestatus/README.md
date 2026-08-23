# Route Status for KDE Plasma

A Plasma 6 widget for the OS/kernel-level view of routing, as a companion to
the Tailscale Status widget — that widget shows what Tailscale's control
plane thinks is advertised; this one shows what the kernel routing table and
IP-forwarding sysctls are actually doing right now. Useful while
experimenting with exit-node or subnet-route configuration, where the two
can disagree (e.g. a route advertised in Tailscale but not actually
forwarding because `net.ipv4.ip_forward` is off).

The compact icon shows a colored dot (green = IPv4 forwarding on, red = off
or last refresh failed) and the count of routes currently going out via the
`tailscale0` interface. The full view shows the default route (gateway +
interface), IPv4/IPv6 forwarding state, and the list of subnets currently
routed through `tailscale0` according to `ip route`.

This is a read-only status widget — it does not change routing or
forwarding configuration.

## Appearance and behavior

Open the widget's settings to choose among:

- the normal Plasma theme background;
- a translucent Plasma-colored surface with adjustable opacity; or
- a transparent surface.

The settings page also controls the refresh interval.

## Requirements

- KDE Plasma 6
- `ip` (iproute2) with JSON output support (`ip -j`) — standard on any
  reasonably current Linux distribution

Verify before installing:

```bash
ip -j route show default
```

## Install

```bash
chmod +x install.sh
./install.sh
```

Then right-click the Plasma desktop or panel, choose **Add Widgets**, search
for **Route Status**, and drag it onto the panel or desktop.

For development, rerun `./install.sh` after edits, then restart Plasma if its
QML cache does not pick up the change. Remove the installed widget with:

```bash
kpackagetool6 --type Plasma/Applet --remove com.casey.plasma.routestatus
```

## Package

Create a distributable package from the project directory:

```bash
zip -r route-status.plasmoid metadata.json contents
```
