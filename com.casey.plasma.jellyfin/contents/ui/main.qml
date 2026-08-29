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

    property var sessions: []
    property string refreshError: ""
    property bool refreshBusy: false
    property bool refreshQueued: false
    property var lastSuccessfulRefresh: null
    property bool haveData: false

    readonly property string trimmedServerUrl: (Plasmoid.configuration.serverUrl || "").trim().replace(/\/+$/, "")
    readonly property string trimmedApiKey: (Plasmoid.configuration.apiKey || "").trim()
    readonly property bool validServerUrl: /^https?:\/\/[A-Za-z0-9_.-]+(:[0-9]{1,5})?(\/[A-Za-z0-9_.\-\/]*)?$/i.test(trimmedServerUrl)
    readonly property bool validApiKey: /^[A-Za-z0-9]{16,64}$/.test(trimmedApiKey)
    readonly property bool configured: validServerUrl && validApiKey
    readonly property bool showingStaleData: refreshError.length > 0 && haveData

    Plasmoid.icon: "applications-multimedia"
    Plasmoid.title: i18n("Jellyfin Now Playing")
    toolTipMainText: i18n("Jellyfin")
    toolTipSubText: !configured
        ? i18n("Not configured")
        : (refreshError.length > 0 ? refreshError : i18n("%1 active stream(s)", sessions.length))
    Plasmoid.backgroundHints: PlasmaCore.Types.ShadowBackground

    function commandError(data) {
        var stderr = (data["stderr"] || "").trim()
        if (data["exit code"] === undefined) {
            return stderr.length > 0 ? stderr : i18n("curl did not report a result")
        }
        var exitCode = Number(data["exit code"])
        if (exitCode === 0) return ""
        return stderr.length > 0
            ? stderr
            : i18n("Request to Jellyfin failed (exit %1)", exitCode)
    }

    function parseSessions(output) {
        var data
        try {
            data = JSON.parse(output)
        } catch (error) {
            return { ok: false, error: i18n("Could not parse Jellyfin response: %1", error) }
        }
        if (!Array.isArray(data)) {
            return { ok: false, error: i18n("Unexpected response from Jellyfin") }
        }
        var playing = []
        for (var i = 0; i < data.length; ++i) {
            if (data[i].NowPlayingItem) playing.push(data[i])
        }
        return { ok: true, sessions: playing }
    }

    function ticksToSeconds(ticks) {
        return Math.floor((ticks || 0) / 10000000)
    }

    function formatDuration(totalSeconds) {
        var seconds = Math.max(0, totalSeconds)
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        var s = seconds % 60
        var mm = (h > 0 && m < 10 ? "0" : "") + m
        var ss = (s < 10 ? "0" : "") + s
        return h > 0 ? (h + ":" + mm + ":" + ss) : (m + ":" + ss)
    }

    function sessionTitle(session) {
        var item = session.NowPlayingItem || {}
        if (item.SeriesName && item.SeriesName.length > 0) return item.SeriesName + " – " + (item.Name || "")
        return item.Name || i18n("Unknown title")
    }

    function isTranscoding(session) {
        var info = session.TranscodingInfo
        if (!info) return false
        return info.IsVideoDirect === false || info.IsAudioDirect === false
    }

    function refresh() {
        if (refreshBusy) {
            refreshQueued = true
            return
        }
        if (!configured) {
            refreshError = ""
            sessions = []
            return
        }
        refreshBusy = true
        refreshError = ""
        // The API key is delivered to curl via a stdin config file (-K -) rather than
        // as a literal -H argument, so it never appears in curl's own argv/cmdline,
        // where any other local user could read it via `ps aux` for the duration of
        // the request. validApiKey already restricts the key to [A-Za-z0-9], so no
        // escaping is needed before embedding it in the heredoc body.
        var cmd = "curl -sS -f -m 5 -K - '"
            + trimmedServerUrl + "/Sessions?ActiveWithinSeconds=960' <<'JELLYFIN_EOF'\n"
            + "header = \"X-Emby-Token: " + trimmedApiKey + "\"\n"
            + "JELLYFIN_EOF"
        sessionsCommand.connectSource(cmd)
    }

    P5Support.DataSource {
        id: sessionsCommand
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

            var result = root.parseSessions(data["stdout"] || "")
            if (!result.ok) {
                root.refreshError = result.error
                if (runQueuedRefresh) refreshDelay.restart()
                return
            }

            root.sessions = result.sessions
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
        interval: Math.max(5, Plasmoid.configuration.refreshInterval) * 1000
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
        source: "applications-multimedia"
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
            visible: root.configured && (!root.refreshBusy || root.haveData)
            color: root.refreshError.length > 0
                ? Kirigami.Theme.negativeTextColor
                : (root.sessions.length > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor)
        }

        PlasmaComponents3.Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.sessions.length
            visible: root.sessions.length > 0
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
        implicitHeight: Kirigami.Units.gridUnit * 20
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
                    source: "applications-multimedia"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    text: i18n("Jellyfin")
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                StatusChip {
                    visible: root.configured
                    label: i18n("%1 active", root.sessions.length)
                    tint: root.sessions.length > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    text: i18n("Refresh")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    enabled: !root.refreshBusy && root.configured
                    onClicked: root.refresh()
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: true
                visible: !root.configured
                text: i18n("Add your Jellyfin server URL and API key in this widget's settings (right-click → Configure…).")
                wrapMode: Text.Wrap
                opacity: 0.7
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.configured && root.refreshError.length > 0
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
                visible: root.configured && root.refreshBusy && !root.haveData
                running: visible
            }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                visible: root.configured && !root.refreshBusy && root.refreshError.length === 0 && root.sessions.length === 0
                text: i18n("No active streams")
                opacity: 0.7
            }

            PlasmaComponents3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.configured && root.sessions.length > 0 && (root.refreshError.length === 0 || root.showingStaleData)

                ListView {
                    id: sessionList
                    model: root.sessions
                    spacing: Kirigami.Units.smallSpacing
                    clip: true

                    delegate: PlasmaComponents3.ItemDelegate {
                        width: sessionList.width
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

                            Kirigami.Icon {
                                source: modelData.PlayState && modelData.PlayState.IsPaused ? "media-playback-pause" : "media-playback-start"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    PlasmaComponents3.Label {
                                        text: root.sessionTitle(modelData)
                                        textFormat: Text.PlainText
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    StatusChip {
                                        label: root.isTranscoding(modelData) ? i18n("Transcoding") : i18n("Direct play")
                                        tint: root.isTranscoding(modelData) ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
                                    }
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: (modelData.UserName || i18n("Unknown user")) + " · "
                                        + (modelData.DeviceName || modelData.Client || "") + " · "
                                        + root.formatDuration(root.ticksToSeconds(modelData.PlayState ? modelData.PlayState.PositionTicks : 0))
                                        + " / " + root.formatDuration(root.ticksToSeconds(modelData.NowPlayingItem ? modelData.NowPlayingItem.RunTimeTicks : 0))
                                    textFormat: Text.PlainText
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
