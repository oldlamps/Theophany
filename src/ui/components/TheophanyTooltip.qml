import QtQuick
import QtQuick.Controls.Basic
import Qt5Compat.GraphicalEffects
import "../style"

ToolTip {
    id: control
    delay: 600
    padding: 8
    
    contentItem: Text {
        id: labelText
        text: control.text
        font.pixelSize: 12
        color: Theme.text
    }

    background: Rectangle {
        id: bgRect
        color: Theme.secondaryBackground
        radius: 6
        border.color: Theme.accent
        border.width: 1
        
        // Proper premium glow effect
        layer.enabled: true
        layer.effect: Glow {
            color: Qt.alpha(Theme.accent, 0.4)
            radius: 8
            samples: 17
            transparentBorder: true
        }
    }
}
