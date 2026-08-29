#!/usr/bin/env bash
# Copies the shared/ sources into every plasmoid package. Plasma installs
# each widget as an independent, self-contained directory, so the shared
# files can't be imported at runtime — they're kept in one place here and
# fanned out on demand instead. Run this after editing anything in shared/.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

for widget_dir in "$repo_dir"/com.casey.plasma.*/; do
    widget_dir="${widget_dir%/}"
    [ -f "$widget_dir/metadata.json" ] || continue

    cp "$repo_dir/shared/ui/StatusChip.qml" "$widget_dir/contents/ui/StatusChip.qml"
    cp "$repo_dir/shared/ui/CardBackground.qml" "$widget_dir/contents/ui/CardBackground.qml"
    cp "$repo_dir/shared/install.sh" "$widget_dir/install.sh"
    chmod +x "$widget_dir/install.sh"

    echo "Synced $(basename -- "$widget_dir")"
done
