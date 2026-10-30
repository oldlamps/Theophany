import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Templates as T
import "../style"
import Qt5Compat.GraphicalEffects

T.Menu {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentItem.implicitHeight + topPadding + bottomPadding)

    padding: 6
    spacing: 2
    
    delegate: TheophanyMenuItem { }

    contentItem: ListView {
        implicitWidth: 200
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: Window.window ? contentHeight > Window.window.height : false
        clip: true
        currentIndex: control.currentIndex

        ScrollIndicator.vertical: ScrollIndicator {}
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 200; easing.type: Easing.OutBack }
    }

    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.InQuad }
        NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 150; easing.type: Easing.InQuad }
    }

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 40
        color: Qt.rgba(Theme.sidebar.r, Theme.sidebar.g, Theme.sidebar.b, 0.98)
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        radius: 10

        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#60000000"
            radius: 12
            samples: 17
            verticalOffset: 6
        }
    }
    function ensureFlipped() {
        // Force layout to ensure height is valid
        if (contentItem) contentItem.forceLayout()
        
        var win = control.window
        if (!win && parent) win = parent.Window.window
        if (!win) return
        
        var h = height > 0 ? height : implicitHeight
        var winHeight = win.height
        
        // Ensure we have a parent to map coordinates
        if (parent) {
            // Compute the parent's actual position in the window, completely independent of menu y
            var parentGlobal = parent.mapToItem(null, 0, 0)
            var parentY = parentGlobal.y
            var parentH = (parent.height > 0 && parent.height < winHeight * 0.6) ? parent.height : 0
            
            // Check if opening below the item exceeds the window bottom
            if (parentY + parentH + h > winHeight) {
                // Not enough room below: flip upwards above parent (or clamp to stay on screen)
                var targetGlobalY = parentY - h
                if (targetGlobalY < 10) {
                    targetGlobalY = Math.max(10, winHeight - h - 10)
                }
                var localPos = parent.mapFromItem(null, 0, targetGlobalY)
                y = localPos.y
            } else {
                // Plenty of room below: reset y if previously shifted negative
                if (y < 0) {
                    y = 0
                }
            }
        }
    }

    onAboutToShow: ensureFlipped()
    onOpened: ensureFlipped()
}
