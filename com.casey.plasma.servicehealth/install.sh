#!/usr/bin/env bash
set -euo pipefail

widget_id="com.casey.plasma.servicehealth"
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if command -v kpackagetool6 >/dev/null 2>&1; then
    package_tool="kpackagetool6"
elif command -v kpackagetool5 >/dev/null 2>&1; then
    package_tool="kpackagetool5"
else
    echo "This requires KDE Plasma and kpackagetool6 (or kpackagetool5 for Plasma 5)." >&2
    exit 1
fi

installed_path="$("$package_tool" --type Plasma/Applet --show "$widget_id" 2>/dev/null | sed -n 's/^ *Path *: *//p')"
installed_path="${installed_path%/}"

if [ -n "$installed_path" ] && [ "$installed_path" = "$project_dir" ]; then
    # Already registered in place from this directory. Running --upgrade here
    # is destructive: some kpackagetool6 versions remove the install path
    # before copying from the source, and since they're the same directory
    # that deletes this project. Nothing to do; edits take effect after
    # restarting the widget or plasmashell.
    echo "Already installed in place. Restart the widget (or plasmashell) to pick up changes."
elif [ -n "$installed_path" ]; then
    "$package_tool" --type Plasma/Applet --upgrade "$project_dir"
    echo "Installed Service Health. Add it from Plasma's widget picker."
else
    "$package_tool" --type Plasma/Applet --install "$project_dir"
    echo "Installed Service Health. Add it from Plasma's widget picker."
fi
