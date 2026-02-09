import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"

Item {
    id: root
    width: 120
    height: 36
    
    // 0 = Grid, 1 = List
    property int currentViewMode: 0
    signal viewChanged(int mode)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 2
        
        // Grid Button
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.currentViewMode === 0 ? Theme.accent : "transparent"
            radius: 5
            
            Text {
                anchors.centerIn: parent
                text: "GRID"
                color: root.currentViewMode === 0 ? "white" : Theme.secondaryText
                font.bold: true
                font.pixelSize: 11
                font.letterSpacing: 1
            }
            
            MouseArea {
                id: gridMa
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    root.viewChanged(0)
                }
                TheophanyTooltip {
                    visible: gridMa.containsMouse
                    text: "Grid View"
                }
            }
        }

        // List Button
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.currentViewMode === 1 ? Theme.accent : "transparent"
            radius: 5

            Text {
                anchors.centerIn: parent
                text: "LIST"
                color: root.currentViewMode === 1 ? "white" : Theme.secondaryText
                font.bold: true
                font.pixelSize: 11
                font.letterSpacing: 1
            }

            MouseArea {
                id: listMa
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    root.viewChanged(1)
                }
                TheophanyTooltip {
                    visible: listMa.containsMouse
                    text: "List View"
                }
            }
        }
    }
    
    // Background container
    Rectangle {
        anchors.fill: parent
        z: -1
        color: Theme.sidebar
        radius: 6
        border.color: Theme.border
    }
}
