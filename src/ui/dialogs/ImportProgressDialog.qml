import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"
import "../components"

Dialog {
    id: root
    title: "Importing Games"
    modal: false
    width: 450
    height: 250
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    header: null

    property real progress: 0.0
    property string status: "Starting import..."

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 25
        spacing: 20

        Text {
            text: root.progress >= 1.0 ? "Import Complete" : "Importing Games"
            color: Theme.text
            font.pixelSize: 20 // Matched to typically used header size
            font.bold: true
        }
        
        Rectangle { 
            Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.progress < 1.0

            ProgressBar {
                id: progressBar
                Layout.fillWidth: true
                value: root.progress
                
                background: Rectangle {
                    implicitWidth: 200
                    implicitHeight: 8
                    color: Theme.hover
                    radius: 4
                }
                contentItem: Item {
                    implicitWidth: 200
                    implicitHeight: 8

                    Rectangle {
                        width: progressBar.visualPosition * parent.width
                        height: parent.height
                        radius: 4
                        color: Theme.accent
                    }
                }
            }
        }

        Text {
            text: root.status
            color: Theme.secondaryText
            font.pixelSize: 13
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }

        Item { Layout.fillHeight: true }

        TheophanyButton {
            text: root.progress >= 1.0 ? "Close" : "Run in Background"
            Layout.alignment: Qt.AlignRight
            primary: true
            onClicked: root.close()
        }
        
        Text {
            text: Math.round(root.progress * 100) + "%"
            color: Theme.accent
            font.pixelSize: 14
            font.bold: true
            Layout.alignment: Qt.AlignRight
            visible: root.progress < 1.0
        }
    }
}
