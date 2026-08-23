import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_backgroundStyle: backgroundStyle.currentIndex
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_refreshInterval: refreshInterval.value

    QQC2.ComboBox {
        id: backgroundStyle
        Kirigami.FormData.label: i18n("Background:")
        model: [
            i18n("Theme background"),
            i18n("Translucent (custom opacity)"),
            i18n("Transparent")
        ]
    }

    QQC2.SpinBox {
        id: backgroundOpacity
        Kirigami.FormData.label: i18n("Translucent opacity:")
        from: 10
        to: 95
        stepSize: 5
        editable: true
        enabled: backgroundStyle.currentIndex === 1
        textFromValue: function(value) { return i18n("%1%", value) }
        valueFromText: function(text) {
            var parsed = parseInt(text)
            return isNaN(parsed) ? value : parsed
        }
    }

    QQC2.SpinBox {
        id: refreshInterval
        Kirigami.FormData.label: i18n("Refresh interval:")
        from: 2
        to: 300
        editable: true
        textFromValue: function(value) { return i18np("%1 second", "%1 seconds", value) }
        valueFromText: function(text) {
            var parsed = parseInt(text)
            return isNaN(parsed) ? value : parsed
        }
    }
}
