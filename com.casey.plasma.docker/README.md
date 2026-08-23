# Docker Containers for KDE Plasma

A Plasma 6 widget for viewing and controlling containers on the local Docker
daemon. It shows running/total counts, supports concurrent start, stop, and
restart actions, and includes a container detail page with ports, Compose
project information, selectable IDs, and recent logs.

## Appearance and behavior

Open the widget's settings to choose among:

- the normal Plasma theme background;
- a translucent Plasma-colored surface with adjustable opacity; or
- a transparent surface.

The widget renders these surfaces itself because Plasma does not reliably
refresh shell-provided backgrounds after a setting changes. **Theme** uses the
native Plasma frame, **Translucent** uses an explicit 10–95% opacity, and
**Transparent** has no fill. The settings page also controls the refresh
interval, stopped-container visibility, and sorting.

## Requirements

- KDE Plasma 6
- Docker CLI
- Permission to run `docker ps` as your desktop user

Verify Docker access before installing:

```bash
docker ps
```

If that command reports a permission error, configure rootless Docker or add
your user to Docker's access group before using the widget. Be aware that
membership in the `docker` group is effectively root-level access.

## Install

```bash
chmod +x install.sh
./install.sh
```

Then right-click the Plasma desktop or panel, choose **Add Widgets**, search for
**Docker Containers**, and drag it onto the panel or desktop.

For development, rerun `./install.sh` after edits, then restart Plasma if its
QML cache does not pick up the change. Remove the installed widget
with:

```bash
kpackagetool6 --type Plasma/Applet --remove com.casey.plasma.docker
```

## Package

Create a distributable package from the project directory:

```bash
zip -r docker-containers.plasmoid metadata.json contents
```
