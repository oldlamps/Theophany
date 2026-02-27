import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"

Item {
    id: root
    width: 6
    implicitWidth: 6
    Layout.fillHeight: true
    Layout.preferredWidth: 6
    z: 100

    property bool isRightSide: true // true if resizer is on its parent's right (resizes parent), false if on the left
    property real minWidth: 50
    property real maxWidth: 1000
    property real targetWidth: 250
    property bool pressed: ma.pressed

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: parent.height
        color: Theme.accent
        opacity: ma.containsMouse || ma.pressed ? 1.0 : 0.3
        visible: true
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.accent
        opacity: ma.containsMouse || ma.pressed ? 0.2 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.SizeHorCursor
        hoverEnabled: true

        property real lastX

        onPressed: {
            lastX = mapToItem(null, mouse.x, mouse.y).x
        }

        onPositionChanged: {
            if (pressed) {
                var currentX = mapToItem(null, mouse.x, mouse.y).x
                var delta = currentX - lastX
                var newWidth = root.isRightSide ? root.targetWidth + delta : root.targetWidth - delta
                
                if (newWidth < root.minWidth) newWidth = root.minWidth
                if (newWidth > root.maxWidth) newWidth = root.maxWidth
                
                if (newWidth !== root.targetWidth) {
                    // console.log("Resizing: delta:", delta, "newWidth:", newWidth)
                    root.targetWidth = newWidth
                    lastX = currentX
                }
            }
        }
    }
}
