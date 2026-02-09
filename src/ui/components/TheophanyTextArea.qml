import QtQuick
import QtQuick.Controls
import "../style"

TextArea {
    id: control
    
    property color accentColor: Theme.accent
    property real cornerRadius: 6
    
    color: Theme.text
    selectionColor: accentColor
    selectedTextColor: "white"
    font.pixelSize: 14
    padding: 10
    
    placeholderTextColor: Theme.secondaryText
    
    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 100
        color: control.activeFocus ? Theme.sidebar : Theme.secondaryBackground
        radius: control.cornerRadius
        border.color: control.activeFocus ? control.accentColor : Theme.border
        border.width: control.activeFocus ? 2 : 1
        
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
