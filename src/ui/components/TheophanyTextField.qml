import QtQuick
import QtQuick.Controls
import "../style"

TextField {
    id: control
    
    property color accentColor: Theme.accent
    property real cornerRadius: 6
    
    color: Theme.text
    selectionColor: accentColor
    selectedTextColor: Theme.text
    font.pixelSize: 14
    padding: 10
    leftPadding: 12
    rightPadding: 12
    
    placeholderTextColor: Theme.secondaryText
    
    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 35
        color: control.activeFocus ? Qt.darker(Theme.sidebar, 1.2) : Theme.sidebar
        radius: control.cornerRadius
        border.color: control.activeFocus ? control.accentColor : Theme.border
        border.width: control.activeFocus ? 2 : 1
        
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
