import QtQuick
import QtQuick.Controls
import "../style"

Switch {
    id: control
    
    property color accentColor: Theme.accent

    indicator: Rectangle {
        implicitWidth: 48
        implicitHeight: 26
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: 13
        color: control.checked ? control.accentColor : Theme.buttonBackground
        border.color: control.checked ? control.accentColor : Theme.border
        
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Rectangle {
            x: control.checked ? parent.width - width - 2 : 2
            y: 2
            width: 22
            height: 22
            radius: 11
            color: Theme.text
            border.color: Theme.secondaryText
            
            Behavior on x { NumberAnimation { duration: 150 } }
        }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }
}
