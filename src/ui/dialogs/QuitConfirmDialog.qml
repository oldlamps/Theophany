import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    width: 400
    height: 230
    title: "Confirm Exit"
    modal: true
    header: null
    
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }

    contentItem: Item {
        implicitHeight: mainCol.implicitHeight
        
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            Text {
                text: "Confirm Exit"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            Label { 
                text: "Are you sure you want to quit Theophany?"
                color: Theme.secondaryText
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true } // Spacer

            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                Layout.alignment: Qt.AlignHCenter

                TheophanyButton {
                    text: "Cancel"
                    Layout.preferredWidth: 100
                    onClicked: root.reject()
                }
                
                TheophanyButton {
                    text: "Quit"
                    primary: true
                    Layout.preferredWidth: 100
                    onClicked: {
                        root.accept()
                        Qt.quit()
                    }
                }
            }
        }
    }
}
