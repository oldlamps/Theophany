import QtQuick
import QtQuick.Controls
import "../style"

CheckBox {
    id: control
    
    font.pixelSize: 13
    
    indicator: Rectangle {
        implicitWidth: 18; implicitHeight: 18
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: 3
        border.color: control.checked ? Theme.accent : Theme.secondaryText
        color: "transparent"
        
        Text {
            anchors.centerIn: parent
            text: "✓"
            color: Theme.accent
            visible: control.checked
            font.bold: true
            font.pixelSize: 14
        }
    }
    
    contentItem: Text {
        text: control.text
        font: control.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + 8
    }
}
