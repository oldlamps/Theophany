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
    onAboutToShow: {
        // Force layout to ensure height is valid
        if (contentItem) contentItem.forceLayout()
        
        var win = control.window
        if (!win && parent) win = parent.Window.window
        if (!win) return
        
        var h = height > 0 ? height : implicitHeight
        var winHeight = win.height
        
        // Ensure we have a parent to map coordinates
        if (parent) {
            // Map current local 'y' to global coordinates
            var globalPos = parent.mapToItem(null, x, y)
            var globalY = globalPos.y
            
            // Check for overflow in global space
            if (globalY + h > winHeight) {
                // Determine new global Y (flipped upwards)
                var newGlobalY = globalY
                
                // If we flip up (bottom at cursor), new top is cursor - height
                // But 'y' is the top-left of the menu. 
                // The cursor position is roughly 'globalY' (since popup opens at mouse/top-left).
                
                // If we assume the menu opened AT the cursor (at globalY),
                // then we want the BOTTOM of the menu to be at globalY.
                // So newGlobalTop = globalY - h
                
                if (globalY - h > 0) {
                     newGlobalY = globalY - h
                } else {
                     // Clamp to bottom
                     newGlobalY = winHeight - h - 10
                }
                
                // Map back to local space to set 'y'
                var localPos = parent.mapFromItem(null, globalPos.x, newGlobalY)
                y = localPos.y
            }
        }
    }
}
