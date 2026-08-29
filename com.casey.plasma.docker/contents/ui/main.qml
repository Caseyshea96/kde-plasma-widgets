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

    property var allContainers: []
    property var pendingActions: ({})
    property var actionBySource: ({})
    property var pendingLogs: ({})
    property var logBySource: ({})
    property var selectedContainer: null
    property string refreshError: ""
    property string actionError: ""
    property string logsText: ""
    property string logsError: ""
    property bool refreshBusy: false
    property bool refreshQueued: false
    property var lastSuccessfulRefresh: null
    property int runningCount: {
        var count = 0
        for (var i = 0; i < allContainers.length; ++i) {
            if (allContainers[i].isRunning) count++
        }
        return count
    }
    property var containers: {
        var result = []
        for (var i = 0; i < allContainers.length; ++i) {
            if (Plasmoid.configuration.showStopped || allContainers[i].isRunning) {
                result.push(allContainers[i])
            }
        }

        if (Plasmoid.configuration.sortMode === 0) {
            result.sort(function(a, b) { return a.Names.localeCompare(b.Names) })
        } else if (Plasmoid.configuration.sortMode === 1) {
            result.sort(function(a, b) {
                if (a.isRunning !== b.isRunning) return a.isRunning ? -1 : 1
                return a.Names.localeCompare(b.Names)
            })
        }
        return result
    }
    readonly property bool anyBusy: refreshBusy || Object.keys(pendingActions).length > 0
    readonly property bool showingStaleData: refreshError.length > 0 && allContainers.length > 0
    readonly property bool logsBusy: selectedContainer !== null && !!pendingLogs[selectedContainer.ID]

    Plasmoid.icon: "system-run"
    Plasmoid.title: i18n("Docker Containers")
    toolTipMainText: i18n("Docker Containers")
    toolTipSubText: refreshError.length > 0
        ? refreshError
        : i18n("%1 running · %2 total", runningCount, allContainers.length)
    Plasmoid.backgroundHints: PlasmaCore.Types.ShadowBackground

    function commandError(data) {
        var stderr = (data["stderr"] || "").trim()
        if (data["exit code"] === undefined) {
            return stderr.length > 0 ? stderr : i18n("Docker command did not report a result")
        }
        var exitCode = Number(data["exit code"])
        if (exitCode === 0) return ""
        return stderr.length > 0
            ? stderr
            : i18n("Docker command failed (exit %1)", exitCode)
    }

    function shortImage(image) {
        return (image || "").split("@")[0]
    }

    function refresh() {
        if (refreshBusy) {
            refreshQueued = true
            return
        }
        refreshBusy = true
        refreshError = ""
        refreshCommand.connectSource("docker ps -a --no-trunc --format '{{json .}}'")
    }

    function parseContainers(output) {
        var parsed = []
        var text = output.trim()
        var lines = text.length > 0 ? text.split("\n") : []
        for (var i = 0; i < lines.length; ++i) {
            try {
                var item = JSON.parse(lines[i])
                if (!item.ID || !item.Names || typeof item.State === "undefined") {
                    return { ok: false, error: i18n("Docker returned an incomplete container record.") }
                }
                item.isRunning = item.State === "running"
                parsed.push(item)
            } catch (error) {
                return { ok: false, error: i18n("Could not parse Docker output: %1", error) }
            }
        }
        return { ok: true, containers: parsed }
    }

    function runAction(action, id) {
        if (["start", "stop", "restart"].indexOf(action) < 0 || !/^[a-fA-F0-9]+$/.test(id)) return
        if (pendingActions[id]) return

        var source = "docker " + action + " " + id
        var nextPending = Object.assign({}, pendingActions)
        var nextSources = Object.assign({}, actionBySource)
        nextPending[id] = action
        nextSources[source] = { id: id, action: action }
        pendingActions = nextPending
        actionBySource = nextSources
        actionError = ""
        actionCommand.connectSource(source)
    }

    function actionFor(id) {
        return pendingActions[id] || ""
    }

    function labelValue(labels, key) {
        // Split only where the comma is followed by another label key, so
        // comma characters inside a label's own value aren't treated as
        // separators.
        var entries = (labels || "").split(/,(?=[\w.\-]+=)/)
        var prefix = key + "="
        for (var i = 0; i < entries.length; ++i) {
            if (entries[i].indexOf(prefix) === 0) return entries[i].slice(prefix.length)
        }
        return ""
    }

    function showDetails(container) {
        selectedContainer = container
        logsText = ""
        logsError = ""
        loadLogs()
    }

    function loadLogs() {
        if (!selectedContainer || pendingLogs[selectedContainer.ID]) return
        if (!/^[a-fA-F0-9]+$/.test(selectedContainer.ID)) return
        var source = "docker logs --timestamps --tail 100 " + selectedContainer.ID
        var nextPending = Object.assign({}, pendingLogs)
        var nextSources = Object.assign({}, logBySource)
        nextPending[selectedContainer.ID] = true
        nextSources[source] = selectedContainer.ID
        pendingLogs = nextPending
        logBySource = nextSources
        logsError = ""
        logCommand.connectSource(source)
    }

    function updateSelectedContainer() {
        if (!selectedContainer) return
        for (var i = 0; i < allContainers.length; ++i) {
            if (allContainers[i].ID === selectedContainer.ID) {
                selectedContainer = allContainers[i]
                return
            }
        }
        selectedContainer = null
    }

    P5Support.DataSource {
        id: refreshCommand
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

            var result = root.parseContainers(data["stdout"] || "")
            if (!result.ok) {
                root.refreshError = result.error
                if (runQueuedRefresh) refreshDelay.restart()
                return
            }

            root.allContainers = result.containers
            root.lastSuccessfulRefresh = new Date()
            root.refreshError = ""
            root.updateSelectedContainer()
            if (runQueuedRefresh) refreshDelay.restart()
        }
    }

    P5Support.DataSource {
        id: actionCommand
        engine: "executable"

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            var operation = root.actionBySource[sourceName]
            if (!operation) return

            var nextPending = Object.assign({}, root.pendingActions)
            var nextSources = Object.assign({}, root.actionBySource)
            delete nextPending[operation.id]
            delete nextSources[sourceName]
            root.pendingActions = nextPending
            root.actionBySource = nextSources

            var failure = root.commandError(data)
            if (failure.length > 0) {
                root.actionError = i18n("%1 failed: %2", operation.action, failure)
            }
            refreshDelay.restart()
        }
    }

    P5Support.DataSource {
        id: logCommand
        engine: "executable"

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            var containerId = root.logBySource[sourceName]
            if (!containerId) return

            var nextPending = Object.assign({}, root.pendingLogs)
            var nextSources = Object.assign({}, root.logBySource)
            delete nextPending[containerId]
            delete nextSources[sourceName]
            root.pendingLogs = nextPending
            root.logBySource = nextSources

            if (!root.selectedContainer || root.selectedContainer.ID !== containerId) return
            var failure = root.commandError(data)
            root.logsText = (data["stdout"] || "") + (data["stderr"] || "")
            root.logsError = failure
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
        source: "system-run"
        opacity: (root.refreshError.length > 0 ? 0.55 : 1.0) * (compactMouse.containsMouse ? 1.0 : 0.85)

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            width: parent.width * 0.65
            height: width
            running: root.anyBusy
            visible: running
        }

        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.runningCount
            visible: !root.anyBusy && root.runningCount > 0
            font.pixelSize: Math.max(9, parent.height * 0.36)
            font.bold: true
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
        implicitWidth: Kirigami.Units.gridUnit * 24
        implicitHeight: Kirigami.Units.gridUnit * 28
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

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

                PlasmaComponents3.ToolButton {
                    visible: root.selectedContainer !== null
                    icon.name: "go-previous"
                    text: i18n("Back")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    onClicked: root.selectedContainer = null
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                }

                Kirigami.Icon {
                    visible: root.selectedContainer === null
                    source: "system-run"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    text: root.selectedContainer ? root.selectedContainer.Names : i18n("Docker Containers")
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StatusChip {
                    visible: root.selectedContainer === null
                    label: i18n("%1/%2 running", root.runningCount, root.allContainers.length)
                    tint: root.allContainers.length > 0 && root.runningCount === root.allContainers.length
                        ? Kirigami.Theme.positiveTextColor
                        : Kirigami.Theme.neutralTextColor
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    text: root.selectedContainer ? i18n("Refresh logs") : i18n("Refresh")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    enabled: root.selectedContainer ? !root.logsBusy : !root.refreshBusy
                    onClicked: root.selectedContainer ? root.loadLogs() : root.refresh()
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.refreshError.length > 0 || root.actionError.length > 0
                text: root.actionError.length > 0 ? root.actionError : root.refreshError
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
                visible: root.refreshBusy && root.allContainers.length === 0
                running: visible
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                visible: !root.refreshBusy && root.refreshError.length === 0
                    && root.containers.length === 0 && root.selectedContainer === null
                text: root.allContainers.length > 0
                    ? i18n("No containers match the current filter")
                    : i18n("No containers found")
                opacity: 0.7
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedContainer === null && root.containers.length > 0

                ListView {
                    id: containerList
                    model: root.containers
                    spacing: Kirigami.Units.smallSpacing
                    clip: true

                    delegate: PlasmaComponents3.ItemDelegate {
                        width: containerList.width
                        height: details.implicitHeight + Kirigami.Units.largeSpacing
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: Kirigami.Units.smallSpacing
                        onClicked: root.showDetails(modelData)

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
                            opacity: parent.hovered ? 0.22 : 0.35
                        }

                        contentItem: RowLayout {
                            id: details
                            spacing: Kirigami.Units.smallSpacing

                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.5
                                Layout.preferredHeight: width
                                radius: width / 2
                                color: modelData.isRunning
                                    ? Kirigami.Theme.positiveTextColor
                                    : Kirigami.Theme.disabledTextColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: modelData.Names
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.shortImage(modelData.Image) + " · " + modelData.Status
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                }
                            }

                            PlasmaComponents3.BusyIndicator {
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: width
                                visible: root.actionFor(modelData.ID).length > 0
                                running: visible
                            }

                            PlasmaComponents3.ToolButton {
                                visible: root.actionFor(modelData.ID).length === 0
                                icon.name: modelData.isRunning ? "media-playback-stop" : "media-playback-start"
                                text: modelData.isRunning ? i18n("Stop") : i18n("Start")
                                display: PlasmaComponents3.AbstractButton.IconOnly
                                onClicked: root.runAction(modelData.isRunning ? "stop" : "start", modelData.ID)
                                PlasmaComponents3.ToolTip.text: text
                                PlasmaComponents3.ToolTip.visible: hovered
                            }

                            PlasmaComponents3.ToolButton {
                                icon.name: "view-refresh"
                                text: i18n("Restart")
                                display: PlasmaComponents3.AbstractButton.IconOnly
                                enabled: modelData.isRunning && root.actionFor(modelData.ID).length === 0
                                onClicked: root.runAction("restart", modelData.ID)
                                PlasmaComponents3.ToolTip.text: text
                                PlasmaComponents3.ToolTip.visible: hovered
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedContainer !== null
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: root.selectedContainer
                        ? root.shortImage(root.selectedContainer.Image) + " · " + root.selectedContainer.Status
                        : ""
                    wrapMode: Text.Wrap
                    opacity: 0.8
                }

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents3.Label {
                        text: i18n("ID:")
                    }

                    PlasmaComponents3.TextArea {
                        id: containerIdText
                        Layout.fillWidth: true
                        text: root.selectedContainer ? root.selectedContainer.ID : ""
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        textFormat: Text.PlainText
                        background: null
                        leftPadding: 0
                        rightPadding: 0
                        topPadding: 0
                        bottomPadding: 0
                    }

                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-copy"
                        text: i18n("Copy container ID")
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        onClicked: {
                            containerIdText.selectAll()
                            containerIdText.copy()
                            containerIdText.deselect()
                        }
                        PlasmaComponents3.ToolTip.text: text
                        PlasmaComponents3.ToolTip.visible: hovered
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: root.selectedContainer && (root.selectedContainer.Ports || "").length > 0
                    text: root.selectedContainer ? i18n("Ports: %1", root.selectedContainer.Ports || "") : ""
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    property string composeProject: root.selectedContainer
                        ? root.labelValue(root.selectedContainer.Labels, "com.docker.compose.project")
                        : ""
                    visible: composeProject.length > 0
                    text: i18n("Compose project: %1", composeProject)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                PlasmaComponents3.Label {
                    text: i18n("Recent logs")
                    font.bold: true
                }

                PlasmaComponents3.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.logsBusy
                    running: visible
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: root.logsError.length > 0
                    text: root.logsError
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.logsBusy
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.35)

                    PlasmaComponents3.ScrollView {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing

                        PlasmaComponents3.TextArea {
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            text: root.logsText.length > 0 ? root.logsText : i18n("No log output")
                            font.family: "monospace"
                            background: null
                        }
                    }
                }
            }
        }
    }
}
