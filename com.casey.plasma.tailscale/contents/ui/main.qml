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

    property string backendState: "Unknown"
    property string selfHostName: ""
    property var selfIPs: []
    property bool offersExitNode: false
    property var advertisedRoutes: []
    property string exitNodeName: ""
    property var allPeers: []
    property var healthWarnings: []
    property string refreshError: ""
    property bool refreshBusy: false
    property bool refreshQueued: false
    property var lastSuccessfulRefresh: null

    readonly property bool backendRunning: backendState === "Running"
    readonly property int onlineCount: {
        var count = 0
        for (var i = 0; i < allPeers.length; ++i) {
            if (allPeers[i].Online) count++
        }
        return count
    }
    readonly property var peers: {
        var result = allPeers.slice()
        if (!Plasmoid.configuration.showOffline) {
            result = result.filter(function(p) { return p.Online })
        }
        if (Plasmoid.configuration.sortMode === 0) {
            result.sort(function(a, b) { return a.HostName.localeCompare(b.HostName) })
        } else {
            result.sort(function(a, b) {
                if (a.Online !== b.Online) return a.Online ? -1 : 1
                return a.HostName.localeCompare(b.HostName)
            })
        }
        return result
    }
    readonly property bool showingStaleData: refreshError.length > 0 && allPeers.length > 0
    readonly property bool showData: backendRunning && (refreshError.length === 0 || showingStaleData)

    Plasmoid.icon: "network-vpn"
    Plasmoid.title: i18n("Tailscale Status")
    toolTipMainText: i18n("Tailscale")
    toolTipSubText: {
        if (refreshError.length > 0) return refreshError
        if (!backendRunning) return i18n("Backend: %1", backendState)
        var line = i18n("%1/%2 peers online", onlineCount, allPeers.length)
        line += "\n" + (exitNodeName.length > 0
            ? i18n("Exit node: %1", exitNodeName)
            : i18n("Exit node: none active"))
        line += "\n" + (advertisedRoutes.length > 0
            ? i18n("Routes advertised: %1", advertisedRoutes.join(", "))
            : i18n("Routes advertised: none"))
        return line
    }
    Plasmoid.backgroundHints: PlasmaCore.Types.ShadowBackground

    function commandError(data) {
        var stderr = (data["stderr"] || "").trim()
        if (data["exit code"] === undefined) {
            return stderr.length > 0 ? stderr : i18n("tailscale status did not report a result")
        }
        var exitCode = Number(data["exit code"])
        if (exitCode === 0) return ""
        return stderr.length > 0
            ? stderr
            : i18n("tailscale status failed (exit %1)", exitCode)
    }

    function isZeroTime(value) {
        return !value || value.indexOf("0001-01-01") === 0
    }

    function parseStatus(output) {
        var data
        try {
            data = JSON.parse(output)
        } catch (error) {
            return { ok: false, error: i18n("Could not parse tailscale output: %1", error) }
        }

        var self = data.Self || {}
        var peersObj = data.Peer || {}
        var peers = []
        var exitNode = ""
        for (var key in peersObj) {
            var p = peersObj[key]
            peers.push(p)
            if (p.ExitNode) exitNode = p.HostName
        }

        return {
            ok: true,
            backendState: data.BackendState || "Unknown",
            selfHostName: self.HostName || "",
            selfIPs: self.TailscaleIPs || [],
            offersExitNode: !!self.ExitNodeOption,
            advertisedRoutes: self.PrimaryRoutes || [],
            exitNodeName: exitNode,
            peers: peers,
            health: data.Health || []
        }
    }

    function refresh() {
        if (refreshBusy) {
            refreshQueued = true
            return
        }
        refreshBusy = true
        refreshError = ""
        statusCommand.connectSource("tailscale status --json")
    }

    P5Support.DataSource {
        id: statusCommand
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

            var result = root.parseStatus(data["stdout"] || "")
            if (!result.ok) {
                root.refreshError = result.error
                if (runQueuedRefresh) refreshDelay.restart()
                return
            }

            root.backendState = result.backendState
            root.selfHostName = result.selfHostName
            root.selfIPs = result.selfIPs
            root.offersExitNode = result.offersExitNode
            root.advertisedRoutes = result.advertisedRoutes
            root.exitNodeName = result.exitNodeName
            root.allPeers = result.peers
            root.healthWarnings = result.health
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
        source: "network-vpn"
        opacity: (root.refreshError.length > 0 || !root.backendRunning ? 0.55 : 1.0) * (compactMouse.containsMouse ? 1.0 : 0.85)

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            width: parent.width * 0.65
            height: width
            running: root.refreshBusy && root.allPeers.length === 0
            visible: running
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.width * 0.3
            height: width
            radius: width / 2
            visible: !root.refreshBusy || root.allPeers.length > 0
            color: root.refreshError.length > 0
                ? Kirigami.Theme.negativeTextColor
                : (root.backendRunning ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor)
        }

        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.onlineCount
            visible: root.backendRunning && root.allPeers.length > 0
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
        implicitWidth: Kirigami.Units.gridUnit * 22
        implicitHeight: Kirigami.Units.gridUnit * 26
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

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
                    source: "network-vpn"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    text: root.selfHostName.length > 0 ? root.selfHostName : i18n("Tailscale")
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StatusChip {
                    visible: root.backendRunning
                    label: i18n("%1/%2 online", root.onlineCount, root.allPeers.length)
                    tint: root.allPeers.length > 0 && root.onlineCount === root.allPeers.length
                        ? Kirigami.Theme.positiveTextColor
                        : Kirigami.Theme.neutralTextColor
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

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.refreshError.length === 0 && !root.backendRunning
                text: i18n("Backend state: %1", root.backendState)
                color: Kirigami.Theme.neutralTextColor
                wrapMode: Text.Wrap
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.showData
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.showData
                spacing: Kirigami.Units.smallSpacing

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    StatusChip {
                        iconName: "network-workgroup"
                        label: root.exitNodeName.length > 0
                            ? i18n("Exit node: %1", root.exitNodeName)
                            : i18n("No active exit node")
                        tint: root.exitNodeName.length > 0
                            ? Kirigami.Theme.positiveTextColor
                            : Kirigami.Theme.disabledTextColor
                    }

                    StatusChip {
                        visible: root.offersExitNode
                        iconName: "emblem-shared"
                        label: i18n("Offers exit node")
                        tint: Kirigami.Theme.neutralTextColor
                    }

                    StatusChip {
                        iconName: "map-flat"
                        label: root.advertisedRoutes.length > 0
                            ? i18n("Routes: %1", root.advertisedRoutes.join(", "))
                            : i18n("No routes advertised")
                        tint: root.advertisedRoutes.length > 0
                            ? Kirigami.Theme.positiveTextColor
                            : Kirigami.Theme.disabledTextColor
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.healthWarnings.length > 0
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.14)
                    implicitHeight: healthLabel.implicitHeight + Kirigami.Units.smallSpacing * 2

                    PlasmaComponents3.Label {
                        id: healthLabel
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: root.healthWarnings.join("\n")
                        wrapMode: Text.Wrap
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.showData
            }

            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: root.refreshBusy && root.allPeers.length === 0
                running: visible
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                visible: !root.refreshBusy && root.showData && root.peers.length === 0
                text: root.allPeers.length > 0
                    ? i18n("No peers match the current filter")
                    : i18n("No peers found")
                opacity: 0.7
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.showData && root.peers.length > 0

                ListView {
                    id: peerList
                    model: root.peers
                    spacing: Kirigami.Units.smallSpacing
                    clip: true

                    delegate: PlasmaComponents3.ItemDelegate {
                        width: peerList.width
                        height: details.implicitHeight + Kirigami.Units.largeSpacing
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: Kirigami.Units.smallSpacing
                        hoverEnabled: false

                        background: Rectangle {
                            radius: 8
                            color: Kirigami.Theme.backgroundColor
                            opacity: 0.35
                        }

                        contentItem: RowLayout {
                            id: details
                            spacing: Kirigami.Units.smallSpacing

                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.5
                                Layout.preferredHeight: width
                                radius: width / 2
                                color: modelData.Online
                                    ? Kirigami.Theme.positiveTextColor
                                    : Kirigami.Theme.disabledTextColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlasmaComponents3.Label {
                                        text: modelData.HostName
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Kirigami.Icon {
                                        source: "network-workgroup"
                                        visible: modelData.ExitNode
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        PlasmaComponents3.ToolTip.text: i18n("Active exit node")
                                        PlasmaComponents3.ToolTip.visible: exitIconMouse.containsMouse

                                        MouseArea {
                                            id: exitIconMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }
                                    }

                                    Kirigami.Icon {
                                        source: "map-flat"
                                        visible: (modelData.PrimaryRoutes || []).length > 0
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        PlasmaComponents3.ToolTip.text: i18n("Advertises: %1", (modelData.PrimaryRoutes || []).join(", "))
                                        PlasmaComponents3.ToolTip.visible: routeIconMouse.containsMouse

                                        MouseArea {
                                            id: routeIconMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }
                                    }
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: modelData.Online
                                        ? (modelData.OS || "") + " · " + i18n("online")
                                        : (modelData.OS || "") + " · " + (root.isZeroTime(modelData.LastSeen)
                                            ? i18n("offline")
                                            : i18n("last seen %1", Qt.formatDateTime(new Date(modelData.LastSeen), "yyyy-MM-dd hh:mm")))
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
