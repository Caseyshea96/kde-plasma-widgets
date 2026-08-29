import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.kirigami 2.20 as Kirigami
import org.kde.ksvg 1.0 as Ksvg

PlasmoidItem {
    id: root

    readonly property string sectionMarker: "===SECTION==="
    readonly property string exitMarker: "===EXIT:"

    property var defaultRoutes: []
    property var tailscaleRoutes: []
    property bool ipv4Forwarding: false
    property bool ipv6Forwarding: false
    property bool haveData: false
    property string refreshError: ""
    property bool refreshBusy: false
    property bool refreshQueued: false
    property var lastSuccessfulRefresh: null

    readonly property bool showingStaleData: refreshError.length > 0 && haveData

    Plasmoid.icon: "preferences-system-network"
    Plasmoid.title: i18n("Route Status")
    toolTipMainText: i18n("Route Status")
    toolTipSubText: refreshError.length > 0
        ? refreshError
        : i18n("IP forwarding: %1 · %2 route(s) via tailscale0", ipv4Forwarding ? i18n("on") : i18n("off"), tailscaleRoutes.length)
    Plasmoid.backgroundHints: PlasmaCore.Types.ShadowBackground

    function commandError(data) {
        var stderr = (data["stderr"] || "").trim()
        if (data["exit code"] === undefined) {
            return stderr.length > 0 ? stderr : i18n("Command did not report a result")
        }
        var exitCode = Number(data["exit code"])
        if (exitCode === 0) return ""
        return stderr.length > 0
            ? stderr
            : i18n("Command failed (exit %1)", exitCode)
    }

    function parseSection(text) {
        var idx = text.lastIndexOf(root.exitMarker)
        if (idx === -1) return { exitCode: -1, content: text.trim() }
        return {
            exitCode: Number(text.substring(idx + root.exitMarker.length).trim()),
            content: text.substring(0, idx).trim()
        }
    }

    function parseOutput(output) {
        var parts = output.split(root.sectionMarker)
        if (parts.length !== 4) {
            return { ok: false, error: i18n("Unexpected command output") }
        }

        var defaultSection = root.parseSection(parts[0])
        var tailscaleSection = root.parseSection(parts[1])
        var ipv4Section = root.parseSection(parts[2])
        var ipv6Section = root.parseSection(parts[3])

        // The default route is the one piece of data we treat as load-bearing: if it
        // fails, something is fundamentally wrong (e.g. `ip` missing), so surface it.
        if (defaultSection.exitCode !== 0) {
            return { ok: false, error: i18n("Could not determine default route (exit %1)", defaultSection.exitCode) }
        }

        var defaultRoutesParsed
        try {
            defaultRoutesParsed = JSON.parse(defaultSection.content || "[]")
        } catch (error) {
            return { ok: false, error: i18n("Could not parse route output: %1", error) }
        }

        // The tailscale0 route and the /proc forwarding reads are each independent and
        // best-effort: a missing interface or an unsupported IPv6 stack is a normal
        // state, not an error, so a non-zero exit there just means "nothing to report".
        var tailscaleRoutesParsed = []
        if (tailscaleSection.exitCode === 0) {
            try {
                tailscaleRoutesParsed = JSON.parse(tailscaleSection.content || "[]")
            } catch (error) {
                tailscaleRoutesParsed = []
            }
        }

        return {
            ok: true,
            defaultRoutes: defaultRoutesParsed,
            tailscaleRoutes: tailscaleRoutesParsed,
            ipv4Forwarding: ipv4Section.exitCode === 0 && ipv4Section.content === "1",
            ipv6Forwarding: ipv6Section.exitCode === 0 && ipv6Section.content === "1"
        }
    }

    function refresh() {
        if (refreshBusy) {
            refreshQueued = true
            return
        }
        refreshBusy = true
        refreshError = ""
        var commands = [
            "ip -j route show default",
            "ip -j route show dev tailscale0",
            "cat /proc/sys/net/ipv4/ip_forward",
            "cat /proc/sys/net/ipv6/conf/all/forwarding"
        ]
        var cmd = commands.map(function(command) {
            return command + "; echo \"" + root.exitMarker + "$?\""
        }).join("; echo '" + root.sectionMarker + "'; ")
        routeCommand.connectSource(cmd)
    }

    P5Support.DataSource {
        id: routeCommand
        engine: "executable"

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.refreshBusy = false
            var runQueuedRefresh = root.refreshQueued
            root.refreshQueued = false

            var failure = root.commandError(data)
            if (failure.length > 0) {
                root.refreshError = failure
                if (runQueuedRefresh) refreshDelay.restart()
                return
            }

            var result = root.parseOutput(data["stdout"] || "")
            if (!result.ok) {
                root.refreshError = result.error
                if (runQueuedRefresh) refreshDelay.restart()
                return
            }

            root.defaultRoutes = result.defaultRoutes
            root.tailscaleRoutes = result.tailscaleRoutes
            root.ipv4Forwarding = result.ipv4Forwarding
            root.ipv6Forwarding = result.ipv6Forwarding
            root.haveData = true
            root.lastSuccessfulRefresh = new Date()
            root.refreshError = ""
            if (runQueuedRefresh) refreshDelay.restart()
        }
    }

    Timer {
        id: refreshDelay
        interval: 350
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: periodicRefresh
        interval: Math.max(2, Plasmoid.configuration.refreshInterval) * 1000
        running: false
        repeat: true
        onTriggered: root.refresh()
    }

    // Stagger this widget's periodic refresh against every other widget/instance so
    // several widgets added around the same time don't poll in lockstep forever.
    Timer {
        interval: Math.floor(Math.random() * periodicRefresh.interval)
        running: true
        repeat: false
        onTriggered: periodicRefresh.start()
    }

    Component.onCompleted: refresh()

    compactRepresentation: Kirigami.Icon {
        source: "preferences-system-network"
        opacity: (root.refreshError.length > 0 ? 0.55 : 1.0) * (compactMouse.containsMouse ? 1.0 : 0.85)

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            width: parent.width * 0.65
            height: width
            running: root.refreshBusy && !root.haveData
            visible: running
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.width * 0.3
            height: width
            radius: width / 2
            visible: !root.refreshBusy || root.haveData
            color: root.refreshError.length > 0
                ? Kirigami.Theme.negativeTextColor
                : (root.ipv4Forwarding ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor)
        }

        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.tailscaleRoutes.length
            visible: root.haveData && root.tailscaleRoutes.length > 0
            font.pixelSize: Math.max(9, parent.height * 0.36)
            font.bold: true
            color: "white"
            style: Text.Outline
            styleColor: "black"
        }

        MouseArea {
            id: compactMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: Item {
        id: fullRepresentation
        implicitWidth: Kirigami.Units.gridUnit * 20
        implicitHeight: Kirigami.Units.gridUnit * 16
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        CardBackground {
            id: cardBackground
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: cardBackground.marginLeft
            anchors.rightMargin: cardBackground.marginRight
            anchors.topMargin: cardBackground.marginTop
            anchors.bottomMargin: cardBackground.marginBottom
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "preferences-system-network"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    text: i18n("Route Status")
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StatusChip {
                    visible: root.haveData
                    label: root.ipv4Forwarding ? i18n("Forwarding: on") : i18n("Forwarding: off")
                    tint: root.ipv4Forwarding ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    text: i18n("Refresh")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    enabled: !root.refreshBusy
                    onClicked: root.refresh()
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.refreshError.length > 0
                text: root.refreshError
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.showingStaleData
                text: root.lastSuccessfulRefresh === null
                    ? i18n("Showing previously loaded data")
                    : i18n("Showing data from %1", Qt.formatTime(root.lastSuccessfulRefresh, Qt.DefaultLocaleShortDate))
                opacity: 0.7
            }

            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: root.refreshBusy && !root.haveData
                running: visible
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.haveData && (root.refreshError.length === 0 || root.showingStaleData)
                spacing: Kirigami.Units.smallSpacing

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    StatusChip {
                        iconName: "network-wired"
                        label: root.defaultRoutes.length > 0
                            ? i18n("Default: via %1 · %2", root.defaultRoutes[0].gateway || "?", root.defaultRoutes[0].dev || "?")
                            : i18n("No default route")
                        tint: root.defaultRoutes.length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                    }

                    StatusChip {
                        iconName: "emblem-shared"
                        label: root.ipv6Forwarding ? i18n("IPv6 forwarding: on") : i18n("IPv6 forwarding: off")
                        tint: root.ipv6Forwarding ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Label {
                    text: i18n("Routes via tailscale0")
                    font.bold: true
                    opacity: 0.85
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: root.tailscaleRoutes.length > 0

                    Repeater {
                        model: root.tailscaleRoutes
                        delegate: StatusChip {
                            iconName: "map-flat"
                            label: modelData.dst || i18n("unknown")
                            tint: Kirigami.Theme.positiveTextColor
                        }
                    }
                }

                PlasmaComponents3.Label {
                    visible: root.tailscaleRoutes.length === 0
                    text: i18n("No subnets are currently routed through tailscale0 on this device.")
                    opacity: 0.7
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}
