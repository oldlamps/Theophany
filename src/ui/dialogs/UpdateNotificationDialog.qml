import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    title: "Update Available"
    modal: true
    focus: true
    
    property string version: ""
    property string notes: ""
    property string url: ""

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: 500
    height: 600

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
        }
    }

    header: Item { height: 0 }

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 20

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                
                Text {
                    text: "A new version of Theophany is available!"
                    color: Theme.text
                    font.pixelSize: 20
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: "Version " + root.version
                    color: Theme.accent
                    font.pixelSize: 16
                    font.bold: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.mainBackground
                radius: 8
                border.color: Theme.border
                border.width: 1
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 10
                    ScrollBar.vertical: TheophanyScrollBar {}

                    TextArea {
                        text: root.notes
                        color: Theme.text
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        readOnly: true
                        background: null
                        selectByMouse: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 15

                TheophanyButton {
                    text: "Later"
                    Layout.fillWidth: true
                    onClicked: root.close()
                }

                TheophanyButton {
                    text: "Update Now"
                    primary: true
                    Layout.fillWidth: true
                    onClicked: {
                        Qt.openUrlExternally(root.url)
                        root.close()
                    }
                }
            }
        }
    }
}
