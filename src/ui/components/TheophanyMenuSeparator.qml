import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import "../style"

T.MenuSeparator {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    // Properly handle visibility by collapsing height
    height: visible ? implicitHeight : 0

    padding: 6

    contentItem: Rectangle {
        implicitWidth: 180
        implicitHeight: 1
        color: Qt.rgba(1, 1, 1, 0.1)
    }
}
