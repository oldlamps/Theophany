import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import "../style"

Item {
    id: root
    property bool running: true
    property string text: ""
    property real size: 64

    implicitWidth: size
    implicitHeight: size

    Column {
        anchors.centerIn: parent
        spacing: 15

        BusyIndicator {
            id: indicator
            anchors.horizontalCenter: parent.horizontalCenter
            running: root.running
            implicitWidth: root.size
            implicitHeight: root.size
            
            contentItem: Item {
                id: contentItem
                width: root.size
                height: root.size
                
                ConicalGradient {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.7; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3) }
                        GradientStop { position: 1.0; color: Theme.accent }
                    }
                    
                    source: Rectangle {
                        width: root.size
                        height: root.size
                        radius: root.size / 2
                        color: "transparent"
                        border.width: root.size / 8
                        border.color: "white"
                    }
                }
                
                RotationAnimator {
                    target: contentItem
                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: root.running
                }
            }
        }

        Text {
            visible: root.text !== ""
            text: root.text
            color: Theme.text
            font.pixelSize: 14
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.8
        }
    }
}
