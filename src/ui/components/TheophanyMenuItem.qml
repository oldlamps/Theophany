import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import QtQuick.Layouts
import "../style"
import Qt5Compat.GraphicalEffects

T.MenuItem {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    // Properly handle visibility by collapsing height
    height: visible ? implicitHeight : 0
    enabled: visible

    padding: 10
    spacing: 12

    property string iconSource: ""
    readonly property string effectiveIcon: {
        if (iconSource !== "") return iconSource
        if (control.subMenu && control.subMenu.iconSource !== undefined) return control.subMenu.iconSource
        return ""
    }

    contentItem: Item {
        implicitWidth: 200
        implicitHeight: 40

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 12
            
            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                visible: control.effectiveIcon !== ""

                readonly property bool isPath: control.effectiveIcon.indexOf("/") !== -1 || 
                                               control.effectiveIcon.indexOf(".") !== -1 ||
                                               control.effectiveIcon.startsWith("qrc:")

                Text {
                    anchors.centerIn: parent
                    text: control.effectiveIcon
                    color: control.highlighted ? Theme.text : Theme.secondaryText
                    font.pixelSize: 16
                    visible: !parent.isPath
                }
                Image {
                    anchors.fill: parent
                    source: parent.isPath ? control.effectiveIcon : ""
                    fillMode: Image.PreserveAspectFit
                    visible: parent.isPath
                    smooth: true
                }
            }

            Text {
                id: labelText
                text: {
                    if (control.text !== "") return control.text
                    if (control.subMenu && control.subMenu.title) return control.subMenu.title
                    return ""
                }
                font.pixelSize: 14
                color: control.highlighted ? Theme.text : Theme.secondaryText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
            }

            // Submenu Arrow
            Text {
                text: "›"
                font.pixelSize: 18
                color: control.highlighted ? Theme.text : Theme.secondaryText
                visible: control.subMenu !== null
            }

            Text {
                text: (control.shortcut && control.shortcut.nativeText) ? control.shortcut.nativeText : ""
                font.pixelSize: 12
                color: Theme.secondaryText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                visible: text !== "" && control.subMenu === null
            }
        }
    }

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 40
        opacity: enabled ? 1 : 0.3
        color: "transparent"
        radius: 6
        
        Rectangle {
            anchors.fill: parent
            visible: control.highlighted
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.05) }
            }
        }
        
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height * 0.5
            width: 3
            color: Theme.accent
            visible: control.highlighted
            radius: 2
            
            layer.enabled: true
            layer.effect: Glow {
                color: Theme.accent
                radius: 4
                samples: 9
            }
        }

        TheophanyTooltip {
            visible: control.highlighted && labelText.truncated
            text: labelText.text
        }
    }
}
