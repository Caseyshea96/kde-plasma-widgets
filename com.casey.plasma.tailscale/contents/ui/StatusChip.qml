import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami 2.20 as Kirigami

Rectangle {
    id: chipRoot
    property string iconName: ""
    property string label: ""
    property color tint: Kirigami.Theme.neutralTextColor
    radius: height / 2
    implicitHeight: chipContent.implicitHeight + Kirigami.Units.smallSpacing
    implicitWidth: chipContent.implicitWidth + Kirigami.Units.largeSpacing
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.4)

    RowLayout {
        id: chipContent
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing / 2

        Kirigami.Icon {
            source: chipRoot.iconName
            visible: chipRoot.iconName.length > 0
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents3.Label {
            text: chipRoot.label
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
    }
}
