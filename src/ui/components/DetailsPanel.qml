import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtMultimedia
import QtQuick.Window
import Theophany.Bridge 1.0
import "../style"
import "../dialogs"


Rectangle {
    id: root
    
    property var gameModel: null
    
    property var videoList: []
    property int currentVideoIndex: 0
    property string currentVideoTitle: ""
    
    property var imageList: []
    property int currentImageIndex: 0
    property string currentImageType: "Box - Front" // Default type to cycle
    
    // View State
    property bool showVideoOverlay: false
    
    // Watch for setting changes to auto-switch if currently viewing a game with video
    Connections {
        target: appSettings
        function onDetailsPreferVideoChanged() {
            if (appSettings.detailsPreferVideo && root.videoList.length > 0) {
                root.showVideoOverlay = true
            }
        }
    }


    VideoProxy {
        id: videoProxy
        onVideoAvailable: (url) => {
            // Simple discovery might still trigger this, we'll favor the list logic
            if (root.videoList.length === 0) {
                root.videoList = [{"title": "Trailer", "url": url}]
                root.currentVideoIndex = 0
                loadCurrentVideo()
            }
        }
        onVideoListReady: (json) => {

            try {
                var list = JSON.parse(json)
                root.videoList = list
                if (list.length > 0) {
                    root.currentVideoIndex = 0
                    
                    var hasImages = (root.imageList.length > 0 || root.boxArtSource !== "")
                    
                    if (appSettings.detailsPreferVideo || !hasImages) {
                        root.showVideoOverlay = true
                        loadCurrentVideo()
                    } else {
                        root.showVideoOverlay = false
                        player.stop() // Ensure stopped
                    }
                } else {
                    root.showVideoOverlay = false
                }
            } catch (e) {

                root.videoList = []
                root.showVideoOverlay = false
            }
        }
        onVideoUnavailable: () => {
             if (root.videoList.length === 0) {
                 root.showVideoOverlay = false
                 player.stop()
             }
        }
    }
    
    function loadCurrentVideo() {
        if (root.videoList.length > 0 && root.currentVideoIndex < root.videoList.length) {
            var v = root.videoList[root.currentVideoIndex]
            player.stop()
            player.source = ""
            player.source = v.url
            root.currentVideoTitle = v.title
            
            if (root.showVideoOverlay) {
                player.play()
            }
        }
    }
    
    onShowVideoOverlayChanged: {
        if (showVideoOverlay) {
            if (player.playbackState !== MediaPlayer.PlayingState) {
                loadCurrentVideo() // This will play it
            }
        } else {
            player.pause()
        }
    }

    function nextVideo() {
        if (root.videoList.length > 1) {
            root.currentVideoIndex = (root.currentVideoIndex + 1) % root.videoList.length
            loadCurrentVideo()
        }
    }

    function prevVideo() {
        if (root.videoList.length > 1) {
            root.currentVideoIndex = (root.currentVideoIndex - 1 + root.videoList.length) % root.videoList.length
            loadCurrentVideo()
        }
    }
    
    StoreBridge { id: storeBridge }

    Timer {
        id: pollTimer
        interval: 100
        repeat: true
        running: true // Always poll for background events
        onTriggered: {
            videoProxy.poll()
            storeBridge.poll()
        }
    }

    Connections {
        target: root.gameModel
        function onPlaytimeUpdated(romId) {

            if (String(root.gameId) === String(romId) && !appSettings.isPlatformRaActive(root.gamePlatformType)) {
                // Skiping RA fetch for non-RA platforms
            } else if (String(root.gameId) === String(romId)) {
                root.refreshAchievements(true)
            }
        }

        function onGameDataChanged(romId) {

            if (String(root.gameId) === String(romId)) {
                // Determine our index to reload via window helper
                if (typeof window !== "undefined" && window.loadGameDetails) {
                    var idx = root.gameModel.getRowById(romId)
                    if (idx >= 0) {

                        window.loadGameDetails(idx)
                        root.checkImages() // Force local image check too
                    }
                } else {
                    // Fallback: local refresh
                    root.checkImages()
                }
            }
        }
    }
    
    onGameIdChanged: {
        raOverlay.visible = false
        root.videoList = []
        root.currentVideoIndex = 0
        root.currentVideoTitle = ""
        root._recentBadges = []
        root._steamAchievementsUnlocked = 0
        root._steamAchievementsCount = 0
        root._steamRecentBadges = []
    }

    onGameFilenameChanged: {
        if (root.gameFilename !== "" && root.gameFilename !== "--") {
            checkVideo()
            checkImages()
        }
    }
    
    function checkVideo() {
        if (root.gameFilename !== "" && root.gameFilename !== "--" && root.platformFolder !== "") {
             videoProxy.getVideoList(root.gameFilename, root.platformFolder)
        } else {
             videoOverlay.visible = false
        }
    }

    function checkImages() {
        if (root.gameId !== "") {
             var json = gameModel.getGameMetadata(root.gameId)
              try {
                  var data = JSON.parse(json)
                  updateImageList(data)
                  updateResources(data)
                  
                  // Load persistent RA data or Steam data
                  if (root.gamePlatformType.toLowerCase() === "steam") {
                      root._steamAchievementsCount = data.achievement_count || 0
                      root._steamAchievementsUnlocked = data.achievement_unlocked || 0
                      if (data.ra_recent_badges) {
                          try {
                              var badges = JSON.parse(data.ra_recent_badges)
                              var wrapped = []
                              for (var i=0; i<badges.length; i++) {
                                  wrapped.push({ "iconUrl": badges[i] })
                              }
                              root._steamRecentBadges = wrapped
                          } catch(e) { root._steamRecentBadges = [] }
                      } else {
                          root._steamRecentBadges = []
                      }
                  } else {
                      root.achievementCount = data.achievement_count || 0
                      root.achievementUnlocked = data.achievement_unlocked || 0
                      if (data.ra_recent_badges) {
                          try {
                              var badges = JSON.parse(data.ra_recent_badges)
                              var wrapped = []
                              for (var i=0; i<badges.length; i++) {
                                  wrapped.push({ "badgeName": badges[i] })
                              }
                              root._recentBadges = wrapped
                          } catch(e) { root._recentBadges = [] }
                      } else {
                          root._recentBadges = []
                      }
                  }
              } catch(e) {

              }
        }
    }

    function updateResources(data) {
        if (data.resources) {
            root.gameResources = data.resources
        } else {
            root.gameResources = []
        }
        
        // Also check if we have a manual in assets but not in resources (Legacy support or Auto-discovery)
        // For now, we rely on the backend to populate the resources list.
    }

    function updateImageList(data) {
        var list = []
        // Defined order for carousel
        var priorityOrder = ["Box - Front", "Box - Back", "Screenshot", "Title Screen", "Background", "Clear Logo", "Banner"]
        var addedTypes = []

        // 1. Add priority types in order
        for (var i = 0; i < priorityOrder.length; i++) {
            var type = priorityOrder[i]
            if (data.assets && data.assets[type]) {
                var assets = data.assets[type]
                for (var j = 0; j < assets.length; j++) {
                    list.push({
                        "url": "file://" + assets[j],
                        "type": type
                    })
                }
                addedTypes.push(type)
            }
        }

        // 2. Add any remaining types not in priority list
        if (data.assets) {
            for (var type in data.assets) {
                if (addedTypes.indexOf(type) === -1) {
                    var assets = data.assets[type]
                    for (var j = 0; j < assets.length; j++) {
                        list.push({
                            "url": "file://" + assets[j],
                            "type": type
                        })
                    }
                }
            }
        }
        root.imageList = list
        root.currentImageIndex = 0
    }

    function nextImage() {
        if (root.imageList.length > 1) {
            root.currentImageIndex = (root.currentImageIndex + 1) % root.imageList.length
        }
    }

    function prevImage() {
        if (root.imageList.length > 1) {
            root.currentImageIndex = (root.currentImageIndex - 1 + root.imageList.length) % root.imageList.length
        }
    }

    Timer {
        id: imageCycleTimer
        interval: 5000 // 5 seconds
        repeat: true
        running: root.imageList.length > 1 && !videoOverlay.visible && !imageViewer.visible
        onTriggered: nextImage()
    }
    
    // UI ... (rest unchanged until videoOverlay)

    color: Qt.rgba(Theme.secondaryBackground.r, Theme.secondaryBackground.g, Theme.secondaryBackground.b, 0.9)
    border.color: Theme.border
    border.width: 1
    radius: 0
    
    property bool isFullscreen: false
    
    function toggleFullscreen() {
        if (root.isFullscreen) {
            videoOverlay.parent = headerArea
            root.isFullscreen = false
        } else {
            videoOverlay.parent = Window.window.contentItem
            root.isFullscreen = true
        }
    }
    property string platformFolder: ""
    property string gameId: ""
    property string gameTitle: "No Game Selected"
    property string gamePlatform: "--"
    property string gamePlatformIcon: ""
    property string gameIcon: ""
    property string gameDeveloper: "--"
    property string gamePublisher: "--"
    property string gameGenre: "--"
    property string gameRegion: "--"
    property int gamePlayCount: 0
    property int gameLastPlayed: 0
    property int gameTotalTime: 0
    
    property string gameTags: ""
    property real gameRating: 0.0
    property string gameReleaseDate: ""
    property bool gameIsFavorite: false
    property string gamePlatformId: ""
    property string gamePlatformType: ""
    property var emulatorProfiles: []
    property var gameResources: []
    
    function refreshProfiles() {

        if (!gamePlatformId) {
            emulatorProfiles = []
            return
        }
        var json = gameModel.getEmulatorProfiles(gamePlatformId)

        try {
            emulatorProfiles = JSON.parse(json)
        } catch(e) {

            emulatorProfiles = []
        }
    }

    function clear() {
        root.gameId = ""
        root.gameTitle = "No Game Selected"
        root.gamePlatform = "--"
        root.gamePlatformIcon = ""
        root.gameIcon = ""
        root.gameDeveloper = "--"
        root.gamePublisher = "--"
        root.gameGenre = "--"
        root.gameRegion = "--"
        root.gamePlayCount = 0
        root.gameLastPlayed = 0
        root.gameTotalTime = 0
        root.gameTags = ""
        root.gameRating = 0.0
        root.gameReleaseDate = ""
        root.gameIsFavorite = false
        root.gamePlatformId = ""
        root.gamePlatformType = ""
        root.gameDescription = "Select a game from the library to view details."
        root.boxArtSource = ""
        root.bannerSource = ""
        root.gameFilename = ""
        root.videoList = []
        root.imageList = []
        root.currentVideoIndex = 0
        root.currentImageIndex = 0
        root.showVideoOverlay = false
        player.stop()
    }

    onGamePlatformIdChanged: refreshProfiles()
    property string gameDescription: "Select a game from the library to view details."
    property string boxArtSource: ""
    property string bannerSource: ""
    property string gameFilename: ""

    signal playRequested(string gameId)
    signal filterGenre(string genre)

    property bool _silentRefresh: false
    property bool isLaunching: false
    property int _steamAchievementsUnlocked: 0
    property int _steamAchievementsCount: 0
    property var _steamRecentBadges: []
    
    Timer {
        id: launchTimer
        interval: 2000
        onTriggered: root.isLaunching = false
    }


    function triggerLaunchFeedback() {
        isLaunching = true
        launchTimer.restart()
    }

    function refreshAchievements(silent) {
        _silentRefresh = !!silent
        var rs = window.appSettingsRef
        
        if (root.gamePlatformType.toLowerCase() === "steam") {
            var steamUser = rs.steamId
            var steamKey = rs.steamApiKey
            if (steamUser !== "" && steamKey !== "") {
                var appid = root.gameFilename.replace(".acf", "")
                storeBridge.refresh_steam_achievements(appid, steamUser, steamKey)
            }
        } else {
            var user = rs.retroAchievementsUser
            var key = rs.retroAchievementsToken
            if (user !== "" && key !== "" && root.fullRomPath !== "" && rs.retroAchievementsEnabled) {
                raBridge.fetchGameData(root.gameId, root.fullRomPath, root.gameTitle, root.platformFolder, user, key)
            }
        }
    }

    Connections {
        target: storeBridge
        function onSteamAchievementsFinished(json, success, message) {
            if (success) {
                try {
                    var data = JSON.parse(json)
                    root._steamAchievementsUnlocked = data.unlocked_count || 0
                    root._steamAchievementsCount = data.total_count || 0
                    
                    achievementModel.clear()
                    
                    var newBadges = []
                    if (data.achievements && data.achievements.length > 0) {
                        var list = data.achievements
                        for (var i = 0; i < list.length; i++) {
                            var ach = list[i]
                            var iconUrl = ach.unlocked ? (ach.icon || "") : (ach.icongray || "")
                            
                            achievementModel.append({
                                id: ach.name || "",
                                title: ach.displayName || ach.name || "Hidden Achievement",
                                description: ach.description || "",
                                points: 0,
                                badgeName: iconUrl, // Steam provides full HTTP URLs here
                                unlocked: !!ach.unlocked,
                                dateEarned: ach.unlock_time ? (new Date(ach.unlock_time * 1000).toISOString()) : ""
                            })
                            
                            if (ach.unlocked) {
                                newBadges.push({ "iconUrl": iconUrl })
                            }
                        }
                    }
                    
                    // Sort recent badges by unlock time (assuming recent pushes to end, or just take first 8)
                    root._steamRecentBadges = newBadges.slice(Math.max(newBadges.length - 8, 0)).reverse()
                    
                    // Persist to DB
                    var badgeUrls = root._steamRecentBadges.map(b => b.iconUrl)
                    gameModel.updateGameAchievements(root.gameId, root._steamAchievementsCount, root._steamAchievementsUnlocked, JSON.stringify(badgeUrls))
                    
                    raOverlay.infoText = "Steam Progress"
                    raOverlay.unlockedCount = root._steamAchievementsUnlocked
                    raOverlay.totalCount = root._steamAchievementsCount
                    if (!root._silentRefresh) raOverlay.visible = true
                    
                } catch(e) {
                    if (!root._silentRefresh) raOverlay.infoText = "Error parsing Steam output"
                }
            } else {
                 if (!root._silentRefresh) raOverlay.infoText = "Steam API Error: " + message
            }
        }
    }

    function openImageViewer() {
        if (imageList.length > 0) {
            imageViewer.open()
        }
    }

        Flickable {
            id: mainFlickable
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomToolbar.top
            contentHeight: mainColumn.implicitHeight
            clip: true
            interactive: true
            ScrollBar.vertical: TheophanyScrollBar { }

            ColumnLayout {
                id: mainColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 15

        // Header Area (Banner or Box Art)
        Rectangle {
            id: headerArea
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            color: Theme.secondaryBackground
            radius: 8
            clip: true

            property bool headerHovered: headerBackgroundMouse.containsMouse || 
                                         carouselHoverArea.containsMouse || 
                                         controlsArea.containsMouse || 
                                         navHoverArea.containsMouse ||
                                         prevButtonMouse.containsMouse ||
                                         nextButtonMouse.containsMouse
            
            MouseArea {
                id: headerBackgroundMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            // Steady Background Banner (Static)
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.bannerSource
                visible: source !== ""
                opacity: 0.3
                cache: false
            }
            
            // Top Image (Foreground - Cycling)

            Item {
                anchors.centerIn: parent
                height: parent.height - 20
                width: parent.width - 20

                Item {
                    id: imageSlot
                    anchors.centerIn: parent
                    height: parent.height
                    width: parent.width

                    property string currentSource: (root.imageList && root.imageList.length > 0 && root.currentImageIndex < root.imageList.length && root.imageList[root.currentImageIndex]) ? root.imageList[root.currentImageIndex].url : root.boxArtSource
                    
                    onCurrentSourceChanged: {
                        if (image1.opacity === 1) {
                            image2.source = currentSource
                            image2.opacity = 1
                            image1.opacity = 0
                        } else {
                            image1.source = currentSource
                            image1.opacity = 1
                            image2.opacity = 0
                        }
                    }

                    Image {
                        id: image1
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: imageSlot.currentSource
                        opacity: 1
                        Behavior on opacity { NumberAnimation { duration: 600 } }
                        visible: opacity > 0
                        cache: false
                    }

                    Image {
                        id: image2
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        opacity: 0
                        Behavior on opacity { NumberAnimation { duration: 600 } }
                        visible: opacity > 0
                        cache: false
                    }

                    MouseArea {
                        id: carouselHoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: imageViewer.open()
                    }
                }

                // Hover Navigation Overlay
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.4)
                    opacity: headerArea.headerHovered && root.imageList.length > 1 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    z: 5
                    
                    // Explicitly block clicks so they don't go to carouselHoverArea if needed, 
                    // though both open the viewer for now.
                    MouseArea {
                        id: navHoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: imageViewer.open()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 0
                        
                        Item {
                            Layout.preferredWidth: 50
                            Layout.fillHeight: true
                            
                            Rectangle {
                                anchors.centerIn: parent
                                width: 44; height: 44; radius: 22
                                color: prevButtonMouse.containsMouse ? Theme.accent : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.6)
                                border.color: Theme.text
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: -1 // Visually center the triangle
                                    text: "◀"
                                    color: Theme.text
                                    font.pixelSize: 22
                                }

                                MouseArea {
                                    id: prevButtonMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        imageCycleTimer.restart()
                                        prevImage()
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Item {
                            Layout.preferredWidth: 50
                            Layout.fillHeight: true
                            
                            Rectangle {
                                anchors.centerIn: parent
                                width: 44; height: 44; radius: 22
                                color: nextButtonMouse.containsMouse ? Theme.accent : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.6)
                                border.color: Theme.text
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: 1 // Visually center the triangle
                                    text: "▶"
                                    color: Theme.text
                                    font.pixelSize: 22
                                }

                                MouseArea {
                                    id: nextButtonMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        imageCycleTimer.restart()
                                        nextImage()
                                    }
                                }
                            }
                        }
                    }

                    // Image Type Indicator
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 15
                        height: 24
                        width: typeText.width + 30
                        radius: 12
                        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.7)
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.2)
                        border.width: 1
                        Text {
                            id: typeText
                            anchors.centerIn: parent
                            text: (root.imageList && root.imageList.length > 0 && root.currentImageIndex < root.imageList.length && root.imageList[root.currentImageIndex]) ? root.imageList[root.currentImageIndex].type : ""
                            color: Theme.text
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }
                }
            }
            
            Text {
                anchors.centerIn: parent
                text: "No Image"
                color: Theme.secondaryText
                visible: root.imageList.length === 0 && root.boxArtSource === "" && root.bannerSource === ""
            }

            // Small Pagination Dots (always visible if multiple)
            Row {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 5
                visible: root.imageList.length > 1 && !videoOverlay.visible
                spacing: 5
                z: 10
                Repeater {
                    model: Math.min(root.imageList.length, 12)
                    Rectangle {
                        width: 4; height: 4; radius: 2
                        color: index === root.currentImageIndex ? Theme.accent : Theme.secondaryText
                    }
                }
            }

            // Video Overlay
            Item {
                id: videoOverlay
                anchors.fill: parent
                visible: root.showVideoOverlay
                
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }

                VideoOutput {
                    id: videoOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                MediaPlayer {
                    id: player
                    videoOutput: videoOutput
                    audioOutput: AudioOutput {
                        id: audio
                        muted: true // Default muted
                        volume: 1.0
                    }
                    loops: MediaPlayer.Infinite
                }
                
                MouseArea {
                    id: controlsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (player.playbackState === MediaPlayer.PlayingState) {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }
                    onDoubleClicked: {
                        toggleFullscreen()
                    }

                    Shortcut {
                        sequence: "Escape"
                        enabled: root.isFullscreen
                        onActivated: toggleFullscreen()
                    }
                    
                    // Top Info Bar (Video Title)
                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 30
                        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.7)
                        visible: headerArea.headerHovered && root.videoList.length > 0
                        
                        Label {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            text: root.currentVideoTitle
                            color: Theme.text
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }

                    // Bottom Controls Overlay
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 40
                        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
                        visible: headerArea.headerHovered
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 5
                            
                            Button {
                                text: audio.muted ? "🔇" : "🔊"
                                background: null
                                contentItem: Text { text: parent.text; color: Theme.text; font.pixelSize: 16 }
                                onClicked: audio.muted = !audio.muted
                            }
                            
                            Slider {
                                id: seekSlider
                                Layout.fillWidth: true
                                Layout.preferredHeight: 20
                                from: 0
                                to: player.duration
                                value: player.position
                                enabled: player.seekable
                                onMoved: player.position = value
                                
                                background: Rectangle {
                                    x: seekSlider.leftPadding
                                    y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 100
                                    implicitHeight: 2
                                    width: seekSlider.availableWidth
                                    height: implicitHeight
                                    radius: 1
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.2)

                                    Rectangle {
                                        width: seekSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: Theme.accent
                                        radius: 1
                                    }
                                }

                                handle: Rectangle {
                                    x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                                    y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 10
                                    implicitHeight: 10
                                    radius: 5
                                    color: Theme.accent
                                    visible: seekSlider.hovered || seekSlider.pressed
                                }
                            }

                            // Navigation (Collection Cycling)
                            RowLayout {
                                visible: root.videoList.length > 1
                                spacing: 10
                                
                                Button {
                                    text: "◀"
                                    background: null
                                    contentItem: Text { text: parent.text; color: Theme.text; font.pixelSize: 14 }
                                    onClicked: prevVideo()
                                }
                                
                                Label {
                                    text: (root.currentVideoIndex + 1) + " / " + root.videoList.length
                                    color: Theme.text
                                    font.pixelSize: 11
                                }

                                Button {
                                    text: "▶"
                                    background: null
                                    contentItem: Text { text: parent.text; color: Theme.text; font.pixelSize: 14 }
                                    onClicked: nextVideo()
                                }
                            }

                            Item { Layout.fillWidth: true }
                            
                            Button {
                                text: root.isFullscreen ? "↙" : "⛶"
                                background: null
                                contentItem: Text { text: parent.text; color: Theme.text; font.pixelSize: 16 }
                                onClicked: toggleFullscreen()
                            }
                        }
                    }
                }
            }

            // Media Switcher Layer (Top right of any media)
            Item {
                anchors.fill: parent
                z: 50
                visible: (root.imageList.length > 0 || root.boxArtSource !== "") && root.videoList.length > 0
                
                opacity: headerArea.headerHovered ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 250 } }
                
                Row {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 8
                    
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: !root.showVideoOverlay ? Theme.accent : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.7)
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.3)
                        border.width: 1
                        Text { anchors.centerIn: parent; text: "🖼️"; font.pixelSize: 12 }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.showVideoOverlay = false
                        }
                    }

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: root.showVideoOverlay ? Theme.accent : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.7)
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.3)
                        border.width: 1
                        Text { anchors.centerIn: parent; text: "🎬"; font.pixelSize: 12 }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.showVideoOverlay = true
                        }
                    }
                }
            }
        }

        // Title and Info
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                
                Image {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    source: root.gameIcon
                    fillMode: Image.PreserveAspectFit
                    visible: root.gameIcon !== ""
                    cache: false
                }
                
                Text {
                    text: root.gameTitle
                    color: Theme.text
                    font.pixelSize: 22
                    font.bold: true
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }

            // Developer / Publisher
            Text {
                text: {
                    var parts = []
                    if (root.gameDeveloper !== "--" && root.gameDeveloper !== "") parts.push(root.gameDeveloper)
                    if (root.gamePublisher !== "--" && root.gamePublisher !== "" && root.gamePublisher !== root.gameDeveloper) parts.push(root.gamePublisher)
                    return parts.join(" • ")
                }
                color: Theme.secondaryText
                font.pixelSize: 13
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                visible: text !== ""
            }
            
            // Meta Row 1: Platform | Year
            RowLayout {
                spacing: 6
                Layout.fillWidth: true
                
                Text {
                    visible: root.gamePlatformIcon !== "" && root.gamePlatformIcon.length <= 2
                    text: root.gamePlatformIcon
                    color: Theme.secondaryText
                    font.pixelSize: 12
                }
                Image {
                    visible: root.gamePlatformIcon !== "" && root.gamePlatformIcon.length > 2
                    source: {
                        if (!root.gamePlatformIcon || root.gamePlatformIcon.length <= 2) return ""
                        if (root.gamePlatformIcon.startsWith("http") || root.gamePlatformIcon.startsWith("file://") || root.gamePlatformIcon.startsWith("qrc:/") || root.gamePlatformIcon.startsWith("/")) {
                            return root.gamePlatformIcon.startsWith("/") ? "file://" + root.gamePlatformIcon : root.gamePlatformIcon
                        }
                        if (root.gamePlatformIcon.startsWith("assets/")) {
                            return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + root.gamePlatformIcon
                        }
                        return "file://" + root.gamePlatformIcon
                    }
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: root.gamePlatform + (root.gameReleaseDate !== "" ? " • " + root.gameReleaseDate : "")
                    color: Theme.secondaryText
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
            }

            // Genre Badges
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: root.gameGenre !== "--" && root.gameGenre !== ""
                
                Repeater {
                    model: root.gameGenre.split(",")
                    
                    Rectangle {
                        height: 20
                        width: genreText.width + 12
                        radius: 4
                        color: genreMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                        border.color: genreMouse.containsMouse ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            id: genreText
                            anchors.centerIn: parent
                            text: modelData.trim()
                            color: genreMouse.containsMouse ? Theme.accent : Theme.secondaryText
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            id: genreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.filterGenre(modelData.trim())
                        }
                    }
                }
            }

            // Region
            Text {
                text: root.gameRegion !== "--" && root.gameRegion !== "" ? "Region: " + root.gameRegion : ""
                color: Theme.secondaryText
                font.pixelSize: 12
                visible: text !== ""
            }

            // Rating
            RowLayout {
                spacing: 5
                visible: root.gameRating > 0
                Text {
                    text: "Rating:"
                    color: Theme.secondaryText
                    font.pixelSize: 12
                }
                Text {
                    text: "★ " + root.gameRating.toFixed(1)
                    color: Theme.accent
                    font.pixelSize: 12
                }
            }

            // Stats
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
                Layout.topMargin: 5
                Layout.bottomMargin: 5
            }

            // Tags (Pill Style)
            Flow {
                Layout.fillWidth: true
                spacing: 5
                visible: root.gameTags !== ""
                Repeater {
                    model: root.gameTags.split(',')
                    Rectangle {
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                        radius: 4
                        height: 20
                        width: tagText.width + 12
                        Text {
                            id: tagText
                            anchors.centerIn: parent
                            text: modelData.trim()
                            color: Theme.secondaryText
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }
                }
            }
            
            // Unified Achievement Card
            Rectangle {
                id: raCard
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                Layout.topMargin: 5
                visible: appSettings.isPlatformRaActive(root.gamePlatformType) && 
                         !["PC (Windows)", "PC (Linux)", "steam", "heroic", "lutris"].includes(root.gamePlatformType.toLowerCase())
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.05)
                border.color: cardMouse.containsMouse ? Theme.accent : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.3)
                border.width: 1
                radius: 8
                clip: true

                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var rs = Window.window.appSettingsRef
                        var user = rs.retroAchievementsUser
                        var key = rs.retroAchievementsToken
                        
                        if (user === "" || key === "") {
                            raOverlay.infoText = "Please login in Settings first."
                            raOverlay.visible = true
                        } else {
                             raOverlay.infoText = "Checking Achievements..."
                             raOverlay.visible = true
                             root.refreshAchievements(false)
                         }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 15

                    // Icon / Progress Circle
                    Item {
                        width: 44; height: 44
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: 22
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            
                            Image {
                                anchors.centerIn: parent
                                source: "file://" + appInfo.getAssetsDir() + "/RA.png"
                                width: 28; height: 28
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "RetroAchievements"
                            color: Theme.accent
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Text {
                            text: root.achievementCount > 0 ? (root.achievementUnlocked + " / " + root.achievementCount + " Unlocked") : "Click to check achievements"
                            color: Theme.text
                            font.pixelSize: 12
                            opacity: 0.8
                        }
                    }

                    // Badge Artwork Row
                    Row {
                        spacing: -8 // Overlapping icons for style
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.achievementUnlocked > 0
                        
                        Repeater {
                            model: root._recentBadges
                            delegate: Item {
                                width: 34; height: 34
                                
                                Rectangle {
                                    width: 32; height: 32; radius: 4
                                    color: "#111"
                                    border.color: Theme.accent
                                    border.width: 1
                                    clip: true
                                    
                                    Image {
                                        anchors.fill: parent
                                        source: modelData.badgeName ? (modelData.badgeName.startsWith("http") ? modelData.badgeName : "https://media.retroachievements.org/Badge/" + modelData.badgeName + ".png") : ""
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                            }
                        }
                    }
                    
                    Text {
                        text: "❯"
                        color: Theme.accent
                        font.pixelSize: 16
                        opacity: cardMouse.containsMouse ? 1 : 0.4
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
            
            // Steam Achievement Card
            Rectangle {
                id: steamCard
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                Layout.topMargin: 5
                visible: root.gamePlatformType.toLowerCase() === "steam" && 
                         appSettings.steamId !== "" && appSettings.steamApiKey !== ""
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.05)
                border.color: steamCardMouse.containsMouse ? Theme.accent : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.3)
                border.width: 1
                radius: 8
                clip: true

                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: steamCardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        raOverlay.infoText = "Checking Steam Achievements..."
                        raOverlay.visible = true
                        root.refreshAchievements(false)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 15

                    // Icon / Progress Circle
                    Item {
                        width: 44; height: 44
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: 22
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            
                            Image {
                                anchors.centerIn: parent
                                source: "file://" + appInfo.getAssetsDir() + "/systems/steam.png"
                                width: 28; height: 28
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Steam Achievements"
                            color: Theme.accent
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Text {
                            text: root._steamAchievementsCount > 0 ? (root._steamAchievementsUnlocked + " / " + root._steamAchievementsCount + " Unlocked") : (root._steamAchievementsUnlocked > 0 ? (root._steamAchievementsUnlocked + " Unlocked") : "Click to check achievements")
                            color: Theme.text
                            font.pixelSize: 12
                            opacity: 0.8
                        }
                    }

                    // Badge Artwork Row
                    Row {
                        spacing: -8
                        Layout.alignment: Qt.AlignVCenter
                        visible: root._steamAchievementsUnlocked > 0
                        
                        Repeater {
                            model: root._steamRecentBadges
                            delegate: Item {
                                width: 34; height: 34
                                
                                Rectangle {
                                    width: 32; height: 32; radius: 4
                                    color: "#111"
                                    border.color: Theme.accent
                                    border.width: 1
                                    clip: true
                                    
                                    Image {
                                        anchors.fill: parent
                                        source: modelData.iconUrl !== "" ? modelData.iconUrl : "file://" + appInfo.getAssetsDir() + "/steam.png"
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                            }
                        }
                    }
                    
                    Text {
                        text: "❯"
                        color: Theme.accent
                        font.pixelSize: 16
                        opacity: steamCardMouse.containsMouse ? 1 : 0.4
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
            
            Text {
                text: "Played: " + root.gamePlayCount + " times\nTotal Time: " + root.formatTime(root.gameTotalTime)
                color: Theme.secondaryText
                font.pixelSize: 11
            }
        }
        
        // Action Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TheophanyButton {
                text: "PLAY"
                iconEmoji: "▶"
                primary: true
                Layout.fillWidth: true
                Layout.preferredHeight: 45
                focusPolicy: Qt.NoFocus
                loading: root.isLaunching
                enabled: !root.isLaunching
                tooltipText: root.isLaunching ? "Launching Game..." : "Launch " + root.gameTitle
                
                onClicked: {
                    root.triggerLaunchFeedback()
                    root.playRequested(root.gameId)
                }

                TheophanyButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: parent.height
                    visible: root.emulatorProfiles.length > 0
                    background: null
                    text: "▼"
                    onClicked: profileMenu.popup()
                    focusPolicy: Qt.NoFocus
                }
                
                Menu {
                    id: profileMenu
                    Repeater {
                        model: root.emulatorProfiles
                        MenuItem {
                            text: "Launch with " + modelData.name
                            onTriggered: {
                                gameModel.launchWithProfile(root.gameId, modelData.id)
                            }
                        }
                    }
                }
            }

            // PC Configuration Button
            TheophanyButton {
                visible: root.gamePlatformType.toLowerCase().includes("pc")
                text: "⚙️"
                Layout.preferredWidth: 45
                Layout.preferredHeight: 45
                focusPolicy: Qt.NoFocus
                onClicked: {
                    Window.window.openPcConfig(root.gameId, root.gameTitle, root.gamePlatformType)
                }
                
                TheophanyTooltip {
                    visible: parent.hovered
                    text: "PC Launch Configuration (Wine/Proton)"
                }
            }

            Button {
                id: editButton
                text: "✎"
                Layout.preferredWidth: 45
                Layout.preferredHeight: 45
                focusPolicy: Qt.NoFocus
                background: Rectangle { 
                    color: Theme.border
                    radius: 4 
                    border.color: parent.hovered ? Theme.accent : "transparent"
                }
                contentItem: Text { 
                    text: "✎"
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter 
                    verticalAlignment: Text.AlignVCenter 
                }
                onClicked: {
                    Window.window.openGameEdit(root.gameId, 1)
                }
                
                TheophanyTooltip {
                    visible: editButton.hovered
                    text: "Edit Game Properties"
                }
            }
            
            Button {
                id: favoriteButton
                text: "★"
                Layout.preferredWidth: 45
                Layout.preferredHeight: 45
                focusPolicy: Qt.NoFocus
                background: Rectangle { 
                    color: root.gameIsFavorite ? Theme.accent : Theme.border
                    radius: 4 
                    border.color: root.gameIsFavorite ? Qt.lighter(Theme.accent, 1.2) : "transparent"
                    border.width: root.gameIsFavorite ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 150 } }
                    
                    layer.enabled: root.gameIsFavorite
                    layer.effect: Glow {
                        color: Theme.accent
                        radius: 8
                        samples: 17
                        spread: 0.2
                    }
                }
                contentItem: Text { 
                    text: "★"
                    color: root.gameIsFavorite ? Theme.buttonText : Theme.secondaryText
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter 
                    verticalAlignment: Text.AlignVCenter 
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                onClicked: {
                    if (gameId !== "") {
                        gameModel.toggleFavorite(gameId)
                        root.gameIsFavorite = !root.gameIsFavorite
                    }
                }
                
                TheophanyTooltip {
                    visible: favoriteButton.hovered
                    text: root.gameIsFavorite ? "Remove from Favorites" : "Add to Favorites"
                }
            }
        }

        // Removed redundant bottom tags section

        // Resources Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Item {
                id: resourcesHoverArea
                Layout.fillWidth: true
                implicitHeight: resSectionLayout.height
                
                MouseArea {
                    id: resourcesMouseDetector
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
                
                ColumnLayout {
                    id: resSectionLayout
                    width: parent.width
                    spacing: 8
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Text {
                            text: "RESOURCES"
                            font.pixelSize: 10
                            font.bold: true
                            color: Theme.secondaryText
                            // Faint if empty, clear if populated, responsive to hover
                            property bool isHovered: resourcesMouseDetector.containsMouse || resEditMouseUI.containsMouse
                            opacity: root.gameResources.length > 0 ? 0.6 : (isHovered ? 0.4 : 0.1)
                            font.letterSpacing: 1
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        // Edit Button
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: resEditMouseUI.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : "transparent"
                            opacity: (resourcesMouseDetector.containsMouse || resEditMouseUI.containsMouse) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            
                            Text {
                                anchors.centerIn: parent
                                text: "✏️"
                                font.pixelSize: 12
                            }
                            
                            MouseArea {
                                id: resEditMouseUI
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    resourceManagerDialog.load(root.gameId)
                                    resourceManagerDialog.open()
                                }
                                
                                TheophanyTooltip {
                                    visible: resEditMouseUI.containsMouse
                                    text: "Edit External Resources"
                                }
                            }
                        }
                    }
                    
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.gameResources.length > 0
                        
                        Repeater {
                            model: root.gameResources
                            
                            Label {
                                height: 28
                                // Automatic width from text + padding
                                leftPadding: 16
                                rightPadding: 16
                                verticalAlignment: Text.AlignVCenter
                                
                                text: {
                                    var t = modelData.type.toLowerCase()
                                    var icon = "🔗"
                                    if (t.includes("wikipedia")) icon = "🌐"
                                    else if (t.includes("mobygames")) icon = "🎮"
                                    else if (t.includes("manual")) icon = "📄"
                                    else if (t.includes("video") || t.includes("trailer")) icon = "🎬"
                                    else if (modelData.url.startsWith("file://")) icon = "📁"
                                    
                                    var lbl = modelData.label ? modelData.label : (modelData.type.charAt(0).toUpperCase() + modelData.type.slice(1))
                                    return icon + "  " + lbl
                                }
                                
                                color: Theme.text
                                font.pixelSize: 12
                                font.bold: true
                                
                                background: Rectangle {
                                    radius: 14
                                    color: resHoverItem.containsMouse ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1)
                                    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.2)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                
                                MouseArea {
                                    id: resHoverItem
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {

                                        Qt.openUrlExternally(modelData.url)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Description
        TextArea {
            Layout.fillWidth: true
            text: root.gameDescription
            color: Theme.bodyText
            wrapMode: Text.Wrap
            readOnly: true
            background: null
            font.pixelSize: 14
        }

        }
    }

    // Bottom Toolbar
    Rectangle {
        id: bottomToolbar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 30
        color: Theme.secondaryBackground
        z: 10

        // Border top
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
            anchors.top: parent.top
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 15
            
            Item { Layout.fillWidth: true }

            // Video Manager Button
            Button {
                id: videoSearchButton
                text: "🎬 Search Videos"
                background: null
                focusPolicy: Qt.NoFocus
                contentItem: Text { 
                    text: parent.text
                    color: Theme.text
                    font.pixelSize: 12 
                }
                onClicked: {
                     Window.window.openVideoDownload(root.gameFilename, root.gameTitle, root.gamePlatform, root.gamePlatformType, root.platformFolder)
                }
                
                TheophanyTooltip {
                    visible: videoSearchButton.hovered
                    text: "Search for trailers and gameplay videos"
                }
            }
        }
    }
    
    property string fullRomPath: "" 
    
    // Achievements Overlay
    Rectangle {
        id: raOverlay
        anchors.fill: parent
        color: Theme.secondaryBackground
        opacity: 0.98
        visible: false
        z: 100
        
        focus: visible // Set focus to trap keys
        Keys.onEscapePressed: {
            visible = false
            Window.window.refocusList()
        }
        
        property string infoText: ""
        property int unlockedCount: 0
        property int totalCount: 0
        
        // Trap mouse (Background)
        MouseArea { 
            anchors.fill: parent 
            onClicked: {} // Block click-through
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15
            
            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    Label {
                        text: "Achievements"
                        color: Theme.accent
                        font.bold: true
                        font.pixelSize: 20
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: raOverlay.infoText
                        color: Theme.secondaryText
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    
                    Label {
                        text: "Progress: " + raOverlay.unlockedCount + " / " + raOverlay.totalCount
                        color: Theme.text
                        font.pixelSize: 12
                        font.bold: true
                        visible: raOverlay.totalCount > 0
                        Layout.fillWidth: true
                    }
                }
                
                TheophanyButton {
                    text: "✕"
                    tooltipText: "Close Overlay"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    onClicked: {
                        raOverlay.visible = false
                        Window.window.refocusList()
                    }
                }
            }
            
            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border 
            }
            
            // Achievement List
            ListView {
                id: achievementList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: ListModel { id: achievementModel }
                spacing: 8
                
                ScrollBar.vertical: TheophanyScrollBar { }
                
                delegate: Rectangle {
                    width: achievementList.width
                    height: 64
                    color: model.unlocked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1) : "transparent"
                    radius: 4
                    border.color: model.unlocked ? Theme.accent : Theme.border
                    border.width: model.unlocked ? 1 : 0
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12
                        
                        // Badge Image (Placeholder or Cache)
                        Rectangle {
                            width: 48
                            height: 48
                            color: Theme.background
                            border.color: Theme.border
                            
                            // Badge URL logic: RetroAchievements use /Badge/{BadgeName}.png, Steam provides full URL
                            Image {
                                anchors.fill: parent
                                source: model.badgeName ? (model.badgeName.startsWith("http") ? model.badgeName : "https://media.retroachievements.org/Badge/" + model.badgeName + ".png") : ""
                                fillMode: Image.PreserveAspectFit
                                opacity: model.unlocked ? 1.0 : 0.3
                            }
                            
                            // Locked Overlay
                             Text {
                                anchors.centerIn: parent
                                text: "🔒"
                                visible: !model.unlocked
                                font.pixelSize: 20
                            }
                        }
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            clip: true
                            
                            Label {
                                text: model.title
                                color: model.unlocked ? Theme.accent : Theme.secondaryText
                                font.bold: true
                                font.pixelSize: 14
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Label {
                                text: model.description
                                color: Theme.bodyText
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                        
                        Label {
                            text: model.points + " pts"
                            color: Theme.accent
                            font.bold: true
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
    
    property int achievementCount: 0
    property int achievementUnlocked: 0
    property var _recentBadges: []

    ResourceManagerDialog {
        id: resourceManagerDialog
        onResourcesChanged: root.checkImages() // Refresh
    }
    
    // Logic to parse JSON

    Connections {
        target: raBridge
        function onGameDataReady(json) {
             if (!appSettings.retroAchievementsEnabled) return;

             try {
                var data = JSON.parse(json)
                
                // CRITICAL: Verify this data is for the current game
                // The RA API response for game info usually has "ID" which matches the gameId we sent (if it's the numeric one)
                // However, our root.gameId might be a UUID if it's not matched yet.
                // The performance_ra_scrape in Rust returns JSON with Title, ID, etc.
                // Let's assume for now it's fine as long as we just requested it.
                // A better way would be to pass the UUID through the scrape and back.
                
                raOverlay.infoText = data.Title || "Unknown Game"
                
                // Reset Model
                achievementModel.clear()
                var unlocked = 0
                var total = 0
                
                if (data.Achievements) {
                    var list = []
                    // Convert Map to Array
                    for (var key in data.Achievements) {
                        var ach = data.Achievements[key]
                        // Check if unlocked: If "DateEarned" is present (non-null in JSON)
                        var isUnlocked = !!ach.DateEarned
                        list.push({
                            id: ach.ID,
                            title: ach.Title,
                            description: ach.Description,
                            points: ach.Points,
                            badgeName: ach.BadgeName,
                            unlocked: !!isUnlocked,
                            dateEarned: ach.DateEarned || ""
                        })
                        if (isUnlocked) unlocked++;
                    }
                    total = list.length
                    
                    // Sort: Unlocked first, then by ID? Or just ID? usually default order ID is fine.
                    list.sort((a,b) => a.id - b.id)
                    
                    for (var i=0; i<list.length; i++) {
                        achievementModel.append(list[i])
                    }

                    // Update Recent Badges
                    var earned = list.filter(a => a.unlocked)
                    earned.sort((a,b) => {
                        var dA = a.dateEarned ? new Date(a.dateEarned) : 0
                        var dB = b.dateEarned ? new Date(b.dateEarned) : 0
                        return dB - dA
                    })
                    root._recentBadges = earned.slice(0, 5)
                }
                
                raOverlay.unlockedCount = unlocked
                raOverlay.totalCount = total
                if (!root._silentRefresh) raOverlay.visible = true
                
                // Update Local UI
                root.achievementCount = total
                root.achievementUnlocked = unlocked
                
                // Persist to DB (Achievements ONLY to avoid overwriting metadata)
                var badgeNames = root._recentBadges.map(b => b.badgeName)
                gameModel.updateGameAchievements(root.gameId, total, unlocked, JSON.stringify(badgeNames))
                
                // CRITICAL: Refresh assets to pick up newly downloaded images
                gameModel.refreshGameAssets(root.gameId)
                
                // Extra trigger to ensure UI picks up changes
                Qt.callLater(() => {
                    if (typeof window !== "undefined" && window.loadGameDetails) {
                        var idx = gameModel.getRowById(root.gameId)
                        if (idx >= 0) window.loadGameDetails(idx)
                    }
                })
                
             } catch(e) {
                raOverlay.infoText = "Error parsing RA data: " + e
             }
        }
        function onErrorOccurred(msg) {
             if (!appSettings.retroAchievementsEnabled) return;
             raOverlay.infoText = "Error: " + msg
             raOverlay.visible = true
        }
    }
    
    // Glassmorphism border/effect (optional overlay)
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Theme.border
        border.width: 1
    }

    // Full Screen Image Viewer
    Popup {
        id: imageViewer
        anchors.centerIn: Overlay.overlay
        width: Overlay.overlay.width
        height: Overlay.overlay.height
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnClickOutside
        
        Shortcut {
            sequence: "Left"
            enabled: imageViewer.opened
            onActivated: prevImage()
        }
        
        Shortcut {
            sequence: "Right"
            enabled: imageViewer.opened
            onActivated: nextImage()
        }
        
        background: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.9)
        }

        Item {
            anchors.fill: parent
            
            Image {
                id: viewerImage
                anchors.fill: parent
                anchors.margins: 40
                source: (root.imageList && root.imageList.length > 0 && root.currentImageIndex < root.imageList.length && root.imageList[root.currentImageIndex]) ? root.imageList[root.currentImageIndex].url : root.boxArtSource
                fillMode: Image.PreserveAspectFit
                cache: false
                
                Behavior on source {
                    PropertyAnimation { duration: 300 }
                }
            }

            Label {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 20
                text: root.gameTitle + (root.imageList.length > 1 ? " (" + (root.currentImageIndex + 1) + " / " + root.imageList.length + ")" : "")
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }

            // Navigation Buttons
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 30
                spacing: 40
                visible: root.imageList.length > 1

                TheophanyButton {
                    text: "PREVIOUS"
                    onClicked: prevImage()
                }

                TheophanyButton {
                    text: "NEXT"
                    onClicked: nextImage()
                }
            }

            TheophanyButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                text: "CLOSE"
                onClicked: imageViewer.close()
            }
            
        }
    }

    function formatTime(seconds) {
        if (seconds < 0) return "--";
        if (seconds === 0) return "0h 0m";
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        return h + "h " + m + "m";
    }
}
