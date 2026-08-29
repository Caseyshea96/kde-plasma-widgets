# KDE Plasma widgets

Five self-contained Plasma applets (KF6 / Plasma 6):

- **Docker Containers** (`com.casey.plasma.docker`) — View and control local Docker containers from Plasma
- **Jellyfin Now Playing** (`com.casey.plasma.jellyfin`) — Active Jellyfin streams: title, user, device, and transcode state
- **Route Status** (`com.casey.plasma.routestatus`) — Default route, IP forwarding state, and routes via tailscale0
- **Service Health** (`com.casey.plasma.servicehealth`) — At-a-glance status for key systemd services
- **Tailscale Status** (`com.casey.plasma.tailscale`) — Tailnet peer status, exit node, and advertised subnet routes

Each has its own `README.md` with widget-specific setup notes (permissions, required CLI tools, etc.).

## Installing

Each widget is installed independently:

```sh
./com.casey.plasma.<widget>/install.sh
```

## Shared code

Plasma installs each widget as an independent, self-contained package, so
there's no runtime-shared import path between them. Code that's common to
all five — `StatusChip.qml`, the `CardBackground.qml` card/translucent/theme
background component, and `install.sh` — lives once in [shared/](shared/)
and is fanned out into each package's `contents/ui/` (and root) by
[sync.sh](sync.sh).

After editing anything under `shared/`, run:

```sh
./sync.sh
```

to propagate the change to every widget before reinstalling.
