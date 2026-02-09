import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"

Button {
    id: control
    
    property color accentColor: Theme.accent
    property bool primary: false
    property real cornerRadius: 6
    property string iconSource: ""
    property string iconEmoji: ""
    property bool loading: false
    property string tooltipText: ""

    TheophanyTooltip {
        visible: control.hovered && control.tooltipText !== ""
        text: control.tooltipText
    }


    contentItem: Item {
        implicitWidth: contentLayout.implicitWidth
        implicitHeight: contentLayout.implicitHeight

        RowLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: (control.iconSource !== "" || control.iconEmoji !== "") && control.text !== "" ? 8 : 0

            // Icon Container (Fixed width to help alignment)
            Item {
                visible: control.iconSource !== "" || control.iconEmoji !== ""
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: iconImage
                    anchors.fill: parent
                    visible: control.iconSource !== ""
                    source: {
                        if (control.iconSource === "") return ""
                        if (control.iconSource.startsWith("assets/")) {
                            return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + control.iconSource
                        }
                        return control.iconSource
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: control.iconEmoji !== "" && control.iconSource === ""
                    text: control.iconEmoji
                    font.pixelSize: 16
                    color: control.primary ? Theme.text : (control.hovered ? Theme.buttonText : Theme.secondaryText)
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Text {
                visible: control.text !== "" && !control.loading
                text: control.text
                font: control.font
                color: control.primary ? Theme.text : (control.hovered ? Theme.buttonText : Theme.secondaryText)
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
                
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            // Loading Indicator
            RowLayout {
                visible: control.loading
                spacing: 4
                Layout.alignment: Qt.AlignVCenter
                
                Repeater {
                    model: 3
                    Rectangle {
                        width: 4; height: 4; radius: 2
                        color: control.primary ? Theme.text : Theme.accent
                        
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: control.loading
                            NumberAnimation { from: 0.2; to: 1; duration: 400; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 1; to: 0.2; duration: 400; easing.type: Easing.InOutQuad }
                            PauseAnimation { duration: index * 200 }
                        }
                    }
                }
            }
        }
    }

    
    background: Rectangle {
        implicitWidth: 100
        implicitHeight: 35
        color: {
            if (control.primary) {
                return control.pressed ? Qt.darker(accentColor, 1.2) : (control.hovered ? Qt.lighter(accentColor, 1.1) : accentColor)
            } else {
                if (control.checked) return Qt.alpha(accentColor, 0.2)
                return control.pressed ? Qt.darker(Theme.buttonBackground, 1.2) : (control.hovered ? Qt.lighter(Theme.buttonBackground, 1.1) : Theme.buttonBackground)
            }
        }
        radius: control.cornerRadius
        border.color: control.checked ? accentColor : (control.primary ? "transparent" : (control.activeFocus ? accentColor : Theme.border))
        border.width: (control.checked || control.activeFocus) ? 2 : 1
        
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
