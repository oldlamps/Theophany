import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtMultimedia
import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    width: Overlay.overlay ? Overlay.overlay.width * 0.8 : 1000
    height: Overlay.overlay ? Overlay.overlay.height * 0.8 : 700
    modal: true
    // title removed to prevent default title bar
    
    // Properties
    property string gameId: ""
    property string gameTitle: ""
    property string gamePlatform: ""
    property string platformFolder: ""
    
    // Internal
    property var searchResults: []
    property var localVideos: [] // New locally managed list
    property bool searching: false
    property bool downloading: false
    property bool streaming: false
    property string sortMode: "Relevance" // Relevance, Shortest, Longest
    property string currentPlayingTitle: ""
    property string currentPlayingUploader: ""
    
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    
    // Access global video proxy
    VideoProxy {
        id: videoProxyInternal
        
        onVideoSearchFinished: (json) => {

            root.searching = false
            try {
                root.searchResults = JSON.parse(json)
                sortSearchResults()
            } catch (e) {

                root.searchResults = []
            }
        }
        
        onVideoDownloadFinished: (path) => {
            root.downloading = false
            root.downloadCompleted(path)
            refreshLibrary() // Auto refresh library
        }

        onVideoListReady: (json) => {
            try {
                 root.localVideos = JSON.parse(json)
            } catch (e) {
                 root.localVideos = []
            }
        }

        onVideoDeleted: (path) => {
            refreshLibrary()
        }

        onStreamUrlReady: (url) => {
            root.streaming = false
            streamPlayer.stop()
            streamPlayer.source = ""
            streamPlayer.source = url
            streamPlayer.play()
            videoContainer.forceActiveFocus()
        }
        
        onErrorOccurred: (msg) => {

            root.searching = false
            root.downloading = false
            root.streaming = false
        }
    }
    
    Timer {
        id: dlgPollTimer
        interval: 100
        repeat: true
        running: root.visible
        onTriggered: videoProxyInternal.poll()
    }
    
    // Track active tab manually since we removed TabBar
    property int currentTab: 0

    signal downloadCompleted(string path)

    background: Rectangle {
        color: Theme.secondaryBackground
        radius: 12
        border.color: Theme.border
        border.width: 1
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }
    
    onClosed: {
        streamPlayer.stop()
    }

    contentItem: Rectangle {
        id: contentRoot
        color: "transparent"
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            
            // Custom Modern Header (Integrated)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 100 // Increased from 85
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 15
                    anchors.bottomMargin: 15 // Added bottom padding
                    spacing: 12 // Increased spacing

                    // Row 1: Video Explorer & Close (x)
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Label {
                            text: "VIDEO EXPLORER"
                            color: Theme.accent
                            font.bold: true
                            font.pixelSize: 11
                            font.letterSpacing: 2
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 4
                            color: closeHover.hovered ? Qt.lighter(Theme.buttonBackground, 1.2) : Theme.buttonBackground
                            border.color: closeHover.hovered ? Theme.accent : Theme.border
                            border.width: 1
                            
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                            
                            Label {
                                anchors.centerIn: parent
                                text: "✕\ufe0e"
                                color: closeHover.hovered ? Theme.text : Theme.secondaryText
                                font.pixelSize: 14
                            }
                            
                            HoverHandler { id: closeHover }
                            TapHandler { onTapped: root.close() }
                        }
                    }

                    // Row 2: Game Title & Platform
                    Label {
                        text: root.gameTitle + (root.gamePlatform !== "--" ? " (" + root.gamePlatform + ")" : "")
                        color: Theme.text
                        font.bold: true
                        font.pixelSize: 22
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
            }


            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // LEFT PANE: Search & Results / Library (approx 33%)
                Rectangle {
                    Layout.preferredWidth: root.width * 0.33
                    Layout.fillHeight: true
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Custom Segmented Control Tabs
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: 15
                            Layout.rightMargin: 15
                            Layout.topMargin: 10
                            Layout.preferredHeight: 36
                            color: Theme.background
                            radius: 8
                            border.color: Theme.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 0

                                Repeater {
                                    model: ["Search", "Library"]
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: root.currentTab === index ? Theme.secondaryBackground : "transparent"
                                        radius: 6
                                        border.color: root.currentTab === index ? Theme.border : "transparent"
                                        border.width: root.currentTab === index ? 1 : 0
                                        
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Label {
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.bold: root.currentTab === index
                                            color: root.currentTab === index ? Theme.text : Theme.secondaryText
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.currentTab = index
                                                if (index === 1) refreshLibrary()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StackLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            currentIndex: root.currentTab
                            
                            // TAB 1: SEARCH
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 15
                                    spacing: 15

                                    // Search Bar
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        
                                        TheophanyTextField {
                                            id: searchField
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            placeholderText: "Search clips..."
                                            onAccepted: startSearch()
                                        }
                                        
                                        TheophanyButton {
                                            text: root.searching ? "..." : "Search"
                                            enabled: !root.searching
                                            Layout.alignment: Qt.AlignVCenter
                                            onClicked: startSearch()
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            text: "Search Results"
                                            color: Theme.secondaryText
                                            font.pixelSize: 12
                                            font.bold: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        Item { Layout.fillWidth: true }
                                        TheophanyButton {
                                            text: "Sort: " + root.sortMode
                                            Layout.preferredHeight: 28
                                            Layout.alignment: Qt.AlignVCenter
                                            onClicked: {
                                                if (root.sortMode === "Relevance") root.sortMode = "Longest"
                                                else if (root.sortMode === "Longest") root.sortMode = "Shortest"
                                                else root.sortMode = "Relevance"
                                                sortSearchResults()
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        ListView {
                                            id: resultList
                                            anchors.fill: parent
                                            clip: true
                                            model: root.searchResults
                                            spacing: 8
                                            ScrollBar.vertical: TheophanyScrollBar {}
                                            delegate: Rectangle {
                                                    id: resultDelegate
                                                    width: ListView.view.width
                                                    height: 85
                                                    color: rowHover.hovered ? Qt.lighter(Theme.secondaryBackground, 1.1) : Theme.secondaryBackground
                                                    border.color: ListView.isCurrentItem ? Theme.accent : (rowHover.hovered ? Theme.border : "transparent")
                                                    border.width: ListView.isCurrentItem ? 2 : 1
                                                    radius: 8

                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    HoverHandler {
                                                        id: rowHover
                                                    }

                                                    TapHandler {
                                                        onTapped: resultList.currentIndex = index
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 8
                                                        spacing: 12

                                                        Rectangle {
                                                            Layout.preferredWidth: 80
                                                            Layout.fillHeight: true
                                                            color: "black"
                                                            radius: 4
                                                            clip: true

                                                            Image {
                                                                anchors.fill: parent
                                                                source: root.getBetterThumbnail(modelData)
                                                                fillMode: Image.PreserveAspectCrop
                                                                opacity: rowHover.hovered ? 0.9 : 0.7
                                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                            }

                                                            TapHandler {
                                                                onTapped: {
                                                                    resultList.currentIndex = index
                                                                    root.streaming = true
                                                                    root.currentPlayingTitle = modelData.title
                                                                    root.currentPlayingUploader = modelData.uploader || "Unknown"
                                                                    videoProxyInternal.getStreamUrl(modelData.url)
                                                                }
                                                            }

                                                            Label {
                                                                anchors.centerIn: parent
                                                                text: "▶\ufe0e"
                                                                color: "white"
                                                                font.pixelSize: 20
                                                                opacity: rowHover.hovered ? 1.0 : 0.6
                                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            Label {
                                                                text: modelData.title
                                                                color: Theme.text
                                                                font.bold: true
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }

                                                            Label {
                                                                text: (modelData.uploader || "Unknown") + " • " + formatDuration(modelData.duration)
                                                                color: Theme.secondaryText
                                                                font.pixelSize: 10
                                                            }

                                                            RowLayout {
                                                                spacing: 8
                                                                TheophanyButton {
                                                                    text: "Play"
                                                                    Layout.preferredHeight: 28
                                                                    Layout.alignment: Qt.AlignVCenter
                                                                    onClicked: {
                                                                        resultList.currentIndex = index
                                                                        root.streaming = true
                                                                        root.currentPlayingTitle = modelData.title
                                                                        root.currentPlayingUploader = modelData.uploader || "Unknown"
                                                                        videoProxyInternal.getStreamUrl(modelData.url)
                                                                    }
                                                                }
                                                                TheophanyButton {
                                                                    text: "Get"
                                                                    Layout.preferredHeight: 28
                                                                    Layout.alignment: Qt.AlignVCenter
                                                                    primary: true
                                                                    onClicked: {
                                                                        if (!root.downloading) {
                                                                            root.downloading = true
                                                                            videoProxyInternal.downloadVideo(modelData.url, root.gameId, root.platformFolder, modelData.title)
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }


                                                }
                                        }

                                        BusyIndicator {
                                            visible: root.searching
                                            anchors.centerIn: parent
                                        }

                                        Label {
                                            visible: root.searchResults.length === 0 && !root.searching
                                            text: "No videos found."
                                            color: Theme.secondaryText
                                            anchors.centerIn: parent
                                        }
                                    }
                                }
                            }
                            
                            // TAB 2: LIBRARY
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 15
                                    spacing: 15
                                    
                                    RowLayout {
                                        TheophanyButton {
                                            text: "Refresh"
                                            Layout.fillWidth: true
                                            onClicked: refreshLibrary()
                                        }
                                    }

                                    ListView {
                                        id: libraryList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        model: root.localVideos
                                        spacing: 8
                                        ScrollBar.vertical: TheophanyScrollBar {}

                                        delegate: Rectangle {
                                            id: libraryDelegate
                                            width: ListView.view.width
                                            height: 85
                                            color: libHover.hovered ? Qt.lighter(Theme.secondaryBackground, 1.1) : Theme.secondaryBackground
                                            border.color: libHover.hovered ? Theme.border : "transparent"
                                            border.width: 1
                                            radius: 8

                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            HoverHandler { id: libHover }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 12

                                                // Unified Thumbnail Area
                                                Rectangle {
                                                    Layout.preferredWidth: 80
                                                    Layout.fillHeight: true
                                                    color: "black"
                                                    radius: 4
                                                    clip: true

                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: "🎬"
                                                        opacity: libHover.hovered ? 1.0 : 0.6
                                                        font.pixelSize: 22
                                                    }

                                                    TapHandler {
                                                        onTapped: {
                                                            root.streaming = false 
                                                            root.currentPlayingTitle = modelData.title
                                                            root.currentPlayingUploader = "Local Library"
                                                            streamPlayer.stop()
                                                            streamPlayer.source = ""
                                                            streamPlayer.source = modelData.url
                                                            streamPlayer.play()
                                                            videoContainer.forceActiveFocus()
                                                        }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    Label {
                                                        text: modelData.title
                                                        color: Theme.text
                                                        font.bold: true
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }

                                                    Label {
                                                        text: (modelData.size || "--") + " • " + (modelData.duration || "--:--")
                                                        color: Theme.secondaryText
                                                        font.pixelSize: 10
                                                    }

                                                    RowLayout {
                                                        spacing: 8
                                                        TheophanyButton {
                                                            text: "Play"
                                                            Layout.preferredHeight: 28
                                                            Layout.alignment: Qt.AlignVCenter
                                                            onClicked: {
                                                                root.streaming = false 
                                                                root.currentPlayingTitle = modelData.title
                                                                root.currentPlayingUploader = "Local Library"
                                                                streamPlayer.stop()
                                                                streamPlayer.source = ""
                                                                streamPlayer.source = modelData.url
                                                                streamPlayer.play()
                                                                videoContainer.forceActiveFocus()
                                                            }
                                                        }

                                                        Rectangle {
                                                            Layout.preferredHeight: 28
                                                            Layout.preferredWidth: 36
                                                            Layout.alignment: Qt.AlignVCenter
                                                            radius: 6
                                                            color: deleteHover.hovered ? Qt.lighter("#cc0000", 1.1) : "#cc0000"
                                                            
                                                            Behavior on color { ColorAnimation { duration: 100 } }
                                                            
                                                            Label {
                                                                anchors.centerIn: parent
                                                                text: "🗑️"
                                                                font.pixelSize: 14
                                                            }
                                                            
                                                            HoverHandler { id: deleteHover }
                                                            TapHandler {
                                                                onTapped: videoProxyInternal.deleteVideo(modelData.path)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                    }
                                    
                                    Label {
                                        visible: root.localVideos.length === 0
                                        text: "No local videos found."
                                        color: Theme.secondaryText
                                        Layout.alignment: Qt.AlignCenter
                                        Layout.fillHeight: true
                                    }
                                }
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    color: Theme.border
                }

                // RIGHT PANE: Video Player (approx 66%)
                Item {
                    id: videoSlot
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        id: videoContainer
                        anchors.fill: parent
                        color: "#020202"
                        clip: true
                        focus: true // Enable focus for keys

                        property bool isFullscreen: false
                        
                        function toggleFullscreen() {
                            if (isFullscreen) {
                                videoContainer.parent = videoSlot
                                videoContainer.z = 0 // Reset Z
                                isFullscreen = false
                                videoContainer.forceActiveFocus()
                            } else {
                                videoContainer.parent = Overlay.overlay
                                videoContainer.z = 1000 // Ensure it is on top of the modal
                                isFullscreen = true
                                videoContainer.forceActiveFocus()
                            }
                        }
                        
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_F) {
                                toggleFullscreen()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape && isFullscreen) {
                                toggleFullscreen()
                                event.accepted = true
                            }
                        }

                        MouseArea {
                            id: playerMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                videoContainer.forceActiveFocus()
                            }
                            onDoubleClicked: {
                                videoContainer.toggleFullscreen()
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "black"
                                    
                                    VideoOutput {
                                        id: videoOutput
                                        anchors.fill: parent
                                        fillMode: VideoOutput.PreserveAspectFit
                                        z: 1
                                    }

                                    // Top Video Metadata Bar
                                    Rectangle {
                                        anchors.top: parent.top
                                        width: parent.width
                                        height: 50
                                        z: 10
                                        visible: (playerMouseArea.containsMouse || root.streaming) && streamPlayer.playbackState !== MediaPlayer.StoppedState
                                        opacity: playerMouseArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "#AA000000" }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 15
                                            anchors.topMargin: 8
                                            spacing: 0

                                            Label {
                                                text: root.currentPlayingTitle
                                                color: "white"
                                                font.bold: true
                                                font.pixelSize: 14
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: root.currentPlayingUploader
                                                color: "#CCCCCC"
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                    
                                    MediaPlayer {
                                        id: streamPlayer
                                        videoOutput: videoOutput
                                        audioOutput: AudioOutput { volume: 1.0 }
                                    }

                                    // Player Overlay / Placeholder
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "black"
                                        visible: streamPlayer.playbackState === MediaPlayer.StoppedState && !root.streaming
                                        z: 5
                                        
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 10
                                            Label {
                                                text: "Preview Area"
                                                color: Theme.secondaryText
                                                font.pixelSize: 16
                                            }
                                            Label {
                                                text: "Select a video on the left to start streaming"
                                                color: Theme.secondaryText
                                                font.pixelSize: 12
                                            }
                                        }
                                    }

                                    // Interactive Controls Overlay
                                    Rectangle {
                                        id: controlsOverlay
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 80
                                        z: 15
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: "#CC000000" }
                                        }
                                        visible: (playerMouseArea.containsMouse || root.streaming) && streamPlayer.playbackState !== MediaPlayer.StoppedState
                                        opacity: playerMouseArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 15
                                            spacing: 5

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                
                                                TheophanyButton {
                                                    text: streamPlayer.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                                                    Layout.preferredWidth: 70
                                                    Layout.preferredHeight: 28
                                                    Layout.alignment: Qt.AlignVCenter
                                                    focusPolicy: Qt.NoFocus
                                                    onClicked: {
                                                        if (streamPlayer.playbackState === MediaPlayer.PlayingState) {
                                                            streamPlayer.pause()
                                                        } else {
                                                            streamPlayer.play()
                                                        }
                                                        videoContainer.forceActiveFocus()
                                                    }
                                                }

                                                Slider {
                                                    id: seekSlider
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    from: 0
                                                    to: streamPlayer.duration
                                                    value: streamPlayer.position
                                                    enabled: streamPlayer.seekable
                                                    focusPolicy: Qt.NoFocus // Don't steal focus
                                                    onMoved: streamPlayer.position = value
                                                    
                                                    background: Rectangle {
                                                        x: seekSlider.leftPadding
                                                        y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 200
                                                        implicitHeight: 4
                                                        width: seekSlider.availableWidth
                                                        height: implicitHeight
                                                        radius: 2
                                                        color: Theme.border

                                                        Rectangle {
                                                            width: seekSlider.visualPosition * parent.width
                                                            height: parent.height
                                                            color: Theme.accent
                                                            radius: 2
                                                        }
                                                    }

                                                    handle: Rectangle {
                                                        x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                                                        y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 12
                                                        implicitHeight: 12
                                                        radius: 6
                                                        color: Theme.accent
                                                        visible: seekSlider.hovered || seekSlider.pressed
                                                    }
                                                }

                                                Label {
                                                    text: formatDuration(streamPlayer.position / 1000) + " / " + formatDuration(streamPlayer.duration / 1000)
                                                    color: "white"
                                                    font.pixelSize: 11
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                
                                                TheophanyButton {
                                                    text: videoContainer.isFullscreen ? "Exit" : "Fullscreen"
                                                    Layout.preferredHeight: 28
                                                    Layout.alignment: Qt.AlignVCenter
                                                    focusPolicy: Qt.NoFocus
                                                    onClicked: {
                                                        videoContainer.toggleFullscreen()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        visible: root.streaming || (streamPlayer.playbackState === MediaPlayer.LoadingState && streamPlayer.playbackState !== MediaPlayer.PlayingState)
                                        z: 10
                                    }
                                }

                                // Download progress indicator
                                Rectangle {
                                    id: downloadStatus
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.downloading ? 40 : 0
                                    color: Theme.accent
                                    visible: Layout.preferredHeight > 0
                                    clip: true

                                    Label {
                                        anchors.centerIn: parent
                                        text: "Downloading system... stays open until finished"
                                        color: "white"
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    function getBetterThumbnail(modelData) {
        if (!modelData.id) return modelData.thumbnail || ""
        // Use the suggested format for YouTube thumbnails
        return "https://img.youtube.com/vi/" + modelData.id + "/0.jpg"
    }

    function refreshLibrary() {
        if (root.gameId && root.platformFolder) {
            videoProxyInternal.getVideoList(root.gameId, root.platformFolder)
        }
    }

    function sortSearchResults() {
        if (root.searchResults.length === 0) return;
        
        // Clone array to modify
        var arr = root.searchResults.slice()
        
        if (root.sortMode === "Longest") {
             arr.sort((a, b) => {
                 return (b.duration || 0) - (a.duration || 0)
             })
        } else if (root.sortMode === "Shortest") {
             arr.sort((a, b) => {
                 return (a.duration || 0) - (b.duration || 0)
             })
        } else {
             // Relevance (Default from backend)
             // We implicitly rely on searchResults being in original order.
             // If we want to restore order perfectly, we'd need a separate original list.
             // For now, re-searching restores relevance.
        }
        root.searchResults = arr
    }

    function startSearch() {
        if (searchField.text === "") return
        root.searching = true
        root.searchResults = []
        videoProxyInternal.searchVideos(searchField.text)
    }
    
    function show(gId, gTitle, gPlatform, gPlatformType, pFolder) {
        root.gameId = gId 
        root.gameTitle = gTitle
        root.gamePlatform = gPlatform
        root.platformFolder = pFolder
        
        // Use Platform Type for search if available for better accuracy (e.g. "steam", "heroic")
        // Mapping "steam", "heroic", "lutris", and PC variants to "PC" for better search results
        var pSearch = ""
        var tLower = (gPlatformType || "").toLowerCase()
        var pLower = (gPlatform || "").toLowerCase()
        
        // Use indexOf for broader compatibility/robustness with collection names
        if (tLower.indexOf("steam") !== -1 || tLower.indexOf("heroic") !== -1 || tLower.indexOf("lutris") !== -1 || tLower.indexOf("epic") !== -1 || 
            tLower.indexOf("pc (") !== -1 || tLower === "pc" ||
            pLower.indexOf("steam") !== -1 || pLower.indexOf("heroic") !== -1 || pLower.indexOf("lutris") !== -1 || pLower.indexOf("epic") !== -1) {
            pSearch = "PC"
        } else if (gPlatformType && gPlatformType !== "" && gPlatformType !== "Unknown") {
            pSearch = gPlatformType
        } else {
            pSearch = gPlatform
        }
        
        searchField.text = gTitle + " " + pSearch
        
        startSearch()
        refreshLibrary()
        root.open()
    }
    
    function formatDuration(seconds) {
        if (!seconds) return "--:--";
        var sec_num = parseInt(seconds, 10);
        var hours   = Math.floor(sec_num / 3600);
        var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
        var seconds = sec_num - (hours * 3600) - (minutes * 60);

        if (hours   < 10) {hours   = "0"+hours;}
        if (minutes < 10) {minutes = "0"+minutes;}
        if (seconds < 10) {seconds = "0"+seconds;}
        
        if (hours !== "00") return hours+':'+minutes+':'+seconds;
        return minutes+':'+seconds;
    }
}
