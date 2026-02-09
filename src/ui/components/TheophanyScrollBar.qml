import QtQuick
import QtQuick.Controls
import "../style"

ScrollBar {
    id: root
    orientation: Qt.Vertical

    property bool persistentVisibility: false

    contentItem: Rectangle {
        implicitWidth: root.orientation === Qt.Vertical ? 12 : 100
        implicitHeight: root.orientation === Qt.Vertical ? 100 : 12
        radius: (root.orientation === Qt.Vertical ? width : height) / 2
        color: root.pressed ? Theme.accent : Theme.secondaryText
        opacity: (root.persistentVisibility && root.size < 1.0) ? 0.95 : ((root.active && root.size < 1.0) ? 0.95 : 0)
        
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    background: Rectangle {
        implicitWidth: root.orientation === Qt.Vertical ? 12 : 20
        implicitHeight: root.orientation === Qt.Vertical ? 20 : 12
        color: Theme.secondaryBackground
        radius: (root.orientation === Qt.Vertical ? width : height) / 2
        opacity: (root.persistentVisibility && root.size < 1.0) ? 0.5 : ((root.active && root.size < 1.0) ? 0.5 : 0)
        
        anchors.fill: parent
        
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
}
