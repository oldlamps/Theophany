import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../style"

Popup {
    id: root

    property var gameModel: null
    property string assetDownloadStatus: ""
    property bool isStoreInstalling: false
    property string storeInstallAppId: ""
    property real storeInstallProgress: 0.0
    property bool hasBackgroundActivity: false
    property string backgroundActivityId: ""
    property string backgroundActivityStatus: ""
    property real backgroundActivityProgress: 0.0

    signal openBulkScrapeRequested()
    signal openStoreRequested()
    signal openImportProgressRequested()

    readonly property bool isScraping: gameModel ? gameModel.bulkScraping : false
    readonly property bool isPaused: gameModel ? gameModel.bulkPaused : false
    readonly property real scrapeProgress: gameModel ? gameModel.bulkProgress : 0.0
    readonly property string scrapeStatus: gameModel ? gameModel.bulkStatus : ""
    readonly property bool isDbLoading: gameModel ? gameModel.loading : false

    readonly property int activeCount: (isScraping ? 1 : 0) +
                                       (isStoreInstalling ? 1 : 0) +
                                       (hasBackgroundActivity ? 1 : 0) +
                                       (assetDownloadStatus !== "" ? 1 : 0) +
                                       (isDbLoading ? 1 : 0)
    readonly property bool hasActiveTasks: activeCount > 0

    // Dynamic vertical sizing:
    // When idle, keep a comfortable 190px centered area.
    // When active tasks are present, smoothly expand to accommodate all active boxes
    // up to maxPopupHeight (capping at 520px or window space above status bar),
    // and seamlessly enable smooth scrolling if tasks exceed the height limit.
    readonly property real maxPopupHeight: Math.min(520, (root.Window && root.Window.window ? root.Window.window.height - 90 : 500))
    readonly property real maxBodyHeight: maxPopupHeight - 43
    readonly property real idleBodyHeight: 190
    readonly property real activeContentHeight: cardsColumn.implicitHeight + 24
    readonly property real activeBodyHeight: Math.min(maxBodyHeight, Math.max(120, activeContentHeight))
    readonly property real currentBodyHeight: hasActiveTasks ? activeBodyHeight : idleBodyHeight

    width: 380
    height: 43 + currentBodyHeight
    x: parent ? parent.width - width : 0
    y: -height - 8
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Behavior on height {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { property: "y"; from: -root.height + 8; to: -root.height - 8; duration: 180; easing.type: Easing.OutQuad }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 140; easing.type: Easing.InQuad }
        NumberAnimation { property: "y"; from: -root.height - 8; to: -root.height + 8; duration: 140; easing.type: Easing.InQuad }
    }

    background: Rectangle {
        color: Theme.sidebar
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        radius: 10
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#80000000"
            radius: 16
            samples: 25
            verticalOffset: -4
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            color: Qt.rgba(1, 1, 1, 0.03)
            radius: 10

            // Keep bottom corners square so divider sits cleanly
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 10
                color: Qt.rgba(1, 1, 1, 0.03)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "⚡"
                    font.pixelSize: 13
                    color: Theme.accent
                }

                Text {
                    text: "Activity Center"
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.text
                }

                // Active Badge
                Rectangle {
                    visible: root.hasActiveTasks
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: activeBadgeText.implicitWidth + 12
                    radius: 9
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        id: activeBadgeText
                        anchors.centerIn: parent
                        text: root.activeCount + " active"
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.accent
                    }
                }

                // Idle Badge
                Rectangle {
                    visible: !root.hasActiveTasks
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: idleBadgeText.implicitWidth + 12
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1

                    Text {
                        id: idleBadgeText
                        anchors.centerIn: parent
                        text: "Idle"
                        font.pixelSize: 10
                        color: Theme.secondaryText
                    }
                }

                Item { Layout.fillWidth: true }

                // Close Button
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: closeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        color: closeMa.containsMouse ? Theme.text : Theme.secondaryText
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        // Header Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        // Body Area
        Item {
            id: bodyArea
            Layout.fillWidth: true
            Layout.preferredHeight: root.currentBodyHeight
            Layout.fillHeight: true
            clip: true

            // 1. Idle / All Tasks Completed State (horizontally and vertically centered)
            Item {
                id: idleContainer
                anchors.fill: parent
                visible: !root.hasActiveTasks

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 8

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 42
                        height: 42
                        radius: 21
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: 18
                            font.bold: true
                            color: Theme.accent
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "All tasks completed"
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: "No active background scraping, downloads, or installs."
                        font.pixelSize: 11
                        color: Theme.secondaryText
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: scrapeLibBtnText.implicitWidth + 20
                        radius: 4
                        color: scrapeLibMa.containsMouse ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            id: scrapeLibBtnText
                            anchors.centerIn: parent
                            text: "Scrape Library"
                            font.pixelSize: 11
                            font.bold: true
                            color: scrapeLibMa.containsMouse ? "white" : Theme.accent
                        }

                        MouseArea {
                            id: scrapeLibMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                root.openBulkScrapeRequested()
                            }
                        }
                    }
                }
            }

            // 2. Active Tasks Scrollable Area (dynamically sized and scrollable)
            ScrollView {
                id: taskScrollView
                anchors.fill: parent
                visible: root.hasActiveTasks
                clip: true

                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: TheophanyScrollBar {
                    persistentVisibility: taskScrollView.contentHeight > taskScrollView.height
                }

                Item {
                    id: scrollContent
                    width: taskScrollView.width
                    implicitHeight: cardsColumn.implicitHeight + 24

                    ColumnLayout {
                        id: cardsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: (taskScrollView.contentHeight > taskScrollView.height ? 16 : 12)
                        anchors.topMargin: 12
                        spacing: 10

                        // 1. Scraping Task Card
                        Rectangle {
                            visible: root.isScraping
                            Layout.fillWidth: true
                            implicitHeight: scrapeCardLayout.implicitHeight + 20
                            color: Theme.secondaryBackground
                            border.color: root.isPaused ? "#ffaa00" : Theme.accent
                            border.width: 1
                            radius: 8

                            ColumnLayout {
                                id: scrapeCardLayout
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                // Title Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "✨"
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: "Metadata & Media Scraping"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Theme.text
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        Layout.preferredHeight: 16
                                        Layout.preferredWidth: scrapeStatusTag.implicitWidth + 10
                                        radius: 4
                                        color: root.isPaused ? Qt.rgba(1, 0.6, 0, 0.18) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)

                                        Text {
                                            id: scrapeStatusTag
                                            anchors.centerIn: parent
                                            text: root.isPaused ? "PAUSED" : "RUNNING"
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: root.isPaused ? "#ffaa00" : Theme.accent
                                        }
                                    }
                                }

                                // Status message
                                Text {
                                    text: root.scrapeStatus !== "" ? root.scrapeStatus : "Scraping in progress..."
                                    font.pixelSize: 11
                                    color: Theme.secondaryText
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                // Progress Bar & Percentage
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    ProgressBar {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                        value: Math.max(0.0, Math.min(1.0, root.scrapeProgress))

                                        background: Rectangle {
                                            implicitHeight: 6
                                            color: Qt.rgba(1, 1, 1, 0.1)
                                            radius: 3
                                        }
                                        contentItem: Item {
                                            implicitHeight: 6
                                            Rectangle {
                                                width: parent.visualPosition * parent.width
                                                height: parent.height
                                                radius: 3
                                                color: root.isPaused ? "#ffaa00" : Theme.accent
                                            }
                                        }
                                    }

                                    Text {
                                        text: Math.round(root.scrapeProgress * 100) + "%"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Theme.text
                                    }
                                }

                                // Controls Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // Pause / Resume Button
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: pauseBtnText.implicitWidth + 16
                                        radius: 4
                                        color: pauseBtnMa.containsMouse ? Theme.hover : Qt.rgba(1, 1, 1, 0.08)
                                        border.color: Theme.border
                                        border.width: 1

                                        Text {
                                            id: pauseBtnText
                                            anchors.centerIn: parent
                                            text: root.isPaused ? "▶ Resume" : "⏸ Pause"
                                            font.pixelSize: 11
                                            color: Theme.text
                                        }

                                        MouseArea {
                                            id: pauseBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.gameModel) {
                                                    if (root.isPaused) root.gameModel.resumeBulkScrape()
                                                    else root.gameModel.pauseBulkScrape()
                                                }
                                            }
                                        }
                                    }

                                    // Stop Button
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: stopBtnText.implicitWidth + 16
                                        radius: 4
                                        color: stopBtnMa.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.2) : Qt.rgba(1, 1, 1, 0.08)
                                        border.color: Theme.border
                                        border.width: 1

                                        Text {
                                            id: stopBtnText
                                            anchors.centerIn: parent
                                            text: "⏹ Cancel"
                                            font.pixelSize: 11
                                            color: stopBtnMa.containsMouse ? "#ff5555" : Theme.secondaryText
                                        }

                                        MouseArea {
                                            id: stopBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.gameModel) root.gameModel.stopBulkScrape()
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Open Full Dialog Button
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: fullBtnText.implicitWidth + 14
                                        radius: 4
                                        color: fullBtnMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                                        border.color: Theme.accent
                                        border.width: 1

                                        Text {
                                            id: fullBtnText
                                            anchors.centerIn: parent
                                            text: "⤢ Full View"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Theme.accent
                                        }

                                        MouseArea {
                                            id: fullBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.close()
                                                root.openBulkScrapeRequested()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Asset Download Card
                        Rectangle {
                            visible: root.assetDownloadStatus !== ""
                            Layout.fillWidth: true
                            implicitHeight: assetCardLayout.implicitHeight + 20
                            color: Theme.secondaryBackground
                            border.color: Theme.border
                            border.width: 1
                            radius: 8

                            ColumnLayout {
                                id: assetCardLayout
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text { text: "🖼️"; font.pixelSize: 12 }
                                    Text {
                                        text: "Asset Download"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Theme.text
                                        Layout.fillWidth: true
                                    }

                                    // Pulsing dot
                                    Rectangle {
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: Theme.accent
                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 1.0; to: 0.2; duration: 600 }
                                            NumberAnimation { from: 0.2; to: 1.0; duration: 600 }
                                        }
                                    }
                                }

                                Text {
                                    text: root.assetDownloadStatus
                                    font.pixelSize: 11
                                    color: Theme.secondaryText
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // 3. Store Installation Card
                        Rectangle {
                            visible: root.isStoreInstalling
                            Layout.fillWidth: true
                            implicitHeight: storeCardLayout.implicitHeight + 20
                            color: Theme.secondaryBackground
                            border.color: Theme.accent
                            border.width: 1
                            radius: 8

                            ColumnLayout {
                                id: storeCardLayout
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text { text: "📦"; font.pixelSize: 12 }
                                    Text {
                                        text: "Store Installation: " + root.storeInstallAppId
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: Math.round(root.storeInstallProgress * 100) + "%"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Theme.accent
                                    }
                                }

                                ProgressBar {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 5
                                    value: Math.max(0.0, Math.min(1.0, root.storeInstallProgress))
                                    background: Rectangle { implicitHeight: 5; color: Qt.rgba(1, 1, 1, 0.1); radius: 2.5 }
                                    contentItem: Item {
                                        implicitHeight: 5
                                        Rectangle {
                                            width: parent.visualPosition * parent.width
                                            height: parent.height
                                            radius: 2.5
                                            color: Theme.accent
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredHeight: 22
                                        Layout.preferredWidth: storeBtnText.implicitWidth + 14
                                        radius: 4
                                        color: storeBtnMa.containsMouse ? Theme.hover : Qt.rgba(1, 1, 1, 0.08)
                                        border.color: Theme.border
                                        border.width: 1

                                        Text {
                                            id: storeBtnText
                                            anchors.centerIn: parent
                                            text: "Open Store"
                                            font.pixelSize: 10
                                            color: Theme.text
                                        }
                                        MouseArea {
                                            id: storeBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.close()
                                                root.openStoreRequested()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 4. Background Activity Card (Import, Deletion, Artwork, etc.)
                        Rectangle {
                            visible: root.hasBackgroundActivity
                            Layout.fillWidth: true
                            implicitHeight: bgCardLayout.implicitHeight + 20
                            color: Theme.secondaryBackground
                            border.color: Theme.border
                            border.width: 1
                            radius: 8

                            ColumnLayout {
                                id: bgCardLayout
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text { text: "⚙️"; font.pixelSize: 12 }
                                    Text {
                                        text: root.backgroundActivityId !== "" ? root.backgroundActivityId : "Background Task"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Theme.text
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: root.backgroundActivityProgress > 0
                                        text: Math.round(root.backgroundActivityProgress * 100) + "%"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Theme.accent
                                    }
                                }

                                Text {
                                    text: root.backgroundActivityStatus !== "" ? root.backgroundActivityStatus : "Processing in background..."
                                    font.pixelSize: 11
                                    color: Theme.secondaryText
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }

                                ProgressBar {
                                    visible: root.backgroundActivityProgress > 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 5
                                    value: Math.max(0.0, Math.min(1.0, root.backgroundActivityProgress))
                                    background: Rectangle { implicitHeight: 5; color: Qt.rgba(1, 1, 1, 0.1); radius: 2.5 }
                                    contentItem: Item {
                                        implicitHeight: 5
                                        Rectangle {
                                            width: parent.visualPosition * parent.width
                                            height: parent.height
                                            radius: 2.5
                                            color: Theme.accent
                                        }
                                    }
                                }

                                RowLayout {
                                    visible: root.backgroundActivityId === "Import"
                                    Layout.fillWidth: true
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredHeight: 22
                                        Layout.preferredWidth: impBtnText.implicitWidth + 14
                                        radius: 4
                                        color: impBtnMa.containsMouse ? Theme.hover : Qt.rgba(1, 1, 1, 0.08)
                                        border.color: Theme.border
                                        border.width: 1

                                        Text {
                                            id: impBtnText
                                            anchors.centerIn: parent
                                            text: "View Import"
                                            font.pixelSize: 10
                                            color: Theme.text
                                        }
                                        MouseArea {
                                            id: impBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.close()
                                                root.openImportProgressRequested()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 5. Database Query Loading Card
                        Rectangle {
                            visible: root.isDbLoading
                            Layout.fillWidth: true
                            implicitHeight: 46
                            color: Theme.secondaryBackground
                            border.color: Theme.border
                            border.width: 1
                            radius: 8

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: "transparent"
                                    border.color: Theme.accent
                                    border.width: 2
                                    SequentialAnimation on rotation {
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0; to: 360; duration: 900 }
                                    }
                                }

                                Text {
                                    text: "Refreshing game library database..."
                                    font.pixelSize: 11
                                    color: Theme.secondaryText
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
