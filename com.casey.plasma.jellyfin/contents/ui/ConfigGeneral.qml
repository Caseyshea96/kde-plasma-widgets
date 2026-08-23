import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_backgroundStyle: backgroundStyle.currentIndex
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_refreshInterval: refreshInterval.value
    property alias cfg_serverUrl: serverUrl.text
    property alias cfg_apiKey: apiKey.text

    QQC2.TextField {
        id: serverUrl
        Kirigami.FormData.label: i18n("Server URL:")
        Layout.fillWidth: true
        placeholderText: "http://localhost:8096"
    }

    QQC2.TextField {
        id: apiKey
        Kirigami.FormData.label: i18n("API key:")
        Layout.fillWidth: true
        echoMode: TextInput.Password
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Generate an API key in Jellyfin: Dashboard → API Keys → the + button.")
        wrapMode: Text.Wrap
        opacity: 0.7
        Layout.fillWidth: true
    }

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
        from: 5
        to: 300
        editable: true
        textFromValue: function(value) { return i18np("%1 second", "%1 seconds", value) }
        valueFromText: function(text) {
            var parsed = parseInt(text)
            return isNaN(parsed) ? value : parsed
        }
    }
}
