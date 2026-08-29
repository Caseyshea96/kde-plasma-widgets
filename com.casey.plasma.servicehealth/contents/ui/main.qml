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

    property var allServices: []
    property string refreshError: ""
    property bool refreshBusy: false
    property bool refreshQueued: false
    property var lastSuccessfulRefresh: null

    readonly property int healthyCount: {
        var count = 0
        for (var i = 0; i < allServices.length; ++i) {
            if (statusFor(allServices[i]).healthy) count++
        }
        return count
    }
    readonly property int failedCount: {
        var count = 0
        for (var i = 0; i < allServices.length; ++i) {
            if (allServices[i].ActiveState === "failed") count++
        }
        return count
    }
    readonly property bool showingStaleData: refreshError.length > 0 && allServices.length > 0

    Plasmoid.icon: "preferences-system-services"
    Plasmoid.title: i18n("Service Health")
    toolTipMainText: i18n("Service Health")
    toolTipSubText: refreshError.length > 0
        ? refreshError
        : i18n("%1/%2 services healthy", healthyCount, allServices.length)
    Plasmoid.backgroundHints: PlasmaCore.Types.ShadowBackground

    function commandError(data) {
        var stderr = (data["stderr"] || "").trim()
        if (data["exit code"] === undefined) {
            return stderr.length > 0 ? stderr : i18n("systemctl did not report a result")
        }
        var exitCode = Number(data["exit code"])
        if (exitCode === 0) return ""
        return stderr.length > 0
            ? stderr
            : i18n("systemctl failed (exit %1)", exitCode)
    }

    function parseUnitList(configString) {
        var raw = (configString || "").split(",")
        var result = []
        for (var i = 0; i < raw.length; ++i) {
            var name = raw[i].trim()
            if (name.length === 0) continue
            if (name.indexOf(".") < 0) name += ".service"
            if (!/^[a-zA-Z0-9_.@-]+$/.test(name)) continue
            result.push(name)
        }
        return result
    }

    function parseServices(output) {
        var stanzas = output.split(/\n\s*\n/)
        var result = []
        for (var i = 0; i < stanzas.length; ++i) {
            var block = stanzas[i].trim()
            if (block.length === 0) continue
            var lines = block.split("\n")
            var record = {}
            for (var j = 0; j < lines.length; ++j) {
                var idx = lines[j].indexOf("=")
                if (idx < 0) continue
                record[lines[j].slice(0, idx)] = lines[j].slice(idx + 1)
            }
            if (!record.Id) continue
            result.push(record)
        }
        return result
    }

    function statusFor(service) {
        if (service.LoadState !== "loaded") {
            return { state: i18n("not installed"), tint: Kirigami.Theme.disabledTextColor, healthy: false }
        }
        if (service.ActiveState === "failed") {
            return { state: i18n("failed"), tint: Kirigami.Theme.negativeTextColor, healthy: false }
        }
        if (service.ActiveState === "active") {
            return { state: i18n("running"), tint: Kirigami.Theme.positiveTextColor, healthy: true }
        }
        return { state: service.ActiveState || i18n("unknown"), tint: Kirigami.Theme.neutralTextColor, healthy: false }
    }

    function serviceLabel(service) {
        if (service.Description && service.Description.length > 0) return service.Description
        return (service.Id || "").replace(/\.service$/, "")
    }

    function refresh() {
        if (refreshBusy) {
            refreshQueued = true
            return
        }
        var units = parseUnitList(Plasmoid.configuration.units)
        if (units.length === 0) {
            refreshError = i18n("No valid service names configured")
            allServices = []
            return
        }
        refreshBusy = true
        refreshError = ""
        var cmd = "systemctl show " + units.join(" ") + " --property=Id,Description,LoadState,ActiveState,SubState,UnitFileState --no-pager"
        statusCommand.connectSource(cmd)
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

            root.allServices = root.parseServices(data["stdout"] || "")
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
        source: "preferences-system-services"
        opacity: (root.refreshError.length > 0 ? 0.55 : 1.0) * (compactMouse.containsMouse ? 1.0 : 0.85)

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            width: parent.width * 0.65
            height: width
            running: root.refreshBusy && root.allServices.length === 0
            visible: running
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.width * 0.3
            height: width
            radius: width / 2
            visible: !root.refreshBusy || root.allServices.length > 0
            color: root.refreshError.length > 0
                ? Kirigami.Theme.negativeTextColor
                : (root.failedCount > 0
                    ? Kirigami.Theme.negativeTextColor
                    : (root.healthyCount === root.allServices.length ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor))
        }

        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.healthyCount
            visible: root.allServices.length > 0
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
        implicitHeight: Kirigami.Units.gridUnit * 22
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
                    source: "preferences-system-services"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    text: i18n("Service Health")
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StatusChip {
                    visible: root.allServices.length > 0
                    label: i18n("%1/%2 healthy", root.healthyCount, root.allServices.length)
                    tint: root.failedCount > 0
                        ? Kirigami.Theme.negativeTextColor
                        : (root.healthyCount === root.allServices.length ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor)
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
                visible: root.refreshBusy && root.allServices.length === 0
                running: visible
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                visible: !root.refreshBusy && root.refreshError.length === 0 && root.allServices.length === 0
                text: i18n("No services configured")
                opacity: 0.7
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.allServices.length > 0 && (root.refreshError.length === 0 || root.showingStaleData)

                ListView {
                    id: serviceList
                    model: root.allServices
                    spacing: Kirigami.Units.smallSpacing
                    clip: true

                    delegate: PlasmaComponents3.ItemDelegate {
                        width: serviceList.width
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
                                color: root.statusFor(modelData).tint
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.serviceLabel(modelData)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.statusFor(modelData).state
                                        + (modelData.UnitFileState ? " · " + modelData.UnitFileState : "")
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
