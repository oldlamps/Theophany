import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import "../style"

ComboBox {
    id: control
    
    property color accentColor: Theme.accent
    property real cornerRadius: 6

    delegate: ItemDelegate {
        width: control.width
        contentItem: Text {
            text: {
                if (control.textRole) {
                    var val = model[control.textRole]
                    if (val === undefined && model.modelData) val = model.modelData[control.textRole]
                    return val !== undefined ? val : ""
                }
                return modelData !== undefined ? modelData : ""
            }
            color: highlighted ? Theme.text : Theme.secondaryText
            font: control.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: highlighted ? accentColor : "transparent"
        }
        highlighted: control.highlightedIndex === index
    }

    indicator: Canvas {
        id: canvas
        x: control.width - width - control.rightPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: 12
        height: 8
        contextType: "2d"

        onPaint: {
            var ctx = getContext("2d");
            if (!ctx) return;
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fillStyle = control.pressed ? accentColor : Theme.secondaryText;
            ctx.fill();
        }

        Connections {
            target: control
            function onPressedChanged() { canvas.requestPaint(); }
        }
    }

    contentItem: Text {
        leftPadding: 12
        rightPadding: control.indicator.width + control.spacing

        text: control.displayText
        font: control.font
        color: control.pressed ? accentColor : Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        implicitWidth: 120
        implicitHeight: 35
        color: control.pressed ? Qt.darker(Theme.secondaryBackground, 1.2) : (control.hovered ? Qt.lighter(Theme.secondaryBackground, 1.1) : Theme.secondaryBackground)
        border.color: control.activeFocus ? accentColor : (control.visualFocus ? accentColor : Theme.border)
        border.width: (control.activeFocus || control.visualFocus) ? 2 : 1
        radius: control.cornerRadius
    }

    popup: Popup {
        y: control.height + 2
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 2, 300)
        padding: 1

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex

            ScrollBar.vertical: TheophanyScrollBar { }
        }

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.border
            radius: control.cornerRadius
            
            // Drop shadow effect
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 8
                samples: 17
                color: "#aa000000"
            }
        }
    }
}
