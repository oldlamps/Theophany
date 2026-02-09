import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    title: "About Theophany"
    modal: true
    focus: true
    
    property var appInfo: null
    
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

            // Header / Logo
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                
                Image {
                    source: "qrc:/ui/assets/logo.png"
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 100
                    Layout.alignment: Qt.AlignHCenter
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: "Theophany"
                    color: Theme.text
                    font.pixelSize: 28
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "v" + (root.appInfo ? root.appInfo.getVersion() : "--") + "-alpha"
                    color: Theme.secondaryText
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // Description
            Text {
                text: "A modern, high-performance game library manager and launcher built with Rust and QML."
                color: Theme.text
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
            }

            // Links Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.topMargin: 10
                Layout.alignment: Qt.AlignHCenter
                
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 20
                    
                    TheophanyButton {
                        text: "🌐 theophany.gg"
                        onClicked: Qt.openUrlExternally("https://theophany.gg")
                    }
                    
                    TheophanyButton {
                        text: "🐙 GitHub"
                        onClicked: Qt.openUrlExternally("https://github.com/oldlamps/theophany")
                    }
                }
            }

            Rectangle {
                height: 1
                Layout.fillWidth: true
                color: Theme.border
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                Layout.preferredWidth: parent.width * 0.8
                Layout.alignment: Qt.AlignHCenter
            }

            // Author Info
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Layout.alignment: Qt.AlignHCenter
                
                Text {
                    text: "Author"
                    color: Theme.secondaryText
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Oldlamps"
                    color: Theme.accent
                    font.pixelSize: 20
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // Donation Support
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.topMargin: 10
                Layout.alignment: Qt.AlignHCenter
                
                Text {
                    text: "Help Support Development"
                    color: Theme.secondaryText
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 15
                    
                    TheophanyButton {
                        text: "❤️ Ko-fi"
                        onClicked: Qt.openUrlExternally("https://ko-fi.com/oldlamps")
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

    }
}
