import QtQuick
import "../style"
import Qt5Compat.GraphicalEffects

Item {
    id: root
    width: 200
    height: 40
    property bool smallMode: false

    Text {
        id: logoText
        anchors.centerIn: parent
        text: "THEOPHANY"
        font.pixelSize: 22
        font.bold: true
        font.letterSpacing: 4
        
        // We use a layer to apply the gradient effect to the text
        layer.enabled: true
        layer.effect: Item {
            width: logoText.width
            height: logoText.height
            
            LinearGradient {
                anchors.fill: parent
                source: logoText
                start: Qt.point(0, 0)
                end: Qt.point(logoText.width, 0)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.accent }
                    GradientStop { position: 0.5; color: Qt.lighter(Theme.accent, 1.4) }
                    GradientStop { position: 1.0; color: Theme.accent }
                }
            }
            
            Glow {
                anchors.fill: parent
                source: parent.children[0] // Target the gradient
                color: Theme.accent
                radius: 6
                samples: 17
                spread: 0.2
            }
        }
    }
}
