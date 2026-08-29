import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.kirigami 2.20 as Kirigami
import org.kde.ksvg 1.0 as Ksvg

// Fills the parent with the widget's chosen background style (theme frame,
// translucent card, or transparent) and exposes the resulting content
// margins so the caller's layout can anchor to them.
Item {
    id: cardBackground
    anchors.fill: parent
    z: -1

    readonly property real marginLeft: Plasmoid.configuration.backgroundStyle === 0
        ? Math.max(Kirigami.Units.largeSpacing, frameBackground.margins.left)
        : Kirigami.Units.largeSpacing
    readonly property real marginRight: Plasmoid.configuration.backgroundStyle === 0
        ? Math.max(Kirigami.Units.largeSpacing, frameBackground.margins.right)
        : Kirigami.Units.largeSpacing
    readonly property real marginTop: Plasmoid.configuration.backgroundStyle === 0
        ? Math.max(Kirigami.Units.largeSpacing, frameBackground.margins.top)
        : Kirigami.Units.largeSpacing
    readonly property real marginBottom: Plasmoid.configuration.backgroundStyle === 0
        ? Math.max(Kirigami.Units.largeSpacing, frameBackground.margins.bottom)
        : Kirigami.Units.largeSpacing

    Ksvg.FrameSvgItem {
        id: frameBackground
        anchors.fill: parent
        visible: Plasmoid.configuration.backgroundStyle === 0
        imagePath: "widgets/background"
    }

    Kirigami.ShadowedRectangle {
        anchors.fill: parent
        visible: Plasmoid.configuration.backgroundStyle === 1
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b,
            Math.max(10, Math.min(95, Plasmoid.configuration.backgroundOpacity)) / 100)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        shadow.size: Kirigami.Units.gridUnit
        shadow.color: Qt.rgba(0, 0, 0, 0.25)
        shadow.yOffset: 2
    }
}
