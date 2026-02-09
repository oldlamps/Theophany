
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"

Dialog {
    id: root
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    
    // Support standard dialog interface
    property string text: ""
    property int buttons: Dialog.Ok // Default to OK
    
    // Center logic since Dialog can sometimes misbehave depending on parenting
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    
    background: Rectangle {
        implicitWidth: 450
        implicitHeight: 200
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12
    }

    header: Item {
        width: parent.width
        implicitHeight: 50
        
        Text {
            anchors.centerIn: parent
            text: root.title
            color: Theme.text
            font.bold: true
            font.pixelSize: 18
            font.letterSpacing: 0.5
        }
        
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
            anchors.bottom: parent.bottom
            opacity: 0.3
        }
    }
    
    contentItem: ColumnLayout {
        spacing: 25
        
        Text {
            text: root.text
            color: Theme.secondaryText
            font.pixelSize: 15
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 25
            Layout.topMargin: 10
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            lineHeight: 1.4
        }
        
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 15
            Layout.bottomMargin: 20

            TheophanyButton {
                text: "No"
                visible: (root.buttons & Dialog.No)
                onClicked: root.reject()
                Layout.preferredWidth: 100
                background: Rectangle {
                    color: parent.down ? Theme.accent : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.4)
                    radius: 6
                    border.color: Theme.border
                }
            }
            
            TheophanyButton {
                text: "Cancel"
                visible: (root.buttons & Dialog.Cancel)
                onClicked: root.reject()
                Layout.preferredWidth: 100
                background: Rectangle {
                    color: parent.down ? Theme.accent : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.4)
                    radius: 6
                    border.color: Theme.border
                }
            }

            TheophanyButton {
                text: "Yes"
                primary: true
                visible: (root.buttons & Dialog.Yes)
                onClicked: root.accept()
                Layout.preferredWidth: 100
            }

            TheophanyButton {
                text: "OK"
                primary: true
                visible: (root.buttons & Dialog.Ok)
                onClicked: root.accept()
                Layout.preferredWidth: 100
            }
        }
    }
    
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150 }
        }
    }
    
    exit: Transition {
        ParallelAnimation {
             NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 100; easing.type: Easing.InQuad }
             NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 100 }
        }
    }
}
