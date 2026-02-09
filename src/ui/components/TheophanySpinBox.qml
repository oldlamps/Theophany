import QtQuick
import QtQuick.Controls
import "../style"

SpinBox {
    id: control
    
    // Allow overriding generally, but default to Theme
    property color accentColor: Theme.accent
    property real cornerRadius: 6

    editable: true

    contentItem: TextInput {
        z: 2
        text: control.textFromValue(control.value, control.locale)

        font: control.font
        color: Theme.text
        selectionColor: accentColor
        selectedTextColor: "white"
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter

        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
    }

    up.indicator: Rectangle {
        x: control.width - width
        height: parent.height
        width: 30
        color: control.up.pressed ? Theme.buttonBackground : (control.up.hovered ? Theme.hover : Theme.buttonBackground)
        border.color: Theme.border
        radius: control.cornerRadius
        
        Text {
            text: "+"
            font.pixelSize: 16
            color: Theme.text
            anchors.centerIn: parent
        }
    }

    down.indicator: Rectangle {
        x: 0
        height: parent.height
        width: 30
        color: control.down.pressed ? Theme.buttonBackground : (control.down.hovered ? Theme.hover : Theme.buttonBackground)
        border.color: Theme.border
        radius: control.cornerRadius

        Text {
            text: "-"
            font.pixelSize: 16
            color: Theme.text
            anchors.centerIn: parent
        }
    }

    background: Rectangle {
        implicitWidth: 140
        implicitHeight: 35
        color: Theme.sidebar // Darker input background
        border.color: control.activeFocus ? accentColor : Theme.border
        border.width: control.activeFocus ? 2 : 1
        radius: control.cornerRadius
    }
}
