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

    function parseOutput(output) {
        var parts = output.split(root.sectionMarker)
        if (parts.length !== 4) {
            return { ok: false, error: i18n("Unexpected command output") }
        }
        try {
            var defaultRoutesParsed = JSON.parse(parts[0].trim() || "[]")
            var tailscaleRoutesParsed = JSON.parse(parts[1].trim() || "[]")
            var ipv4 = parts[2].trim() === "1"
            var ipv6 = parts[3].trim() === "1"
            return {
                ok: true,
                defaultRoutes: defaultRoutesParsed,
                tailscaleRoutes: tailscaleRoutesParsed,
                ipv4Forwarding: ipv4,
                ipv6Forwarding: ipv6
            }
        } catch (error) {
            return { ok: false, error: i18n("Could not parse route output: %1", error) }
        }
    }

    function refresh() {
        if (refreshBusy) {
            refreshQueued = true
            return
        }
        refreshBusy = true
        refreshError = ""
        var cmd = "ip -j route show default; echo '" + sectionMarker + "'; "
            + "ip -j route show dev tailscale0; echo '" + sectionMarker + "'; "
            + "cat /proc/sys/net/ipv4/ip_forward; echo '" + sectionMarker + "'; "
            + "cat /proc/sys/net/ipv6/conf/all/forwarding"
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
        interval: Math.max(2, Plasmoid.configuration.refreshInterval) * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
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

        Ksvg.FrameSvgItem {
            id: widgetBackground
            anchors.fill: parent
            z: -1
            visible: Plasmoid.configuration.backgroundStyle === 0
            imagePath: "widgets/background"
        }

        Rectangle {
            anchors.fill: parent
            z: -1
            visible: Plasmoid.configuration.backgroundStyle === 1
            radius: Kirigami.Units.smallSpacing * 3
            color: Kirigami.Theme.backgroundColor
            opacity: Math.max(10, Math.min(95, Plasmoid.configuration.backgroundOpacity)) / 100
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Plasmoid.configuration.backgroundStyle === 0
                ? Math.max(Kirigami.Units.largeSpacing, widgetBackground.margins.left)
                : Kirigami.Units.largeSpacing
            anchors.rightMargin: Plasmoid.configuration.backgroundStyle === 0
                ? Math.max(Kirigami.Units.largeSpacing, widgetBackground.margins.right)
                : Kirigami.Units.largeSpacing
            anchors.topMargin: Plasmoid.configuration.backgroundStyle === 0
                ? Math.max(Kirigami.Units.largeSpacing, widgetBackground.margins.top)
                : Kirigami.Units.largeSpacing
            anchors.bottomMargin: Plasmoid.configuration.backgroundStyle === 0
                ? Math.max(Kirigami.Units.largeSpacing, widgetBackground.margins.bottom)
                : Kirigami.Units.largeSpacing
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
                        iconName: "network-wired"
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
