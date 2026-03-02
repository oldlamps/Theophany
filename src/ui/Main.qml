import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.platform as Platform
import Theophany.Bridge 1.0
import "components"
import "views"
import "dialogs"
import "style"

ApplicationWindow {
    id: window
    visible: true
    width: 1280
    height: 720
    title: "Theophany"
    color: Theme.background
    
    function tryQuit(force = false) {

        if (!force && appSettings.showTrayIcon && appSettings.closeToTray && window.visible) {
            window.hide()
            window.visible = false
            return
        }
        
        if (appSettings.confirmOnQuit) {
            quitConfirmDialog.open()
        } else {
            Qt.quit()
        }
    }

    onClosing: (close) => {
        close.accepted = false
        tryQuit()
    }
    
    // Grid Scaling
    property real gridScale: appSettings.gridScale
    property string assetDownloadStatus: "" // New status for non-blocking downloads
    property var rootViewStack: viewStack

    property var hotkeyMap: ({})
    property var pendingBulkScrapeIds: []

    function updateHotkeys() {
        try {
            if (appSettings.hotkeysJson && appSettings.hotkeysJson !== "") {
                var map = JSON.parse(appSettings.hotkeysJson)
                // Normalize "Return" which might be stored as "Enter" or vice versa if we aren't careful, 
                // but our default is "Return".
                window.hotkeyMap = map
            }
        } catch (e) {

        }
    }

    Connections {
        target: appSettings
        function onSettingsChanged() { updateHotkeys() }
    }

    // Mouse Navigation
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onPressed: (mouse) => {
            if (mouse.button === Qt.BackButton) {
                window.goBack();
                mouse.accepted = true;
            } else if (mouse.button === Qt.ForwardButton) {
                window.goForward();
                mouse.accepted = true;
            }
        }
        z: -1 // Behind all interactive elements but covers background
    }
    

    
    // Store Install Tracking Properties (Generic)
    property string storeInstallAppId: ""
    property real storeInstallProgress: 0.0
    property bool isStoreInstalling: false
    property string storeInstallStatus: ""
    property bool storeInstallPaused: false

    // Generic Background Activity (Separate from Store Installs)
    property string backgroundActivityId: ""
    property real backgroundActivityProgress: 0.0
    property string backgroundActivityStatus: ""
    property bool hasBackgroundActivity: false

    Shortcut {
        sequence: window.hotkeyMap["Settings"]
        onActivated: sidebar.settingsRequested()
    }

    Shortcut {
        sequence: window.hotkeyMap["Quit"]
        onActivated: window.tryQuit(true)
    }

    Shortcut {
        sequence: window.hotkeyMap["Refresh"]
        onActivated: gameModel.refresh()
    }

    Shortcut {
        sequence: window.hotkeyMap["Search"]
        onActivated: {
            window.searchActive = true
            // Ensure visibility is updated before focusing
            Qt.callLater(function() {
                searchField.forceActiveFocus()
            })
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["CycleNext"] || "Ctrl+Tab"
        onActivated: sidebar.nextPlatform()
    }

    Shortcut {
        sequence: window.hotkeyMap["CyclePrev"] || "Ctrl+Shift+Tab"
        onActivated: sidebar.prevPlatform()
    }

    Shortcut {
        sequence: window.hotkeyMap["Launch"] || "Return"
        onActivated: {
            if (viewStack.currentIndex === 0) {
                if (gameGrid.currentIndex >= 0) {
                    var id = gameModel.getGameId(gameGrid.currentIndex)
                    window.launchGame(id)
                }
            } else {
                if (gameList.currentIndex >= 0) {
                    var id = gameModel.getGameId(gameList.currentIndex)
                    window.launchGame(id)
                }
            }
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["Edit"] || "E"
        onActivated: {
            if (viewStack.currentIndex === 0) {
                if (gameGrid.currentIndex >= 0) window.openGameEdit(gameModel.getGameId(gameGrid.currentIndex), 1)
            } else {
                if (gameList.currentIndex >= 0) window.openGameEdit(gameModel.getGameId(gameList.currentIndex), 1)
            }
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["VideoExplorer"]
        onActivated: {
            var index = (viewStack.currentIndex === 0) ? gameGrid.currentIndex : gameList.currentIndex;
            if (index >= 0) {
                // Ensure details are loaded for this index to get platformFolder etc.
                if (detailsPanel.gameId !== gameModel.getGameId(index)) {
                     window.loadGameDetails(index);
                }
                window.openVideoDownload(
                    detailsPanel.gameFilename, 
                    detailsPanel.gameTitle, 
                    detailsPanel.gamePlatform, 
                    detailsPanel.gamePlatformType,
                    detailsPanel.platformFolder
                );
            }
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["ImageViewer"]
        onActivated: detailsPanel.openImageViewer()
    }

    Shortcut {
        sequence: window.hotkeyMap["FilterBar"]
        onActivated: window.showFilterBar = !window.showFilterBar
    }

    Shortcut {
        sequence: window.hotkeyMap["ToggleSidebar"]
        onActivated: sidebar.collapsed = !sidebar.collapsed
    }



    Shortcut {
        sequence: window.hotkeyMap["Escape"]
        enabled: window.showFilterBar
        onActivated: window.showFilterBar = false
    }

    Shortcut {
        sequence: window.hotkeyMap["ScrapeManual"]
        onActivated: {
            var index = (viewStack.currentIndex === 0) ? gameGrid.currentIndex : gameList.currentIndex;
            if (index >= 0) {
                 var id = gameModel.getGameId(index);
                 // We need the title too for default search query
                 // We can get it from detailsPanel if it matches, or query model
                 // 257 = TitleRole, 260 = PlatformNameRole, 261 = PlatformTypeRole
                 var title = detailsPanel.gameId === id ? detailsPanel.gameTitle : gameModel.data(gameModel.index(index, 0), 257);
                 var platformType = detailsPanel.gameId === id ? detailsPanel.gamePlatformType : gameModel.data(gameModel.index(index, 0), 261);
                 var platformName = detailsPanel.gameId === id ? detailsPanel.gamePlatform : gameModel.data(gameModel.index(index, 0), 260);
                 
                 mainScrapeDialog.gameId = id
                 mainScrapeDialog.query = title
                 mainScrapeDialog.platform = (platformType && platformType !== "--") ? platformType : ((platformName && platformName !== "--") ? platformName : "")
                 mainScrapeDialog.targetCategory = "Box - Front" // Default
                 mainScrapeDialog.currentTab = 0 
                 
                 mainScrapeDialog.open()
            }
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["ScrapeAuto"]
        onActivated: {
            // Priority to multi-selection in List view or Grid View
            if (viewStack.currentIndex === 1 && gameList.selectedIndices && gameList.selectedIndices.length > 1) {
                var ids = []
                for (var i = 0; i < gameList.selectedIndices.length; i++) {
                    ids.push(gameModel.getGameId(gameList.selectedIndices[i]))
                }
                window.openBulkScrape(ids, "Metadata")
                return
            } else if (viewStack.currentIndex === 0 && viewStack.sharedSelectedIndices && viewStack.sharedSelectedIndices.length > 1) {
                 var ids = []
                 for (var i = 0; i < viewStack.sharedSelectedIndices.length; i++) {
                     ids.push(gameModel.getGameId(viewStack.sharedSelectedIndices[i]))
                 }
                 window.openBulkScrape(ids, "Metadata")
                 return
            }

            var index = (viewStack.currentIndex === 0) ? gameGrid.currentIndex : gameList.currentIndex;
            if (index >= 0) {
                 var id = gameModel.getGameId(index);
                 var title = detailsPanel.gameId === id ? detailsPanel.gameTitle : gameModel.data(gameModel.index(index, 0), 257);
                 var platformType = detailsPanel.gameId === id ? detailsPanel.gamePlatformType : gameModel.data(gameModel.index(index, 0), 261);
                 var platformName = detailsPanel.gameId === id ? detailsPanel.gamePlatform : gameModel.data(gameModel.index(index, 0), 260);
                 
                 // Store ID in the dialog for context, even though we aren't opening it yet
                 mainScrapeDialog.gameId = id
                 mainScrapeDialog.query = title
                  mainScrapeDialog.platform = (platformType && platformType !== "--") ? platformType : ((platformName && platformName !== "--") ? platformName : "")
                 
                 gameModel.autoScrape(id)
            }
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["Achievements"]
        onActivated: {
            // Priority to multi-selection in List view or Grid View
            if (viewStack.currentIndex === 1 && gameList.selectedIndices && gameList.selectedIndices.length > 1) {
                var d_ids = []
                for (var j = 0; j < gameList.selectedIndices.length; j++) {
                    d_ids.push(gameModel.getGameId(gameList.selectedIndices[j]))
                }
                window.openBulkScrape(d_ids, "RetroAchievements")
                return
            } else if (viewStack.currentIndex === 0 && viewStack.sharedSelectedIndices && viewStack.sharedSelectedIndices.length > 1) {
                 var d_ids = []
                 for (var j = 0; j < viewStack.sharedSelectedIndices.length; j++) {
                     d_ids.push(gameModel.getGameId(viewStack.sharedSelectedIndices[j]))
                 }
                 window.openBulkScrape(d_ids, "RetroAchievements")
                 return
            }

            var index = (viewStack.currentIndex === 0) ? gameGrid.currentIndex : gameList.currentIndex;
            if (index >= 0 && !detailsPanel.gamePlatformType.includes("PC")) {

                detailsPanel.refreshAchievements(true)
            }
        }
    }


    // --- Centralized Navigation Shortcuts ---
    
    function navigateLetter(direction) {
        // direction: 1 for next, -1 for prev
        var view = (viewStack.currentIndex === 0) ? gameGrid : gameList
        if (!view || !view.visible) return

        var currentIdx = view.currentIndex
        var nextIdx = -1
        
        if (direction === 1) {
            nextIdx = gameModel.findNextLetter(currentIdx)
        } else {
            nextIdx = gameModel.findPrevLetter(currentIdx)
        }

        if (nextIdx !== -1) {
            view.currentIndex = nextIdx
            // Force scroll to position (User requested Center)
            view.positionViewAtIndex(nextIdx, (viewStack.currentIndex === 0) ? GridView.Center : ListView.Center)
            showNavOSD(gameModel.getLetterAt(nextIdx))
        }
    }

    function navigateHome() {
        var view = (viewStack.currentIndex === 0) ? gameGrid : gameList
        if (!view || !view.visible) return
        view.currentIndex = 0
        view.positionViewAtIndex(0, (viewStack.currentIndex === 0) ? GridView.Beginning : ListView.Beginning)
    }

    function navigateEnd() {
        var view = (viewStack.currentIndex === 0) ? gameGrid : gameList
        if (!view || !view.visible) return
        var max = view.count - 1
        view.currentIndex = max
        view.positionViewAtIndex(max, (viewStack.currentIndex === 0) ? GridView.End : ListView.End)
    }
    
    // Standard paging (custom +/- 10 entries)
    function navigatePage(direction) {
        // direction: 1 for next (down), -1 for prev (up)
        var view = (viewStack.currentIndex === 0) ? gameGrid : gameList
        if (!view || !view.visible) return

        var jumpSize = 10
        var currentIdx = view.currentIndex
        var newIdx = currentIdx + (direction * jumpSize)
        
        // Clamp
        if (newIdx < 0) newIdx = 0
        if (newIdx >= view.count) newIdx = view.count - 1
        
        if (newIdx !== currentIdx) {
            view.currentIndex = newIdx
            view.positionViewAtIndex(newIdx, (viewStack.currentIndex === 0) ? GridView.Contain : ListView.Contain)
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["Home"]
        onActivated: navigateHome()
    }
    
    Shortcut {
        sequence: window.hotkeyMap["End"]
        onActivated: navigateEnd()
    }

    Shortcut {
        sequence: window.hotkeyMap["NextLetter"]
        onActivated: navigateLetter(1)
    }

    Shortcut {
        sequence: window.hotkeyMap["PrevLetter"]
        onActivated: navigateLetter(-1)
    }

    Shortcut {
        sequence: window.hotkeyMap["PageDown"]
        onActivated: navigatePage(1)
    }

    Shortcut {
        sequence: window.hotkeyMap["PageUp"]
        onActivated: navigatePage(-1)
    }

    Shortcut {
        sequence: window.hotkeyMap["Back"]
        onActivated: window.goBack()
    }

    // Consolidate second back shortcut if not handled by multiple entries in sequence
    // For now we removed the separate Alt+Left Shortcut to rely on the map
    // Shortcut { sequence: "Alt+Left" ... } -> Removed/Merged conceptually


    Shortcut {
        sequence: window.hotkeyMap["Forward"]
        onActivated: window.goForward()
    }
    
    // Global OSD Overlay
    Rectangle {
        id: globalNavOSD
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 120
        height: 120
        radius: 12
        color: "#aa000000"
        opacity: 0
        visible: opacity > 0
        z: 1000 // Very high
        
        Text {
            anchors.centerIn: parent
            text: globalNavOSD.letter
            color: "white"
            font.pixelSize: 64
            font.bold: true
            style: Text.Outline
            styleColor: "black"
        }
        
        property string letter: ""
        
        Behavior on opacity { NumberAnimation { duration: 250 } }
        
        Timer {
            id: globalOsdTimer
            interval: 800
            onTriggered: globalNavOSD.opacity = 0
        }
    }

    function showNavOSD(letterStr) {
        globalNavOSD.letter = letterStr
        globalNavOSD.opacity = 1
        globalOsdTimer.restart()
    }
    
    property string globalBackgroundSource: ""
    property string currentViewTitle: "All Games"
    property string currentPlatformIcon: "🎮"
    property bool showFilterBar: false
    
    property var raUserSummary: null
    property bool raSummaryError: false
    property string raProfilePic: ""
    
    property string currentPlatformId: ""
    property var platformSelectionCache: ({})
    property string pendingSelectionId: ""  // Robust Async Restoration
    property bool isJumping: false
    property bool searchActive: false
    
    onShowFilterBarChanged: {
        if (!showFilterBar) {
            if (viewStack.currentIndex === 0) gameGrid.forceActiveFocus()
            else gameList.forceActiveFocus()
        }
    }
    
    // Ticker Stats
    property int statTotalGames: 0
    property int statTotalLibraryCount: 0
    property string statTotalTime: "--"
    property string statLastPlayed: "--"
    property string statLastPlayedId: ""
    property string upNextTitle: ""
    property string upNextId: ""
    
    onStatLastPlayedIdChanged: {
        refreshUpNext()
    }
    
    // --- Navigation History ---
    property var historyStack: []
    property int historyIndex: -1
    property bool isNavigatingHistory: false

    property var trayRecentGames: []
    function refreshTrayRecentGames() {
        if (!gameModel) return
        var json = gameModel.getRecentGamesJSON(5)
        try {
            window.trayRecentGames = JSON.parse(json)
        } catch(e) {

            window.trayRecentGames = []
        }
    }

    function pushHistory(type, id, name, icon) {
        if (isNavigatingHistory) return;

        var newItem = { type: type, id: id, name: name, icon: icon };

        // Don't push if it's the same as current
        if (historyIndex >= 0) {
            var current = historyStack[historyIndex];
            if (current.type === type && current.id === id) return;
        }

        // Clear future history if we were in a back state
        if (historyIndex < historyStack.length - 1) {
            historyStack.splice(historyIndex + 1);
        }

        historyStack.push(newItem);
        // Limit history size
        if (historyStack.length > 50) historyStack.shift();
        else historyIndex++;
    }

    function goBack() {
        if (historyIndex > 0) {
            historyIndex--;
            applyHistoryItem(historyStack[historyIndex]);
        }
    }

    function goForward() {
        if (historyIndex < historyStack.length - 1) {
            historyIndex++;
            applyHistoryItem(historyStack[historyIndex]);
        }
    }

    function applyHistoryItem(item) {
        isNavigatingHistory = true;
        if (item.type === "platformType") {
            sidebar.activeViewType = "platformType"
            sidebar.activeId = item.id
            sidebar.platformTypeSelected(item.id)
        } else {
            // covers all, favorites, recent, platform, playlist
            var viewType = item.type;
            if (viewType === "playlist") {
                 sidebar.activeViewType = "playlist"
                 sidebar.activeId = item.id
                 sidebar.platformSelected("playlist:" + item.id, item.name, item.icon)
            } else if (viewType === "platform") {
                 sidebar.activeViewType = "platform"
                 sidebar.activeId = item.id
                 sidebar.platformSelected(item.id, item.name, item.icon)
            } else {
                 sidebar.activeViewType = viewType
                 sidebar.activeId = item.id
                 sidebar.platformSelected(item.id, item.name, item.icon)
            }
        }
        isNavigatingHistory = false;
    }
    
    function refreshUpNext() {
        var json = gameModel.getUpNextSuggestion(window.statLastPlayedId)
        try {
            var data = JSON.parse(json)
            window.upNextTitle = data.title || ""
            window.upNextId = data.id || ""
        } catch (e) {
            window.upNextTitle = ""
            window.upNextId = ""
        }
    }
    property string deleteGameId: ""
    property string deleteGameTitle: ""
    property var deleteGameIds: []
    property string deleteCollectionId: ""
    property string deleteCollectionName: ""

    property alias appSettingsRef: appSettings

    AppSettings {
        id: appSettings
        Component.onCompleted: {
            load()
            // Apply defaults on load
            viewStack.currentIndex = defaultView
            window.showFilterBar = showFilterBar
            
            // Apply Theme
            if (themeName && themeName !== "") {
                Theme.setTheme(themeName)
            }
            
            // Region logic
            updateHotkeys()
            
            // Auto Rescan
            if (autoRescanOnStartup) {

                gameModel.refresh()
            }
        }
    }

    // Listen for settings changes to apply defaults (handles late load or runtime changes)
    Connections {
        target: appSettings
        function onSettingsChanged() {
             var defRegion = appSettings.defaultRegion
             if (defRegion !== "" && defRegion !== "All Regions") {
                  // Ensure model is ready (it should be if app is running)
                  gameModel.setRegionFilter(defRegion)
                  filterBar.selectRegion(defRegion)
              }
        }
    }


    // One-shot timer to ensure RA connects on startup (avoids too-early / too-spamous checks)
    Timer {
        id: startupRaTimer
        interval: 1000 
        repeat: false
        running: true
        onTriggered: {
            if (appSettings.retroAchievementsEnabled && appSettings.retroAchievementsUser !== "" && !window.raUserSummary) {

                 raBridge.fetchUserSummary(appSettings.retroAchievementsUser, appSettings.retroAchievementsToken)
            }
        }
    }

    Component.onCompleted: {
        // First Run Experience
        if (!appSettings.settingsExist()) {
            firstRunWizard.open()
        }

        // Keep this as immediate check, timer acts as safety fallback
        if (appSettings.retroAchievementsEnabled && appSettings.retroAchievementsUser !== "") {
            raBridge.fetchUserSummary(appSettings.retroAchievementsUser, appSettings.retroAchievementsToken)
        }
        
        if (appSettings.checkForUpdatesOnStartup) {
            rootAppInfo.checkForUpdates()
        }

        updateHotkeys()
    }

    PlaylistModel {
        id: playlistModel
        Component.onCompleted: init(appInfo.getDataPath() + "/games.db")
    }

    RetroAchievements {
        id: raBridge
        onUserSummaryReady: (json) => {
            window.raSummaryError = false
            try {
                var data = JSON.parse(json)
                window.raUserSummary = data
                if (data.UserPic) {
                    window.raProfilePic = "https://media.retroachievements.org" + data.UserPic
                }
            } catch(e) {

            }
        }
        onLoginSuccess: (user) => {
            window.raSummaryError = false
            if (appSettings.retroAchievementsEnabled) {
                raBridge.fetchUserSummary(user, appSettings.retroAchievementsToken)
            }
        }
        onErrorOccurred: (msg) => {
            // Set error state when RA summary fetch fails
            if (msg.includes("user summary")) {
                window.raSummaryError = true
            }
        }
    }

    Timer {
        id: globalRaPollTimer
        interval: 100
        repeat: true
        running: true
        onTriggered: raBridge.poll()
    }

    GlobalSearchDialog {
        id: globalSearchDialog
        onLaunchRequested: (romId) => {
             gameModel.launchGame(romId)
        }
        onGameSelected: (romId) => {
             window.jumpToGame(romId)
        }
        onCollectionSelected: (collectionId) => {
            sidebar.selectPlatform(collectionId)
        }
        onPlaylistSelected: (playlistId) => {
            sidebar.selectPlaylist(playlistId)
        }
    }

    Shortcut {
        sequence: window.hotkeyMap["GlobalSearch"]
        onActivated: globalSearchDialog.show()
    }

    // Disabled: 5-minute auto-refresh is not necessary
    // Timer {
    //     id: raSummaryRefreshTimer
    //     interval: 300000 // 5 minutes
    //     repeat: true
    //     running: appSettings.retroAchievementsEnabled && appSettings.retroAchievementsUser !== ""
    //     onTriggered: {
    //         if (appSettings.retroAchievementsEnabled && appSettings.retroAchievementsUser !== "") {
    //             raBridge.fetchUserSummary(appSettings.retroAchievementsUser, appSettings.retroAchievementsToken)
    //         }
    //     }
    // }

    function refocusList() {
        if (viewStack.currentIndex === 0) gameGrid.forceActiveFocus()
        else gameList.forceActiveFocus()
    }

    StoreBridge {
        id: storeBridge
        
        onInstallProgress: (appId, progress, status) => {
            if (appId === "exodos" || appId === "Artwork") {
                window.backgroundActivityId = appId
                window.backgroundActivityProgress = progress
                window.backgroundActivityStatus = status
                window.hasBackgroundActivity = true
            } else {
                window.storeInstallAppId = appId
                window.storeInstallProgress = progress
                window.isStoreInstalling = true
                window.storeInstallStatus = status
            }
        }
        
        onInstallFinished: (appId, success, message) => {
            // 1. Cleanup state tracking
            if (appId === "exodos" || appId === "Artwork") {
                window.hasBackgroundActivity = false
            } else if (appId !== "exodos_immediate" && appId !== "exodos_batch") {
                window.isStoreInstalling = false
            }
            
            // 2. Handle refresh and details update on success
            if (success) {
                gameModel.refresh()
                
                // Specific updates for finished installs/imports
                if (appId !== "exodos_batch" && appId !== "exodos_immediate") {
                    window.storeInstallStatus = message
                    if (detailsPanel.gameId.includes(appId)) {
                        var idx = gameModel.getRowById(detailsPanel.gameId)
                        if (idx >= 0) window.loadGameDetails(idx)
                    }
                }
            } else {
                // Ignore manual cancellations
                if (message === "Cancelled") return;

                // 3. Show error dialog (Ignore for background batch updates)
                if (appId !== "exodos_batch") {
                    window.storeInstallStatus = message
                    mainAutoScrapeErrorDialog.text = "Installation Failed: " + message
                    mainAutoScrapeErrorDialog.open()
                }
            }
        }
    }

    function importEpicGame(id) {
        if (!id) return
        var path = ""
        var idx = gameModel.getRowById(id)
        if (idx >= 0) {
            path = gameModel.data(gameModel.index(idx, 0), 258) // PathRole
        }
        
        if (path.startsWith("epic://")) {
            var appName = path.split("/").pop()
            if (appName) {
                epicImportPathDialog.pendingAppId = appName
                epicImportPathDialog.open()
            }
        }
    }

    function launchGame(id) {
        if (!id) return
        
        // Handle Legendary Installation Trigger
        var path = ""
        var isInstalled = true
        var idx = gameModel.getRowById(id)
        if (idx >= 0) {
            path = gameModel.data(gameModel.index(idx, 0), 258) // PathRole
            var metaJson = gameModel.getGameMetadata(id)
            try {
                var meta = JSON.parse(metaJson)
                isInstalled = (typeof meta.is_installed !== "undefined") ? meta.is_installed : true
            } catch(e) {}
        }
        
        if (path.startsWith("epic://") && !isInstalled) {
            // Correct App ID extraction for epic://launch/AppId
            var appName = path.split("/").pop()
            if (appName) {
                epicInstallPathDialog.pendingAppId = appName
                epicInstallPathDialog.open()
                return
            }
        }

        gameModel.launchGame(id)
        if (detailsPanel) detailsPanel.triggerLaunchFeedback()
    }

    function loadGameDetails(index) {
        if (index < 0 || index >= gameModel.rowCount()) return;
        var id = gameModel.getGameId(index);

        
        var json = gameModel.getGameMetadata(id);

        
        try {
            var data = JSON.parse(json);
            // Populate details panel
            detailsPanel.gameId = id // Assuming 'id' is the romId
            detailsPanel.fullRomPath = gameModel.data(gameModel.index(index, 0), 258) // Role 258 = Path
            detailsPanel.platformFolder = gameModel.data(gameModel.index(index, 0), 265)
            detailsPanel.gameTitle = data.title || gameModel.data(gameModel.index(index, 0), 257) // Fallback to titleRole
            detailsPanel.gamePlatform = gameModel.data(gameModel.index(index, 0), 260) || "--"
            detailsPanel.gamePlatformType = gameModel.data(gameModel.index(index, 0), 261) || ""
            detailsPanel.gamePlatformIcon = gameModel.data(gameModel.index(index, 0), 266) || ""
            detailsPanel.gameIcon = gameModel.data(gameModel.index(index, 0), 274) || ""
            detailsPanel.gameDescription = data.description || "No description available."
            detailsPanel.gameDeveloper = data.developer || "--"
            detailsPanel.gamePublisher = data.publisher || "--"
            detailsPanel.gameGenre = data.genre || "--"
            detailsPanel.gameRegion = data.region || ""
            detailsPanel.gamePlayCount = data.play_count || 0
            detailsPanel.gameLastPlayed = data.last_played || 0
            detailsPanel.gameTotalTime = data.total_play_time || 0
            detailsPanel.gameTags = data.tags || ""
            detailsPanel.gameRating = data.rating || 0.0
            if (data.release_date && data.release_date !== "") {
                detailsPanel.gameReleaseDate = data.release_date
            } else {
                detailsPanel.gameReleaseDate = ""
            }
            detailsPanel.gamePlatformId = gameModel.data(gameModel.index(index, 0), 264)
            detailsPanel.gamePlatformType = data.platform_type || "Unknown Platform"
            detailsPanel.gamePlatformId = data.platform_id || ""
            
            detailsPanel.gameIsFavorite = data.is_favorite || false
            detailsPanel.gameIsInstalled = (typeof data.is_installed !== "undefined") ? data.is_installed : (detailsPanel.gamePlatformType.toLowerCase() !== "steam" && detailsPanel.gamePlatformId.toLowerCase() !== "epic")
            detailsPanel.achievementCount = data.achievement_count || 0
            detailsPanel.achievementUnlocked = data.achievement_unlocked || 0
            if (data.ra_recent_badges) {
                try {
                    var badges = JSON.parse(data.ra_recent_badges)
                    var wrapped = []
                    for (var i=0; i<badges.length; i++) {
                        wrapped.push({ "badgeName": badges[i] })
                    }
                    detailsPanel._recentBadges = wrapped
                } catch(e) { detailsPanel._recentBadges = [] }
            } else {
                detailsPanel._recentBadges = []
            }
            
            if (data.assets) {
                if (data.assets["Box - Front"] && data.assets["Box - Front"].length > 0) 
                    detailsPanel.boxArtSource = "file://" + data.assets["Box - Front"][0]
                else detailsPanel.boxArtSource = ""
                
                if (data.assets["Banner"] && data.assets["Banner"].length > 0) 
                    detailsPanel.bannerSource = "file://" + data.assets["Banner"][0]
                else detailsPanel.bannerSource = ""
                
                if (data.assets["Background"] && data.assets["Background"].length > 0) {
                    var bgs = data.assets["Background"]
                    window.globalBackgroundSource = "file://" + bgs[Math.floor(Math.random() * bgs.length)]
                }
                else {
                    var bg = gameModel.data(gameModel.index(index, 0), 275) || ""
                    window.globalBackgroundSource = bg
                }
            } else {
                 detailsPanel.boxArtSource = ""
                 detailsPanel.bannerSource = ""
                 var bg2 = gameModel.data(gameModel.index(index, 0), 275) || ""
                 window.globalBackgroundSource = bg2
            }

            detailsPanel.updateImageList(data)
            detailsPanel.updateResources(data)

            // Filename for video download (stem only)
            var fullFilename = gameModel.data(gameModel.index(index, 0), 263) || ""
            if (fullFilename !== "") {
                var lastDotIndex = fullFilename.lastIndexOf('.')
                if (lastDotIndex > 0) {
                     detailsPanel.gameFilename = fullFilename.substring(0, lastDotIndex)
                } else {
                     detailsPanel.gameFilename = fullFilename
                }
            } else {
                detailsPanel.gameFilename = id // Fallback to ID if filename missing
            }
        } catch (e) {

        }
    }

    function selectGame(index, positionMode) {
        if (index < 0 || index >= gameModel.rowCount()) return;
        
        // Use Contain by default for less intrusive behavior
        var mode = (positionMode !== undefined) ? positionMode : ((viewStack.currentIndex === 0) ? GridView.Contain : ListView.Contain)
        
        // 1. Update Grid
        gameGrid.currentIndex = index
        
        // 2. Update List
        gameList.currentIndex = index
        
        // 3. Ensure visible
        if (viewStack.currentIndex === 0) {
            gameGrid.positionViewAtIndex(index, mode)
        } else {
            gameList.positionViewAtIndex(index, mode)
        }
        
        // 4. Load Details
        loadGameDetails(index)
    }

    function jumpToGame(romId) {
        if (!romId || romId === "") return
        
        var json = gameModel.getGameMetadata(romId)
        try {
            var data = JSON.parse(json)
            var pid = data.platform_id || ""
            
            // Pre-cache
            platformSelectionCache[pid] = romId
            
            if (currentPlatformId !== pid) {
                // Trigger the actual sidebar selection to update filters
                sidebar.selectPlatform(pid)
                jumpTimer.targetId = romId
                jumpTimer.start()
            } else {
                // Already on the right platform
                var idx = gameModel.getRowById(romId)
                if (idx >= 0) selectGame(idx)
            }
        } catch (e) {

        }
    }

    Timer {
        id: jumpTimer
        interval: 150
        repeat: false
        property string targetId: ""
        onTriggered: {
            var idx = gameModel.getRowById(targetId)
            if (idx >= 0) {
                selectGame(idx)
                // Second pass to ensure scroll settled
                Qt.callLater(() => {
                    var idx2 = gameModel.getRowById(targetId)
                    if (idx2 >= 0) selectGame(idx2)
                })
            }
            isJumping = false
        }
    }

    // Dynamic Background
    Rectangle {
        id: bgRoot
        anchors.fill: parent
        color: Theme.background
        
        // Base Gradient
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.background }
                GradientStop { position: 1.0; color: Theme.secondaryBackground }
            }
        }

        Item {
            id: crossFadeManager
            anchors.fill: parent
            
            property string currentSource: window.globalBackgroundSource
            onCurrentSourceChanged: {
                if (bgImage1.opacity === 1) {
                    bgImage2.source = currentSource
                    bgImage2.opacity = currentSource !== "" ? 1.0 : 0.0
                    bgImage1.opacity = 0
                } else {
                    bgImage1.source = currentSource
                    bgImage1.opacity = currentSource !== "" ? 1.0 : 0.0
                    bgImage2.opacity = 0
                }
            }

            Image {
                id: bgImage1
                anchors.fill: parent
                source: ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 600 } }
                visible: opacity > 0
            }

            Image {
                id: bgImage2
                anchors.fill: parent
                source: ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 600 } }
                visible: opacity > 0
            }
        }
        
        // Darkening Overlay (Top of images)
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            opacity: 0.75
        }
        
        // Ensure initial state if a background is already set on launch
        Component.onCompleted: {
            if (window.globalBackgroundSource !== "") {
                bgImage1.source = window.globalBackgroundSource
                bgImage1.opacity = 1.0
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // LEFT PANE (Sidebar + AI)
        Item {
            id: sidebarContainer
            Layout.preferredWidth: sidebar.collapsed ? 64 : appSettings.sidebarWidth
            Layout.fillHeight: true
            
            Behavior on Layout.preferredWidth { 
                enabled: !sidebarResizer.pressed && !sidebar.collapsed
                NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } 
            }
            
            Sidebar {
                id: sidebar
                allGamesCount: window.statTotalLibraryCount
                appSettings: appSettings
                appSettingsRef: appSettings
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                
                onAddSystemClicked: addSystemDialog.openAdd()
                onManagePlaylistsRequested: playlistManagerDialog.open()
                onAddContentRequested: {
                    addContentDialog.isFolderMode = true
                    addContentDialog.isNewMode = false
                    addContentDialog.open()
                }
                onAddContentToCollectionRequested: (platformId) => {
                    addContentDialog.isFolderMode = true
                    addContentDialog.isNewMode = false
                    var idx = sidebar.platformModel.getRowById(platformId)
                    if (idx >= 0) {
                        addContentDialog.existingCollectionIndex = idx
                    }
                    addContentDialog.open()
                }
                onManageEmulatorsClicked: emulatorManager.open()
                onDeleteCollectionRequested: (pid, name) => {
                    window.deleteCollectionId = pid
                    window.deleteCollectionName = name
                    deleteCollectionDialog.open()
                }
                onPlatformSelected: (pid, name, icon) => {

                    
                    // 1. Save current selection for the OUTGOING platform
                    if (detailsPanel.gameId !== "") {
                        platformSelectionCache[currentPlatformId] = detailsPanel.gameId

                    }

                    // 2. Switch Platform
                    currentPlatformId = pid
                    window.currentViewTitle = name
                    window.currentPlatformIcon = icon

                    var historyType = pid === "" ? "all" : (pid === "favorites" ? "favorites" : (pid === "recent" ? "recent" : (pid.startsWith("playlist:") ? "playlist" : "platform")));
                    var historyId = pid.startsWith("playlist:") ? pid.substring(9) : pid;
                    pushHistory(historyType, historyId, name, icon);

                    if (pid.startsWith("playlist:")) {
                        var realId = pid.substring(9)
                        gameModel.setPlaylistFilter(realId)
                        // Do NOT call batchSetFilters here - setPlaylistFilter already handles refresh
                    } else if (pid === "favorites") {
                        gameModel.batchSetFilters("", true, gameModel.sortMethod, false, filterBar.installedButton.checked)
                    } else if (pid === "recent") {
                        gameModel.batchSetFilters("", false, "LastPlayed", true, filterBar.installedButton.checked)
                    } else if (pid === "") { // All Games
                        gameModel.batchSetFilters("", false, gameModel.sortMethod, false, filterBar.installedButton.checked)
                    } else { // System UUID
                        gameModel.batchSetFilters(pid, false, gameModel.sortMethod, false, filterBar.installedButton.checked)
                    }
                    
                    // 3. Queue selection restoration for the INCOMING platform
                    pendingSelectionId = platformSelectionCache[pid] || ""
                }
                onEditSystemRequested: (id, name, ext, cmd, emuId, pType, icon, pcConfig) => {
                    addSystemDialog.openEdit(id, name, ext, cmd, emuId, pType, icon, pcConfig)
                }
                onSystemDeleted: {
                    // Ensure game grid updates to remove games from deleted system
                    gameModel.refresh()
                }
                onRescanRequested: (pid) => {
                    gameModel.rescanSystem(pid)
                }
                onSettingsRequested: {
                     settingsDialog.availableRegions = gameModel.getRegions()
                     settingsDialog.currentViewMode = appSettings.defaultView
                     settingsDialog.currentShowFilterBar = appSettings.showFilterBar
                     settingsDialog.currentDefaultRegion = appSettings.defaultRegion
                     settingsDialog.currentTheme = appSettings.themeName
                     
                     settingsDialog.currentRaUser = appSettings.retroAchievementsUser
                     settingsDialog.currentRaToken = appSettings.retroAchievementsToken
                     settingsDialog.currentRaEnabled = appSettings.retroAchievementsEnabled
                     
                     settingsDialog.currentShowTrayIcon = appSettings.showTrayIcon
                     settingsDialog.currentCloseToTray = appSettings.closeToTray
                     
                     settingsDialog.currentAiEnabled = appSettings.aiEnabled
                     settingsDialog.currentOllamaUrl = appSettings.ollamaUrl
                     settingsDialog.currentOllamaModel = appSettings.ollamaModel
                     settingsDialog.currentAiDescriptionPrompt = appSettings.aiDescriptionPrompt
                     
                     settingsDialog.currentDetailsPreferVideo = appSettings.detailsPreferVideo
                     settingsDialog.currentIgnoreTheInSort = appSettings.ignoreTheInSort
                     settingsDialog.currentDefaultIgnoreOnDelete = appSettings.defaultIgnoreOnDelete
                     settingsDialog.currentActiveMeta = appSettings.activeMetadataScraper
                     settingsDialog.currentActiveImage = appSettings.activeImageScraper
                     
                     settingsDialog.currentGeminiKey = appSettings.geminiApiKey
                     settingsDialog.currentOpenaiKey = appSettings.openaiApiKey
                     settingsDialog.currentLlmProvider = appSettings.llmApiProvider
                     
                     settingsDialog.currentSaveHeroicAssetsLocally = appSettings.saveHeroicAssetsLocally
                     settingsDialog.currentAutoRescanOnStartup = appSettings.autoRescanOnStartup
                     settingsDialog.currentConfirmOnQuit = appSettings.confirmOnQuit
                     settingsDialog.currentGridScale = appSettings.gridScale
                     
                     settingsDialog.currentUseCustomYtdlp = appSettings.useCustomYtdlp
                     settingsDialog.currentCustomYtdlpPath = appSettings.customYtdlpPath
                     
                     settingsDialog.currentDefaultProtonRunner = appSettings.defaultProtonRunner
                     settingsDialog.currentDefaultProtonPrefix = appSettings.defaultProtonPrefix
                     settingsDialog.currentDefaultProtonWrapper = appSettings.defaultProtonWrapper
                     settingsDialog.currentDefaultProtonUseGamescope = appSettings.defaultProtonUseGamescope
                     settingsDialog.currentDefaultProtonUseMangohud = appSettings.defaultProtonUseMangohud
                     settingsDialog.currentDefaultProtonGamescopeArgs = appSettings.defaultProtonGamescopeArgs
                     settingsDialog.currentDefaultProtonGamescopeW = appSettings.defaultProtonGamescopeW
                     settingsDialog.currentDefaultProtonGamescopeH = appSettings.defaultProtonGamescopeH
                     settingsDialog.currentDefaultProtonGamescopeOutW = appSettings.defaultProtonGamescopeOutW
                     settingsDialog.currentDefaultProtonGamescopeOutH = appSettings.defaultProtonGamescopeOutH
                     settingsDialog.currentDefaultProtonGamescopeRefresh = appSettings.defaultProtonGamescopeRefresh
                     settingsDialog.currentDefaultProtonGamescopeScaling = appSettings.defaultProtonGamescopeScaling
                     settingsDialog.currentDefaultProtonGamescopeUpscaler = appSettings.defaultProtonGamescopeUpscaler
                     settingsDialog.currentDefaultProtonGamescopeFullscreen = appSettings.defaultProtonGamescopeFullscreen
                     
                     settingsDialog.currentHidePlatformsSidebar = appSettings.hidePlatformsSidebar
                     settingsDialog.currentCheckForUpdatesOnStartup = appSettings.checkForUpdatesOnStartup
                     
                     settingsDialog.open()
                }

                onPlatformTypeSelected: (ptype, picon) => {
                    var pid = "type:" + ptype
                    currentPlatformId = pid
                    window.currentViewTitle = ptype
                    window.currentPlatformIcon = picon || "🏷️"
                    
                    pushHistory("platformType", ptype, ptype, picon || "🏷️");

                    gameModel.setPlatformTypeFilter(ptype)
                    
                    // Queue restoration for the INCOMING platform type
                    pendingSelectionId = platformSelectionCache[pid] || ""
                }
            }
            
            Connections {
                target: gameModel
                function onPlatformTypesChanged() {
                    sidebar.setPlatformTypes(gameModel.getPlatformTypes())
                }
                
                function onLoadingFinishedSignal() {
                    // Simplified restoration: prioritize pending (explicit) then cache
                    var restoreId = pendingSelectionId
                    if (restoreId === "") {
                        restoreId = platformSelectionCache[currentPlatformId] || ""
                    }

                    if (restoreId !== "") {
                        var idx = gameModel.getRowById(restoreId)
                        if (idx >= 0) {
                            selectGame(idx)
                        } else if (gameModel.rowCount() > 0) {
                            selectGame(0)
                        }
                    } else if (gameModel.rowCount() > 0) {
                        selectGame(0)
                    }

                    pendingSelectionId = ""
                }
            }
            
            Connections {
                target: sidebar.platformModel
                
                function onDeleteProgress(platformId, progress, status) {
                    window.backgroundActivityId = "Deletion"
                    window.backgroundActivityStatus = status
                    window.backgroundActivityProgress = progress
                    window.hasBackgroundActivity = true
                }
                
                function onDeleteFinished(platformId, success, message) {
                    window.hasBackgroundActivity = false
                    if (!success) {
                        scrapeErrorDialog.text = "Deletion Failed: " + message
                        scrapeErrorDialog.open()
                    }
                }
            }
            
            Component.onCompleted: {
                sidebar.setPlatformTypes(gameModel.getPlatformTypes())
            }
            
            // Shared AppInfo for DB Path
            AppInfo { 
                id: rootAppInfo 
                onUpdateAvailable: (version, notes, url) => {
                    updateNotificationDialog.version = version
                    updateNotificationDialog.notes = notes
                    updateNotificationDialog.url = url
                    updateNotificationDialog.open()
                }
            }

            Dialog {
                id: newPlaylistDialog
                title: "New Playlist"
                standardButtons: Dialog.Ok | Dialog.Cancel
                anchors.centerIn: parent
                property alias text: nameInput.text
                background: Rectangle {
                    color: Theme.background
                    border.color: Theme.border
                    radius: 8
                }
                contentItem: ColumnLayout {
                    spacing: 15
                    Label { text: "Playlist Name:"; color: Theme.text }
                    TextField { 
                        id: nameInput
                        Layout.fillWidth: true
                        placeholderText: "Enter name..."
                        color: Theme.text
                        background: Rectangle {
                            color: Theme.secondaryBackground
                            radius: 4
                            border.color: nameInput.activeFocus ? Theme.accent : Theme.border
                        }
                    }
                }
                onAccepted: {
                    if (nameInput.text !== "") {
                        playlistModel.createPlaylist(nameInput.text)
                        nameInput.text = ""
                        // playlistModel should handle refresh via its own logic or signal
                        // If it doesn't, we might need to trigger it.
                        // window.refreshPlaylists() // Check if available
                    }
                }
            }
        }

        Resizer {
            id: sidebarResizer
            visible: true
            targetWidth: sidebar.collapsed ? 64 : appSettings.sidebarWidth
            minWidth: sidebar.collapsed ? 64 : 150
            maxWidth: 250
            isRightSide: true
            
            onTargetWidthChanged: {
                if (sidebar.collapsed) {
                    if (targetWidth > 150) {
                        sidebar.collapsed = false
                        if (Math.abs(appSettings.sidebarWidth - targetWidth) > 0.1) {
                            appSettings.sidebarWidth = targetWidth
                        }
                    }
                } else {
                    if (targetWidth <= 150) {
                        sidebar.collapsed = true
                    } else if (Math.abs(appSettings.sidebarWidth - targetWidth) > 0.1) {
                        appSettings.sidebarWidth = targetWidth
                    }
                }
            }

            Connections {
                target: sidebar
                function onCollapsedChanged() {
                    sidebarResizer.targetWidth = sidebar.collapsed ? 64 : appSettings.sidebarWidth
                }
            }

            onPressedChanged: {
                if (!pressed) appSettings.save()
            }
        }

        // CENTER GRID/LIST (Games)
        Rectangle {
            id: mainCenterArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            clip: true


            
            // View Toggle (Top Right of Center area, or header)
            // Let's put a header bar above the grid
           
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Header Bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    color: "transparent"
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        
                        RowLayout {
                            spacing: 12
                             Text {
                                text: window.currentPlatformIcon && !window.currentPlatformIcon.includes("/") && !window.currentPlatformIcon.includes(".") ? window.currentPlatformIcon : ""
                                color: Theme.text
                                font.pixelSize: 20
                                visible: text !== ""
                            }
                            Image {
                                source: {
                                    if (!window.currentPlatformIcon || (!window.currentPlatformIcon.includes("/") && !window.currentPlatformIcon.includes("."))) return ""
                                    if (window.currentPlatformIcon.startsWith("http") || window.currentPlatformIcon.startsWith("file://") || window.currentPlatformIcon.startsWith("qrc:/") || window.currentPlatformIcon.startsWith("/")) {
                                        return (window.currentPlatformIcon.startsWith("/") ? "file://" + window.currentPlatformIcon : window.currentPlatformIcon) + "?t=" + sidebar.platformModel.cache_buster
                                    }
                                    if (window.currentPlatformIcon.startsWith("assets/")) {
                                        return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + window.currentPlatformIcon + "?t=" + sidebar.platformModel.cache_buster
                                    }
                                    return "file://" + window.currentPlatformIcon + "?t=" + sidebar.platformModel.cache_buster
                                }
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                fillMode: Image.PreserveAspectFit
                                visible: source != ""
                            }
                            Text {
                                text: window.currentViewTitle
                                color: Theme.text
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }

                         // Filter Indicator Tags
                         Flow {
                             Layout.leftMargin: 10
                             Layout.fillWidth: true
                             spacing: 6
                             visible: filterBar.isFiltered || (searchField.text !== "")
                             
                             // Helper component for tags
                             component FilterTag: Rectangle {
                                 property string label
                                 property string value
                                 signal cleared()

                                 height: 24
                                 width: contentRow.width + 20
                                 color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                 radius: 12
                                 border.color: Theme.accent
                                 border.width: 1

                                 Row {
                                     id: contentRow
                                     anchors.centerIn: parent
                                     spacing: 5

                                     Text {
                                         text: "<b>" + label + ":</b> " + value
                                         color: Theme.text
                                         font.pixelSize: 10
                                         anchors.verticalCenter: parent.verticalCenter
                                     }

                                     // Dismiss × button
                                     Item {
                                         width: 14; height: 14
                                         anchors.verticalCenter: parent.verticalCenter

                                         Text {
                                             anchors.centerIn: parent
                                             text: "✕"
                                             font.pixelSize: 9
                                             color: dismissArea.containsMouse ? "white" : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.7)
                                             Behavior on color { ColorAnimation { duration: 100 } }
                                         }

                                         MouseArea {
                                             id: dismissArea
                                             anchors.fill: parent
                                             hoverEnabled: true
                                             cursorShape: Qt.PointingHandCursor
                                             onClicked: cleared()
                                         }
                                     }
                                 }
                             }

                             FilterTag {
                                 label: "Search"
                                 value: searchField.text
                                 visible: searchField.text !== ""
                                 onCleared: {
                                     searchField.text = ""
                                     window.searchActive = false
                                     if (gameModel) gameModel.setSearchFilter("")
                                 }
                             }
                             
                             FilterTag {
                                 label: "Genre"
                                 value: filterBar.genreBox ? filterBar.genreBox.currentText : ""
                                 visible: filterBar.genreBox && filterBar.genreBox.currentIndex > 0
                                 onCleared: {
                                     if (filterBar.genreBox) filterBar.genreBox.currentIndex = 0
                                     if (gameModel) gameModel.setGenreFilter("All Genres")
                                 }
                             }

                             FilterTag {
                                 label: "Region"
                                 value: filterBar.regionBox ? filterBar.regionBox.currentText : ""
                                 visible: filterBar.regionBox && filterBar.regionBox.currentIndex > 0
                                 onCleared: {
                                     if (filterBar.regionBox) filterBar.regionBox.currentIndex = 0
                                     if (gameModel) gameModel.setRegionFilter("All Regions")
                                 }
                             }

                             FilterTag {
                                 label: "Developer"
                                 value: filterBar.developerBox ? filterBar.developerBox.currentText : ""
                                 visible: filterBar.developerBox && filterBar.developerBox.currentIndex > 0
                                 onCleared: {
                                     if (filterBar.developerBox) filterBar.developerBox.currentIndex = 0
                                     if (gameModel) gameModel.setDeveloperFilter("All Developers")
                                 }
                             }

                             FilterTag {
                                 label: "Publisher"
                                 value: filterBar.publisherBox ? filterBar.publisherBox.currentText : ""
                                 visible: filterBar.publisherBox && filterBar.publisherBox.currentIndex > 0
                                 onCleared: {
                                     if (filterBar.publisherBox) filterBar.publisherBox.currentIndex = 0
                                     if (gameModel) gameModel.setPublisherFilter("All Publishers")
                                 }
                             }

                             FilterTag {
                                 label: "Year"
                                 value: filterBar.yearBox ? filterBar.yearBox.currentText : ""
                                 visible: filterBar.yearBox && filterBar.yearBox.currentIndex > 0
                                 onCleared: {
                                     if (filterBar.yearBox) filterBar.yearBox.currentIndex = 0
                                     if (gameModel) gameModel.setYearFilter("All Years")
                                 }
                             }

                             FilterTag {
                                 label: "Rating"
                                 value: filterBar.ratingBox ? filterBar.ratingBox.currentText : ""
                                 visible: filterBar.ratingBox && filterBar.ratingBox.currentIndex > 0
                                 onCleared: {
                                     if (filterBar.ratingBox) filterBar.ratingBox.currentIndex = 0
                                     if (gameModel) gameModel.setRatingFilter(0)
                                 }
                             }

                             FilterTag {
                                 label: "Favorites"
                                 value: "Only"
                                 visible: filterBar.favButton && filterBar.favButton.checked
                                 onCleared: {
                                     if (filterBar.favButton) filterBar.favButton.checked = false
                                     if (gameModel) gameModel.setFavoritesOnly(false)
                                 }
                             }

                             FilterTag {
                                 label: "Installed"
                                 value: "Only"
                                 visible: filterBar.installedButton && filterBar.installedButton.checked
                                 onCleared: {
                                     if (filterBar.installedButton) filterBar.installedButton.checked = false
                                     if (gameModel) gameModel.setInstalledOnly(false)
                                 }
                             }

                             Repeater {
                                 model: filterBar.selectedTags
                                 FilterTag {
                                     label: "Tag"
                                     value: modelData
                                     onCleared: {
                                         filterBar.toggleTag(modelData, false)
                                     }
                                 }
                             }
                         }
                         
                         Item { Layout.fillWidth: true }
                         
                         // Search Slide-out
                         Row {
                             spacing: 5
                             Layout.preferredHeight: 36
                             
                             TheophanyTextField {
                                 id: searchField
                                 placeholderText: "Search..."
                                 width: window.searchActive ? 200 : 0
                                 height: 36
                                 opacity: window.searchActive ? 1.0 : 0.0
                                 clip: true
                                 visible: window.searchActive || width > 0
                                 
                                 Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
                                 Behavior on opacity { NumberAnimation { duration: 200 } }
                                 
                                 onTextChanged: {
                                     if (gameModel) gameModel.setSearchFilter(text)
                                 }
                                 Keys.onPressed: (event) => {
                                      if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && (event.modifiers & Qt.ControlModifier)) {
                                          if (gameModel.rowCount() > 0) {
                                              var romId = gameModel.getGameId(0)
                                              window.jumpToGame(romId)
                                              window.searchActive = false
                                              searchField.text = ""
                                              event.accepted = true
                                          }
                                      }
                                  }

                                  Keys.onEscapePressed: {
                                      if (text === "") window.searchActive = false
                                      else text = ""
                                      window.refocusList()
                                  }
                              }

                             Rectangle {
                                 width: 36
                                 height: 36
                                 color: window.searchActive ? Theme.accent : Qt.rgba(1,1,1,0.1)
                                 radius: 18
                                 
                                 Text {
                                     anchors.centerIn: parent
                                     text: "🔍"
                                     font.pixelSize: 16
                                     color: "white"
                                 }
                                 
                                 MouseArea {
                                     anchors.fill: parent
                                     cursorShape: Qt.PointingHandCursor
                                     onClicked: {
                                         window.searchActive = !window.searchActive
                                         if (window.searchActive) searchField.forceActiveFocus()
                                     }
                                 }
                             }
                         }

                         // Grid Scale Slider
                         Slider {
                             visible: viewStack.currentIndex === 0
                             from: 0.5
                             to: 1.5
                             value: window.gridScale
                             onMoved: {
                                 window.gridScale = value
                                 appSettings.gridScale = value
                                 appSettings.save()
                             }
                             Layout.preferredWidth: 100
                             TheophanyTooltip {
                                 visible: parent.hovered || parent.pressed
                                 text: Math.round(parent.value * 100) + "%"
                             }

                             background: Rectangle {
                                 x: parent.leftPadding
                                 y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                 implicitWidth: 200
                                 implicitHeight: 4
                                 width: parent.availableWidth
                                 height: implicitHeight
                                 radius: 2
                                 color: Theme.border

                                 Rectangle {
                                     width: parent.visualPosition * parent.width
                                     height: parent.height
                                     color: Theme.accent
                                     radius: 2
                                 }
                             }

                             handle: Rectangle {
                                 x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                 y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                 implicitWidth: 16
                                 implicitHeight: 16
                                 radius: 8
                                 color: parent.pressed ? Theme.accent : "#f6f6f6"
                                 border.color: Theme.accent
                              }
                         }

                         // Top Bar Sort (Only for Grid)
                         TheophanyComboBox {
                             id: topSortBox
                             visible: viewStack.currentIndex === 0
                             Layout.preferredWidth: 150
                             Layout.preferredHeight: 36
                             model: ["Title (A-Z)", "Title (Z-A)", "Recently Added", "Last Played"]
                             onActivated: {
                                 if (gameModel) {
                                     var method = "TitleAZ"
                                     if (index === 1) method = "TitleZA"
                                     else if (index === 2) method = "Recent"
                                     else if (index === 3) method = "LastPlayed"
                                     gameModel.setSortMethod(method)
                                     window.refocusList()
                                 }
                             }

                             Connections {
                                 target: gameModel
                                 function onSortMethodChanged() {
                                     var method = gameModel.sortMethod
                                     if (method === "TitleAZ") topSortBox.currentIndex = 0
                                     else if (method === "TitleZA" || method === "TitleDESC") topSortBox.currentIndex = 1
                                     else if (method === "Recent") topSortBox.currentIndex = 2
                                     else if (method === "LastPlayed") topSortBox.currentIndex = 3
                                 }
                             }
                         }

                         // Filter Toggle Button
                         Rectangle {
                             width: 36
                             height: 36
                             color: window.showFilterBar ? Theme.accent : Qt.rgba(1,1,1,0.1)
                             radius: 6
                             border.color: window.showFilterBar ? "transparent" : Qt.rgba(1,1,1,0.2)
                             
                             Text {
                                 anchors.centerIn: parent
                                 text: "▼" // Filter funnel icon
                                 font.pixelSize: 14
                                 color: window.showFilterBar ? "white" : Theme.text
                             }
                             
                             MouseArea {
                                 id: filterMa
                                 anchors.fill: parent
                                 cursorShape: Qt.PointingHandCursor
                                 hoverEnabled: true
                                 onClicked: window.showFilterBar = !window.showFilterBar
                                 
                                 TheophanyTooltip {
                                     visible: filterMa.containsMouse
                                     text: window.showFilterBar ? "Hide Filters" : "Show Filters"
                                 }
                             }
                         }

                         ViewToggle {
                             currentViewMode: viewStack.currentIndex
                             onViewChanged: (mode) => {
                                 viewStack.currentIndex = mode
                             }
                         }
                    }
                }

                FilterBar {
                    id: filterBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.showFilterBar ? 50 : 0
                    opacity: window.showFilterBar ? 1.0 : 0.0
                    visible: opacity > 0
                    gameModel: gameModel
                    clip: true
                    
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }

                AppInfo { id: appInfo }

                GameListModel {
                    id: gameModel
                    // Use XDG data path for persistence
                    Component.onCompleted: {
                        init(appInfo.getDataPath() + "/games.db")
                        filterBar.refreshModels()
                        
                        // Apply Ignore "The" Sorting from Settings
                        gameModel.setIgnoreTheInSort(appSettings.ignoreTheInSort)

                        // Apply Default Region from Settings
                        if (appSettings.defaultRegion !== "" && appSettings.defaultRegion !== "All Regions") {
                             gameModel.setRegionFilter(appSettings.defaultRegion)
                             filterBar.selectRegion(appSettings.defaultRegion)
                        } else {
                           // If loaded late, Connections handles it.
                        }
                    }
                    onStatsUpdated: (totalGames, totalTime, lastPlayed, lastPlayedId, libraryCount) => {
                         window.statTotalGames = totalGames
                         window.statTotalLibraryCount = libraryCount
                         window.statTotalTime = totalTime
                         window.statLastPlayed = lastPlayed
                         window.statLastPlayedId = lastPlayedId
                         refreshUpNext()
                         
                         // Auto-refresh details for the currently viewed game (if persistent)
                         if (detailsPanel.gameId !== "") {
                             var idx = gameModel.getRowById(detailsPanel.gameId)
                             if (idx >= 0) {
                                 window.selectGame(idx)
                             } else if (totalGames > 0 && !window.isJumping) {
                                 window.selectGame(0)
                             }
                         } else if (totalGames > 0 && !window.isJumping) {
                             // Initial launch or switch to platform with no saved selection
                             window.selectGame(0)
                         }
                    }

                    onPlaytimeUpdated: (romId) => {
                         // Logic moved to DetailsPanel for robustness
                    }

                    onImportProgress: (p, status) => {
                        importProgressDialog.progress = p
                        importProgressDialog.status = status
                        
                        if (importProgressDialog.minimized) {
                            window.backgroundActivityId = "Import"
                            window.backgroundActivityStatus = status
                            window.backgroundActivityProgress = p
                            window.hasBackgroundActivity = true
                        } else if (!importProgressDialog.opened) {
                            importProgressDialog.open()
                        }
                    }

                    onAssetDownloadProgress: (msg) => {
                         window.assetDownloadStatus = msg
                    }

                    onImportFinished: (pid, jsonIds) => {
                        importProgressDialog.progress = 1.0
                        importProgressDialog.status = "Import complete!"
                        importProgressDialog.minimized = false
                        window.hasBackgroundActivity = false
                        sidebar.refresh()
                        filterBar.refreshModels()

                        if (romPreviewDialog.autoScrape) {
                            try {
                                var ids = JSON.parse(jsonIds)
                                if (ids.length > 0) {
                                    pendingBulkScrapeIds = ids
                                }
                            } catch (e) {

                            }
                        }
                    }

                    onGameDataChanged: (romId) => {
                         // Signal handled in DetailsPanel directly for better reliability
                    }
                }

                Timer {
                    id: globalPollTimer
                    interval: 100
                    repeat: true
                    running: true
                    onTriggered: {
                        gameModel.checkAsyncResponses()
                        sidebar.platformModel.checkAsyncResponses()
                        storeBridge.poll()
                    }
                }

                StackLayout {
                    id: viewStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: 0 // 0=Grid, 1=List
                    visible: window.statTotalGames > 0
                    
                    // Shared selection state between grid and list views
                    property int sharedGameIndex: 0
                    property var sharedSelectedIndices: []
                    property int sharedSelectionAnchor: -1
                    property bool sharedIgnoreNextReset: false
                    
                    function selectAll() {
                        var newSel = []
                        for (var i = 0; i < gameModel.rowCount(); i++) {
                            newSel.push(i)
                        }
                        sharedSelectedIndices = newSel
                    }

                    function updateRangeSelection(targetIndex) {
                        if (sharedSelectionAnchor === -1) sharedSelectionAnchor = sharedGameIndex
                        var start = Math.min(sharedSelectionAnchor, targetIndex)
                        var end = Math.max(sharedSelectionAnchor, targetIndex)
                        var newSel = []
                        for (var i = start; i <= end; i++) {
                            newSel.push(i)
                        }
                        sharedIgnoreNextReset = true
                        sharedSelectedIndices = newSel
                        sharedGameIndex = targetIndex
                        
                        if (currentIndex === 0) gameGrid.currentIndex = targetIndex
                        else gameList.currentIndex = targetIndex
                    }
                    
                    onCurrentIndexChanged: {
                        if (currentIndex === 0) {
                            gameGrid.currentIndex = sharedGameIndex
                            gameGrid.forceActiveFocus()
                            // Defer positioning to avoid blocking UI
                            Qt.callLater(function() {
                                gameGrid.positionViewAtIndex(sharedGameIndex, GridView.Contain)
                            })
                        } else {
                            gameList.currentIndex = sharedGameIndex
                            gameList.forceActiveFocus()
                            // Defer positioning to avoid blocking UI
                            Qt.callLater(function() {
                                gameList.positionViewAtIndex(sharedGameIndex, ListView.Contain)
                            })
                        }
                    }

                    // Index 0: Grid
                    GridView {
                        id: gameGrid
                        cellWidth: 207 * window.gridScale
                        cellHeight: 299 * window.gridScale
                        model: gameModel
                        focus: true
                        clip: true
                        interactive: true
                        boundsBehavior: Flickable.DragAndOvershootBounds
                        highlightMoveDuration: 0
                        ScrollBar.vertical: TheophanyScrollBar { 
                            policy: gameGrid.visibleArea.heightRatio < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff 
                        }
                        
                        // Performance optimizations for large lists (4500+ items)
                        cacheBuffer: 500 // Increase cache buffer to pre-render more items off-screen
                        reuseItems: true // Reuse delegate items instead of creating/destroying
                        displayMarginBeginning: 100 // Reduce overdraw at the beginning
                        displayMarginEnd: 100 // Reduce overdraw at the end

                        onCurrentIndexChanged: {
                            viewStack.sharedGameIndex = currentIndex
                            if (currentIndex >= 0 && focus) {
                                // Save to memory cache (session-only)
                                var gid = gameModel.getGameId(currentIndex)
                                if (gid !== "" && currentPlatformId !== undefined) {
                                    platformSelectionCache[currentPlatformId] = gid
                                }

                                // Reset selection if moving without Shift or Control
                                if (!viewStack.sharedIgnoreNextReset) {
                                    viewStack.sharedSelectedIndices = [currentIndex]
                                    viewStack.sharedSelectionAnchor = currentIndex
                                }
                                viewStack.sharedIgnoreNextReset = false
                                window.loadGameDetails(currentIndex)
                            }
                        }

                        Keys.onReturnPressed: {
                            if (currentIndex >= 0) {
                                var id = gameModel.getGameId(currentIndex)
                                window.launchGame(id)
                            }
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                                viewStack.selectAll()
                                event.accepted = true
                            } else if (event.key === Qt.Key_E && currentIndex >= 0) {
                                window.openGameEdit(gameModel.getGameId(currentIndex))
                                event.accepted = true
                            } else if (event.modifiers & Qt.ShiftModifier) {
                                var columns = Math.floor(gameGrid.width / gameGrid.cellWidth)
                                var newIdx = -1
                                if (event.key === Qt.Key_Up) newIdx = Math.max(0, currentIndex - columns)
                                else if (event.key === Qt.Key_Down) newIdx = Math.min(gameModel.rowCount() - 1, currentIndex + columns)
                                else if (event.key === Qt.Key_Left) newIdx = Math.max(0, currentIndex - 1)
                                else if (event.key === Qt.Key_Right) newIdx = Math.min(gameModel.rowCount() - 1, currentIndex + 1)
                                
                                if (newIdx !== -1) {
                                    viewStack.updateRangeSelection(newIdx)
                                    event.accepted = true
                                }
                            } else if (event.modifiers & Qt.ControlModifier) {
                                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                                    viewStack.sharedIgnoreNextReset = true
                                }
                            }
                        }

                        Keys.onTabPressed: (event) => { event.accepted = true }
                        Keys.onBacktabPressed: (event) => { event.accepted = true }

                        // KeyNavigation.left: sidebar.platformListRef // Removed

                        delegate: Item {
                            id: delegateRoot
                            width: gameGrid.cellWidth
                            height: gameGrid.cellHeight
                            property bool hovered: false
                            readonly property bool isSelected: (viewStack && viewStack.sharedSelectedIndices) ? (viewStack.sharedSelectedIndices.indexOf(index) !== -1 || (gameGrid.currentIndex === index && gameGrid.activeFocus)) : false

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 10
                                color: "transparent"
                                
                                // Selection Highlight
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    color: "transparent"
                                    border.color: Theme.accent
                                    border.width: 3
                                    radius: 12
                                    // Highlight if in shared selection OR if it's the current keyboard focus
                                    visible: delegateRoot.isSelected
                                    
                                    layer.enabled: delegateRoot.isSelected
                                    layer.effect: Glow {
                                        color: Theme.accent
                                        opacity: 0.4
                                        radius: 6
                                        samples: 9
                                        spread: 0.2
                                        transparentBorder: true
                                    }
                                }
                                
                                // Poster Art Placeholder
                                Rectangle {
                                    id: poster
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 20
                                    height: width * 1.5
                                    color: Theme.secondaryBackground
                                    radius: 8
                                    
                                    // Shadow/Glow - Only for selected item to avoid rapid layer allocation during hover/scroll
                                    layer.enabled: delegateRoot.isSelected
                                    layer.effect: DropShadow {
                                        transparentBorder: true
                                        color: Qt.rgba(0,0,0,0.5)
                                        samples: 9
                                    }
                                    
                                    // Hover Border Highlight (Lightweight alternative to shadow)
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        color: "transparent"
                                        border.color: Theme.accent
                                        border.width: 2
                                        radius: 8
                                        visible: delegateRoot.hovered && !delegateRoot.isSelected
                                    }

                                    Image {
                                        anchors.fill: parent
                                        source: (typeof gameBoxArt !== "undefined" && gameBoxArt !== "") ? gameBoxArt : ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: source != ""
                                        cache: true
                                        asynchronous: true
                                        opacity: (typeof gameIsInstalled !== "undefined" && !gameIsInstalled) ? 0.4 : 1.0
                                        // Robust sourceSize: only set if dimensions are valid to avoid startup race crashes
                                        sourceSize: (poster.width > 0 && poster.height > 0) ? Qt.size(poster.width, poster.height) : undefined
                                    }

                                    // Cloud Icon for uninstalled games
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 8
                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: Qt.rgba(0,0,0,0.6)
                                        visible: typeof gameIsInstalled !== "undefined" && !gameIsInstalled
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            text: "☁"
                                            color: "white"
                                            font.pixelSize: 14
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "NO IMG"
                                        color: Theme.secondaryText
                                        visible: parent.children[0].status !== Image.Ready && gameBoxArt === ""
                                    }
                                }

                                // Title Text
                                Text {
                                    anchors.top: poster.bottom
                                    anchors.topMargin: 10
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    text: gameTitle
                                    color: Theme.text
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onEntered: {
                                        delegateRoot.hovered = true
                                        parent.scale = 1.05
                                    }
                                    onExited: {
                                        delegateRoot.hovered = false
                                        parent.scale = 1.0
                                    }
                                    onClicked: (mouse) => {
                                        gameGrid.forceActiveFocus()
                                        
                                        if (mouse.button === Qt.LeftButton) {
                                            if (mouse.modifiers & Qt.ControlModifier) {
                                                var current = viewStack.sharedSelectedIndices.slice() // Clone
                                                var idx = current.indexOf(index)
                                                viewStack.sharedIgnoreNextReset = true
                                                if (idx !== -1) {
                                                    current.splice(idx, 1)
                                                    viewStack.sharedSelectedIndices = current
                                                } else {
                                                    current.push(index)
                                                    viewStack.sharedSelectedIndices = current
                                                    gameGrid.currentIndex = index
                                                    viewStack.sharedSelectionAnchor = index
                                                }
                                            } else if (mouse.modifiers & Qt.ShiftModifier) {
                                                viewStack.updateRangeSelection(index)
                                            } else {
                                                gameGrid.currentIndex = index
                                                viewStack.sharedSelectedIndices = [index]
                                                viewStack.sharedSelectionAnchor = index
                                            }
                                        } else if (mouse.button === Qt.RightButton) {
                                            if (viewStack.sharedSelectedIndices.indexOf(index) === -1) {
                                                gameGrid.currentIndex = index
                                                viewStack.sharedSelectedIndices = [index]
                                                viewStack.sharedSelectionAnchor = index
                                            }
                                            gridContextMenu.popup()
                                        }
                                        window.loadGameDetails(index)
                                    }
                                    onDoubleClicked: window.launchGame(gameId)
                                    
                                        TheophanyMenu {
                                            id: gridContextMenu
                                            
                                            // Mass Edit Option
                                            TheophanyMenuItem {
                                                text: "Mass Edit (" + rootViewStack.sharedSelectedIndices.length + ")"
                                                iconSource: "📝"
                                                visible: rootViewStack.sharedSelectedIndices.length > 1
                                                onTriggered: {
                                                    var ids = []
                                                    for (var i = 0; i < rootViewStack.sharedSelectedIndices.length; i++) {
                                                        ids.push(gameModel.getGameId(rootViewStack.sharedSelectedIndices[i]))
                                                    }
                                                    window.openMassEdit(ids)
                                                }
                                            }
                                            TheophanyMenuSeparator { visible: rootViewStack.sharedSelectedIndices.length > 1 }

                                            TheophanyMenuItem {
                                                text: "Run Game"
                                                iconSource: "🚀"
                                                visible: rootViewStack.sharedSelectedIndices.length === 1
                                                onTriggered: window.launchGame(gameId)
                                            }
                                            TheophanyMenuItem {
                                                text: "Uninstall Game"
                                                iconSource: "🗑️"
                                                visible: rootViewStack.sharedSelectedIndices.length === 1
                                                         && (typeof gamePlatformType !== "undefined" && gamePlatformType.toLowerCase() === "steam")
                                                         && (typeof gameIsInstalled !== "undefined" && gameIsInstalled)
                                                onTriggered: gameModel.uninstallSteamGame(gameId)
                                            }
                                            TheophanyMenuSeparator { visible: rootViewStack.sharedSelectedIndices.length === 1 }
                                            TheophanyMenu {
                                                id: addToPlaylistMenu
                                                title: "Add to Playlist"
                                                property string iconSource: "📜"

                                                Instantiator {
                                                    model: playlistModel
                                                    TheophanyMenuItem {
                                                        text: playlistName
                                                        iconSource: "📜"
                                                        onTriggered: {
                                                            gridContextMenu.close()
                                                            gameGrid.forceActiveFocus()
                                                            for (var i = 0; i < rootViewStack.sharedSelectedIndices.length; i++) {
                                                                var gId = gameModel.getGameId(rootViewStack.sharedSelectedIndices[i])
                                                                gameModel.addToPlaylist(playlistId, gId)
                                                            }
                                                            playlistModel.refresh()
                                                        }
                                                    }
                                                    onObjectAdded: (index, object) => addToPlaylistMenu.insertItem(index, object)
                                                    onObjectRemoved: (index, object) => addToPlaylistMenu.removeItem(object)
                                                }
                                                
                                                TheophanyMenuSeparator {
                                                    visible: playlistModel.rowCount() > 0
                                                }

                                                TheophanyMenuItem {
                                                    text: "Manage Playlists..."
                                                    iconSource: "➕"
                                                    onTriggered: {
                                                        playlistManagerDialog.open()
                                                        gridContextMenu.close()
                                                    }
                                                }
                                            }
                                            TheophanyMenu {
                                                id: metadataMenuGrid
                                                title: "Metadata"
                                                property string iconSource: "📋"
                                                
                                                TheophanyMenuItem {
                                                    text: rootViewStack.sharedSelectedIndices.length > 1 ? "Bulk Auto-Scrape..." : "Auto Populate Metadata"
                                                    iconSource: "🤖"
                                                    onTriggered: {
                                                        if (rootViewStack.sharedSelectedIndices.length > 1) {
                                                            var ids = []
                                                            for (var i = 0; i < rootViewStack.sharedSelectedIndices.length; i++) {
                                                                ids.push(gameModel.getGameId(rootViewStack.sharedSelectedIndices[i]))
                                                            }
                                                            window.openBulkScrape(ids)
                                                        } else {
                                                            // Get game ID and title
                                                            var gId = gameId
                                                            var gTitle = gameTitle
                                                            
                                                            // Store ID in the dialog for context
                                                            mainScrapeDialog.gameId = gId
                                                            mainScrapeDialog.query = gTitle
                                                            
                                                            gameModel.autoScrape(gId)
                                                        }
                                                    }
                                                }
                                                TheophanyMenuItem {
                                                    text: "Update RetroAchievements"
                                                    iconSource: "🏆"
                                                    visible: !gamePlatformType.includes("PC")
                                                    onTriggered: {
                                                        // Call the same achievement refresh function used when game closes
                                                        if (detailsPanel && typeof detailsPanel.refreshAchievements !== 'undefined') {
                                                            detailsPanel.refreshAchievements(true) // true = silent refresh
                                                        }
                                                    }
                                                }
                                                TheophanyMenuItem {
                                                    text: "Find Online"
                                                    iconSource: "🌐"
                                                    onTriggered: {
                                                        // Get game ID and title
                                                        var gId = gameId
                                                        var gTitle = gameTitle
                                                        
                                                        // Open scrape dialog (same as Shift+S)
                                                        mainScrapeDialog.gameId = gId
                                                        mainScrapeDialog.query = gTitle
                                                        mainScrapeDialog.platform = (typeof gamePlatformType !== "undefined" && gamePlatformType !== "") ? gamePlatformType : gamePlatformName
                                                        mainScrapeDialog.targetCategory = "Box - Front" // Default
                                                        mainScrapeDialog.currentTab = 0
                                                        mainScrapeDialog.open()
                                                    }
                                                }
                                                TheophanyMenuItem {
                                                    text: "Refresh Assets"
                                                    iconSource: "🔄"
                                                    onTriggered: {
                                                        for(var i=0; i<viewStack.sharedSelectedIndices.length; i++) {
                                                            var gId = gameModel.getGameId(viewStack.sharedSelectedIndices[i])
                                                            gameModel.refreshGameAssets(gId)
                                                        }
                                                    }
                                                }
                                            }
                                            TheophanyMenuItem {
                                                text: "Video Explorer"
                                                iconSource: "🎬"
                                                onTriggered: {
                                                    // Open video download dialog (same as V key)
                                                    window.openVideoDownload(
                                                        detailsPanel.gameFilename,
                                                        detailsPanel.gameTitle,
                                                        detailsPanel.gamePlatform,
                                                        detailsPanel.gamePlatformType,
                                                        detailsPanel.platformFolder
                                                    )
                                                }
                                            }
                                            TheophanyMenuItem {
                                                text: "View Images"
                                                iconSource: "🖼️"
                                                onTriggered: {
                                                    // Open image viewer (same as I key)
                                                    detailsPanel.openImageViewer()
                                                }
                                            }
                                            TheophanyMenuSeparator {}
                                        TheophanyMenuItem {
                                            text: rootViewStack.sharedSelectedIndices.length > 1 ? "Toggle Favorites" : (gameIsFavorite ? "Remove from Favorites" : "Add to Favorites")
                                            iconSource: "⭐"
                                            onTriggered: {
                                                for(var i=0; i<rootViewStack.sharedSelectedIndices.length; i++) {
                                                    var gId = gameModel.getGameId(rootViewStack.sharedSelectedIndices[i])
                                                    gameModel.toggleFavorite(gId)
                                                }
                                            }
                                        }
                                        TheophanyMenuItem {
                                            text: "Game Properties"
                                            iconSource: "📝"
                                            visible: rootViewStack.sharedSelectedIndices.length === 1
                                            onTriggered: window.openGameEdit(gameId)
                                        }
                                        TheophanyMenuSeparator {}
                                        TheophanyMenuItem {
                                            text: "Delete from Library"
                                            iconSource: "🗑️"
                                            onTriggered: {
                                                if (rootViewStack.sharedSelectedIndices.length <= 1) {
                                                    window.deleteGameId = gameId
                                                    window.deleteGameTitle = gameTitle
                                                    window.deleteGameIds = [gameId]
                                                    deleteConfirmDialog.open()
                                                } else {
                                                    var ids = []
                                                    for (var i = 0; i < rootViewStack.sharedSelectedIndices.length; i++) {
                                                        ids.push(gameModel.getGameId(rootViewStack.sharedSelectedIndices[i]))
                                                    }
                                                    window.deleteGameIds = ids
                                                    deleteConfirmDialog.open()
                                                }
                                            }
                                        }
                                    }
                                }
                                Behavior on scale { NumberAnimation { duration: 100 } }
                            }
                        }
                    } // End GridView

                    GameList {
                        id: gameList
                        model: gameModel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        currentIndex: viewStack.sharedGameIndex
                        selectedIndices: viewStack.sharedSelectedIndices
                        selectionAnchor: viewStack.sharedSelectionAnchor
                        ignoreNextReset: viewStack.sharedIgnoreNextReset
                        
                        onCurrentIndexChanged: {
                            viewStack.sharedGameIndex = currentIndex
                            // Save to memory cache (session-only)
                            if (currentIndex >= 0 && focus) {
                                var gid = gameModel.getGameId(currentIndex)
                                if (gid !== "" && currentPlatformId !== "") {
                                    platformSelectionCache[currentPlatformId] = gid
                                }
                            }
                        }
                        
                        onSelectedIndicesChanged: {
                            viewStack.sharedSelectedIndices = selectedIndices
                        }
                        
                        onSelectionAnchorChanged: {
                            viewStack.sharedSelectionAnchor = selectionAnchor
                        }

                        onIgnoreNextResetChanged: {
                            viewStack.sharedIgnoreNextReset = ignoreNextReset
                        }
                    }
                } // End StackLayout

                EmptyStateView {
                    id: emptyStateView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: window.statTotalGames === 0
                    isSearching: window.searchActive || filterBar.isFiltered
                    platformName: window.currentViewTitle !== "All Games" ? window.currentViewTitle : ""
                    
                    onAddFileRequested: {
                        addContentDialog.isFolderMode = false
                        addContentDialog.open()
                    }
                    onAddFolderRequested: {
                        addContentDialog.isFolderMode = true
                        addContentDialog.open()
                    }
                    onCreateCollectionRequested: addSystemDialog.openAdd()
                    onClearFiltersRequested: {
                        searchField.text = ""
                        window.searchActive = false
                        gameModel.setSearchFilter("")
                        filterBar.clearFilters()
                    }
                }

                // Bottom Ticker
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    color: Theme.background 
                    
                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Theme.border
                    }
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        anchors.rightMargin: 15
                        spacing: 12
                        
                        // --- Left Group: Statistics ---
                        Text { text: "Games: <font color='" + Theme.text + "'>" + window.statTotalGames + "</font>"; color: Theme.secondaryText; font.pixelSize: 12; textFormat: Text.StyledText }
                        Text { text: "|"; color: Theme.border }
                        
                        Text { text: "Playtime: <font color='" + Theme.text + "'>" + window.statTotalTime + "</font>"; color: Theme.secondaryText; font.pixelSize: 12; textFormat: Text.StyledText }
                        Text { text: "|"; color: Theme.border }

                        Row {
                            spacing: 5
                            Text { text: "Last Played: "; color: Theme.secondaryText; font.pixelSize: 12 }
                            Text {
                                text: window.statLastPlayed
                                color: lpMa.containsMouse ? Theme.accent : Theme.text
                                font.pixelSize: 12
                                font.bold: true
                                MouseArea {
                                    id: lpMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: window.jumpToGame(window.statLastPlayedId)
                                }
                            }
                            
                            // Mini Play Button
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                color: playMa.containsMouse ? Theme.accent : Theme.border
                                visible: (lpMa.containsMouse || playMa.containsMouse) && window.statLastPlayedId !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "▶"; color: Theme.text; font.pixelSize: 8 }
                                MouseArea {
                                    id: playMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (window.statLastPlayedId !== "") gameModel.launchGame(window.statLastPlayedId) }
                                }
                            }
                        }
                        
                        Text { text: "|"; color: Theme.border; visible: window.upNextId !== "" }

                        Row {
                            spacing: 5
                            visible: window.upNextId !== ""
                            Text { text: "Next Up? "; color: Theme.secondaryText; font.pixelSize: 12 }
                            Text {
                                text: window.upNextTitle
                                color: unMa.containsMouse ? Theme.accent : Theme.text
                                font.pixelSize: 12
                                font.italic: true
                                MouseArea {
                                    id: unMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: window.jumpToGame(window.upNextId)
                                }
                            }
                        }

                        // --- Spacer to push notifications to the right ---
                        Item { Layout.fillWidth: true }

                        // --- Right Group: Notifications & Progress ---
                        
                        // Asset Download Status
                        Row {
                            spacing: 12
                            visible: window.assetDownloadStatus !== ""
                            Text { 
                                text: window.assetDownloadStatus
                                color: Theme.accent
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text { text: "|"; color: Theme.border; visible: gameModel.bulkScraping || window.isStoreInstalling }
                        }

                        // Universal Progress Indicator (Scraping, Store Install, or Background Activity)
                        RowLayout {
                            id: universalProgressRow
                            visible: gameModel.bulkScraping || window.isStoreInstalling || window.hasBackgroundActivity
                            spacing: 10
                            
                            Text {
                                text: window.isStoreInstalling ? 
                                      "Installing " + window.storeInstallAppId + ": " + Math.round(window.storeInstallProgress * 100) + "%" :
                                      (window.hasBackgroundActivity ? 
                                       window.backgroundActivityStatus + " (" + Math.round(window.backgroundActivityProgress * 100) + "%)" :
                                       "Scraping: " + Math.round(gameModel.bulkProgress * 100) + "%")
                                color: Theme.accent
                                font.pixelSize: 12
                                font.bold: true
                            }
                            
                            ProgressBar {
                                Layout.preferredWidth: 100
                                Layout.preferredHeight: 4
                                value: window.isStoreInstalling ? window.storeInstallProgress : 
                                       (window.hasBackgroundActivity ? window.backgroundActivityProgress : gameModel.bulkProgress)
                                background: Rectangle {
                                    implicitWidth: 100
                                    implicitHeight: 4
                                    color: Theme.secondaryBackground
                                    radius: 2
                                }
                                contentItem: Item {
                                    implicitWidth: 100
                                    implicitHeight: 4
                                    Rectangle {
                                        width: parent.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color: Theme.accent
                                    }
                                }
                            }

                            // Restore Icon/Button
                            Text {
                                text: "⤢"
                                color: navMa.containsMouse ? Theme.accent : Theme.text
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                MouseArea {
                                    id: navMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (window.isStoreInstalling && window.storeInstallAppId.includes(".")) flatpakStoreDialog.open()
                                        else bulkScrapeDialog.open()
                                    }
                                }
                            }
                        }

                        // Background Activity Indicator
                        Rectangle {
                            id: loadingBar
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 6
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                            radius: 3
                            visible: gameModel.loading
                            clip: true
                            Layout.rightMargin: 10

                            Rectangle {
                                width: 40
                                height: parent.height
                                color: Theme.accent
                                radius: 3
                                
                                NumberAnimation on x {
                                    from: -40
                                    to: 120
                                    duration: 1200
                                    loops: Animation.Infinite
                                    running: loadingBar.visible
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }

                }
            }

            DropArea {
                id: mainDropArea
                anchors.fill: parent
                z: 99
                onDropped: (drop) => {
                    if (drop.hasUrls) {
                        for (var i = 0; i < drop.urls.length; i++) {
                             var url = drop.urls[i].toString()
                             window.openImportFromDrop(url)
                             break
                        }
                    }
                }
            }

            // Drag and Drop Overlay
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.accent, 0.2)
                visible: mainDropArea.containsDrag
                z: 100
                border.color: Theme.accent
                border.width: 2

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    
                    Text {
                        text: "📥"
                        font.pixelSize: 64
                        Layout.alignment: Qt.AlignHCenter
                    }
                    
                    Text {
                        text: "Drop Files or Folders to Import"
                        color: Theme.text
                        font.pixelSize: 22
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                        style: Text.Outline
                        styleColor: Theme.background
                    }
                    
                    Text {
                        text: "Supports individual ROMs or entire system folders"
                        color: Theme.secondaryText
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        // RIGHT SIDEBAR (Details)
        Resizer {
            id: detailsResizer
            visible: detailsPanel.visible && !window.collapsedMode // Only show if panel is visible and not in mobile/collapsed mode
            targetWidth: appSettings.detailsWidth
            minWidth: 250
            maxWidth: window.width * 0.5
            isRightSide: false
            onTargetWidthChanged: {
                if (Math.abs(appSettings.detailsWidth - targetWidth) > 0.1) {
                    appSettings.detailsWidth = targetWidth
                }
            }
            onPressedChanged: {
                if (!pressed) appSettings.save()
            }
        }

        DetailsPanel {
            id: detailsPanel
            gameModel: gameModel
            Layout.preferredWidth: appSettings.detailsWidth
            Layout.fillHeight: true
            visible: window.statTotalGames > 0
            onPlayRequested: (id) => {
                window.launchGame(id)
            }
            onFilterGenre: (genre) => {
                window.showFilterBar = true
                filterBar.selectGenre(genre)
            }
            onUninstallComplete: (romId) => {
                // Refresh the model and re-select the game so the install status updates
                pendingSelectionId = romId
                gameModel.refresh()
            }
        }
    }
    
    GameEditDialog {
        id: gameEditDialog
        platformModel: sidebar.platformModel
        aiEnabled: appSettings.aiEnabled
        ollamaUrl: appSettings.ollamaUrl
        ollamaModel: appSettings.ollamaModel
        aiDescriptionPrompt: appSettings.aiDescriptionPrompt
        geminiKey: appSettings.geminiApiKey
        openaiKey: appSettings.openaiApiKey
        llmProvider: appSettings.llmApiProvider
        storeBridge: storeBridge
        onAccepted: {
             var savedId = gameEditDialog.gameId 
             gameModel.refresh()
             
             // Find the new index of the edited game (refresh may change its position)
             var newIndex = gameModel.getRowById(savedId)
             if (newIndex >= 0) {
                 window.selectGame(newIndex)
             }
        }
    }
    
    VideoDownloadDialog {
        id: videoDownloadDialog
        onDownloadCompleted: (path) => {

            // Trigger DetailsPanel to play it if it's the current game
            // We can just reload the details?
            // detailsPanel will need to be told to check again.
            if (detailsPanel.gameFilename === videoDownloadDialog.gameId || detailsPanel.gameId === videoDownloadDialog.gameId) { 
                 // Assuming gameFilename is gameId basically.
                 detailsPanel.checkVideo()
            }
        }
        onClosed: {
            window.refocusList()
        }
    }
    
    function openGameEdit(gameId, targetTab) {
        if (!gameId) return
        gameEditDialog.load(gameId, targetTab)
        gameEditDialog.open()
    }

    function openVideoDownload(gameId, title, platform, platformType, platformFolder) {
        videoDownloadDialog.show(gameId, title, platform, platformType, platformFolder)
    }

    function openPcConfig(gameId, title, platformType) {
        // Now redirects to unified Properties dialog on the Configuration tab (index 3)
        openGameEdit(gameId, 3)
    }

    function openFlatpakStore(targetPlatformId) {
        flatpakStoreDialog.targetPlatformId = targetPlatformId || ""
        flatpakStoreDialog.open()
    }

    function openLocalAppImport() {
        localAppImportDialog.openImport()
    }

    FirstRunWizard {
        id: firstRunWizard
        raBridge: raBridge
        appSettings: appSettings
        
        onLoginRequested: (username, key) => {
              
             // 1. Update Settings Immediately
             appSettings.retroAchievementsUser = username
             appSettings.retroAchievementsToken = key
             appSettings.retroAchievementsEnabled = true
             
             // 2. Persist Settings
              appSettings.save()
             
             // 3. Trigger Login
              raBridge.login(username, key)
        }
    }

    FlatpakStoreDialog {
        id: flatpakStoreDialog
    }

    LocalAppImportDialog {
        id: localAppImportDialog
    }

    ExoDosImportDialog {
        id: exodosImportDialog
    }

    SteamImportDialog {
        id: steamImportDialog
    }

    HeroicImportDialog {
        id: heroicImportDialog
    }

    EpicImportDialog {
        id: epicImportDialog
    }

    LutrisImportDialog {
        id: lutrisImportDialog
    }
    
    BulkScrapeDialog {
        id: bulkScrapeDialog
    }
    EpicInstallDialog {
        id: epicInstallPathDialog
        appSettings: appSettings
        platformModel: sidebar.platformModel
        storeBridge: storeBridge
    }
    FolderDialog {
        id: epicImportPathDialog
        title: "Select Folder Containing Existing Game Data"
        property string pendingAppId: ""
        onAccepted: {
            var pathStr = selectedFolder.toString()
            if (pathStr.startsWith("file://")) {
                pathStr = pathStr.substring(7)
            }
            storeBridge.import_legendary_game(pendingAppId, pathStr)
        }
    }
    
    function openBulkScrape(ids, mode) {
        if (!ids || ids.length === 0) return
        bulkScrapeDialog.gameIds = ids
        
        if (mode === "Metadata") {
            bulkScrapeDialog.scrapeMetadata = true
            bulkScrapeDialog.scrapeRetroAchievements = false
        } else if (mode === "RetroAchievements") {
            bulkScrapeDialog.scrapeMetadata = false
            bulkScrapeDialog.scrapeRetroAchievements = true
        } else {
            // Default (e.g. from context menu)
            bulkScrapeDialog.scrapeMetadata = true
            bulkScrapeDialog.scrapeRetroAchievements = false
        }

        bulkScrapeDialog.open()
    }

    QuitConfirmDialog {
        id: quitConfirmDialog
    }

    SettingsDialog {
        id: settingsDialog
        
        currentViewMode: appSettings.defaultView
        currentShowFilterBar: appSettings.showFilterBar
        currentDefaultRegion: appSettings.defaultRegion
        currentTheme: appSettings.themeName
        currentRaUser: appSettings.retroAchievementsUser
        currentRaToken: appSettings.retroAchievementsToken
        currentRaEnabled: appSettings.retroAchievementsEnabled
        currentShowTrayIcon: appSettings.showTrayIcon
        currentCloseToTray: appSettings.closeToTray
        
        currentAiEnabled: appSettings.aiEnabled
        currentOllamaUrl: appSettings.ollamaUrl
        currentOllamaModel: appSettings.ollamaModel
        currentAiDescriptionPrompt: appSettings.aiDescriptionPrompt
        
        currentDetailsPreferVideo: appSettings.detailsPreferVideo
        currentIgnoreTheInSort: appSettings.ignoreTheInSort
        currentDefaultIgnoreOnDelete: appSettings.defaultIgnoreOnDelete
        currentActiveMeta: appSettings.activeMetadataScraper
        currentActiveImage: appSettings.activeImageScraper
        
        currentGeminiKey: appSettings.geminiApiKey
        currentOpenaiKey: appSettings.openaiApiKey
        currentLlmProvider: appSettings.llmApiProvider
        currentSaveHeroicAssetsLocally: appSettings.saveHeroicAssetsLocally
        currentAutoRescanOnStartup: appSettings.autoRescanOnStartup
        currentConfirmOnQuit: appSettings.confirmOnQuit
        currentGridScale: appSettings.gridScale
        currentUseCustomYtdlp: appSettings.useCustomYtdlp
        currentCustomYtdlpPath: appSettings.customYtdlpPath
        currentDefaultProtonRunner: appSettings.defaultProtonRunner
        currentDefaultProtonPrefix: appSettings.defaultProtonPrefix
        currentDefaultProtonWrapper: appSettings.defaultProtonWrapper
        currentDefaultProtonUseGamescope: appSettings.defaultProtonUseGamescope
        currentDefaultProtonUseMangohud: appSettings.defaultProtonUseMangohud
        currentDefaultProtonGamescopeArgs: appSettings.defaultProtonGamescopeArgs
        currentDefaultProtonGamescopeW: appSettings.defaultProtonGamescopeW
        currentDefaultProtonGamescopeH: appSettings.defaultProtonGamescopeH
        currentDefaultProtonGamescopeOutW: appSettings.defaultProtonGamescopeOutW
        currentDefaultProtonGamescopeOutH: appSettings.defaultProtonGamescopeOutH
        currentDefaultProtonGamescopeRefresh: appSettings.defaultProtonGamescopeRefresh
        currentDefaultProtonGamescopeScaling: appSettings.defaultProtonGamescopeScaling
        currentDefaultProtonGamescopeUpscaler: appSettings.defaultProtonGamescopeUpscaler
        currentDefaultProtonGamescopeFullscreen: appSettings.defaultProtonGamescopeFullscreen
        currentHidePlatformsSidebar: appSettings.hidePlatformsSidebar
        currentCheckForUpdatesOnStartup: appSettings.checkForUpdatesOnStartup
        currentUseCustomLegendary: appSettings.useCustomLegendary
        currentCustomLegendaryPath: appSettings.customLegendaryPath
        currentDefaultInstallLocation: appSettings.defaultInstallLocation
        platformModel: sidebar.platformModel
        
        availableRegions: gameModel.getRegions()
        availableScrapers: gameModel.getAvailableScrapers()
        
        onSettingsApplied: (viewMode, showFilter, defRegion, themeName, raUser, raToken, raEnabled, showTray, closeToTray, aiEnabled, ollamaUrl, ollamaModel, detailsPreferVideo, ignoreTheInSort, aiDescriptionPrompt, defaultIgnoreOnDelete, activeMeta, activeImage, geminiKey, openaiKey, llmProvider, saveHeroicLocally, autoRescan, confirmQuit, gridScale, useCustomYtdlp, customYtdlpPath, defaultProtonRunner, defaultProtonPrefix, defaultProtonWrapper, defaultProtonUseGamescope, defaultProtonUseMangohud, defaultProtonGamescopeArgs, defaultProtonGamescopeW, defaultProtonGamescopeH, defaultProtonGamescopeOutW, defaultProtonGamescopeOutH, defaultProtonGamescopeRefresh, defaultProtonGamescopeScaling, defaultProtonGamescopeUpscaler, defaultProtonGamescopeFullscreen, hidePlatformsSidebar, checkUpdates, useCustomLegendary, customLegendaryPath, defaultInstallLocation) => {
             // Update Settings
             appSettings.defaultView = viewMode
             appSettings.showFilterBar = showFilter
             appSettings.defaultRegion = defRegion
             appSettings.themeName = themeName
             
             var raChanged = (appSettings.retroAchievementsUser !== raUser) || 
                             (appSettings.retroAchievementsToken !== raToken) ||
                             (appSettings.retroAchievementsEnabled !== raEnabled)
                             
             appSettings.retroAchievementsUser = raUser
             appSettings.retroAchievementsToken = raToken
             appSettings.retroAchievementsEnabled = raEnabled
             
             appSettings.showTrayIcon = showTray
             appSettings.closeToTray = closeToTray
             
             appSettings.aiEnabled = aiEnabled
             appSettings.ollamaUrl = ollamaUrl
             appSettings.ollamaModel = ollamaModel
             appSettings.aiDescriptionPrompt = aiDescriptionPrompt
             appSettings.geminiApiKey = geminiKey
             appSettings.openaiApiKey = openaiKey
             appSettings.llmApiProvider = llmProvider
             
             appSettings.detailsPreferVideo = detailsPreferVideo
             appSettings.ignoreTheInSort = ignoreTheInSort
             appSettings.defaultIgnoreOnDelete = defaultIgnoreOnDelete
             appSettings.activeMetadataScraper = activeMeta
             appSettings.activeImageScraper = activeImage
             appSettings.gridScale = gridScale
             
             appSettings.saveHeroicAssetsLocally = saveHeroicLocally
             appSettings.autoRescanOnStartup = autoRescan
             appSettings.confirmOnQuit = confirmQuit
             appSettings.useCustomYtdlp = useCustomYtdlp
             appSettings.customYtdlpPath = customYtdlpPath
             
             appSettings.defaultProtonRunner = defaultProtonRunner
             appSettings.defaultProtonPrefix = defaultProtonPrefix
             appSettings.defaultProtonWrapper = defaultProtonWrapper
             appSettings.defaultProtonUseGamescope = defaultProtonUseGamescope
             appSettings.defaultProtonUseMangohud = defaultProtonUseMangohud
             appSettings.defaultProtonGamescopeArgs = defaultProtonGamescopeArgs
             appSettings.defaultProtonGamescopeW = defaultProtonGamescopeW
             appSettings.defaultProtonGamescopeH = defaultProtonGamescopeH
             appSettings.defaultProtonGamescopeOutW = defaultProtonGamescopeOutW
             appSettings.defaultProtonGamescopeOutH = defaultProtonGamescopeOutH
             appSettings.defaultProtonGamescopeRefresh = defaultProtonGamescopeRefresh
             appSettings.defaultProtonGamescopeScaling = defaultProtonGamescopeScaling
             appSettings.defaultProtonGamescopeUpscaler = defaultProtonGamescopeUpscaler
             appSettings.defaultProtonGamescopeFullscreen = defaultProtonGamescopeFullscreen
             
             appSettings.hidePlatformsSidebar = hidePlatformsSidebar
             appSettings.checkForUpdatesOnStartup = checkUpdates
             appSettings.useCustomLegendary = useCustomLegendary
             appSettings.customLegendaryPath = customLegendaryPath
             appSettings.defaultInstallLocation = defaultInstallLocation
             
             appSettings.save()
             
             if (raChanged && raEnabled && raUser !== "") {
                 raBridge.fetchUserSummary(raUser, raToken)
             }
             
             // Apply region filter logic
             if (defRegion !== "" && defRegion !== "All Regions") {
                  gameModel.setRegionFilter(defRegion)
                  filterBar.selectRegion(defRegion)
             } else if (defRegion === "All Regions") {
                  gameModel.setRegionFilter("")
                  filterBar.selectRegion("All Regions")
             }
        }
    }

    Platform.SystemTrayIcon {
        id: trayIcon
        visible: appSettings.showTrayIcon
        icon.source: appInfo.getTrayIconPath()
        tooltip: "Theophany"

        menu: Platform.Menu {
            id: trayMenu
            onAboutToShow: refreshTrayRecentGames()

            Platform.MenuItem {
                text: "Recent Games"
                enabled: false
                visible: window.trayRecentGames.length > 0
            }

            Platform.MenuSeparator {
                visible: window.trayRecentGames.length > 0
            }

            Instantiator {
                model: window.trayRecentGames
                Platform.MenuItem {
                    // Indent with spaces and add a generic icon if no native icon shows
                    text: (modelData.icon ? "  " : "🎮 ") + modelData.title
                    icon.source: {
                        if (modelData.icon) {
                            var iconPath = modelData.icon
                            if (iconPath.startsWith("/")) return "file://" + iconPath
                            if (iconPath.startsWith("assets/")) return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + iconPath
                            return iconPath
                        }
                        return ""
                    }
                    onTriggered: gameModel.launchGame(modelData.id)
                }
                onObjectAdded: (index, object) => trayMenu.insertItem(index + 2, object) // +2 for label and separator
                onObjectRemoved: (index, object) => trayMenu.removeItem(object)
            }

            Platform.MenuSeparator {
                visible: window.trayRecentGames.length > 0
            }

            Platform.MenuItem {
                text: "Show"
                onTriggered: {
                    window.show()
                    window.raise()
                    window.requestActivate()
                }
            }
            Platform.MenuItem {
                text: "Settings"
                onTriggered: sidebar.settingsRequested()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: "Quit"
                onTriggered: Qt.quit()
            }
        }
        
        onActivated: (reason) => {
            if (reason === Platform.SystemTrayIcon.Trigger) {
                if (window.visible) {
                    window.hide()
                } else {
                    window.show()
                    window.raise()
                    window.requestActivate()
                }
            }
        }
    }

    AddSystemDialog {
        id: addSystemDialog
        platformModel: sidebar.platformModel
        appSettings: appSettings
        onSystemConfigured: (name, ext, path, cmd, emuId, emuName, pType, icon, pcConfig) => {
            if (addSystemDialog.editMode) {
                sidebar.updateSystem(addSystemDialog.platformId, name, ext, cmd, emuId, pType, icon, pcConfig)
            } else if (path === "") {
                // No path - just create the collection without importing anything
                gameModel.commitSystemImport(
                    name,
                    ext,
                    path,
                    cmd,
                    emuId,
                    pType,
                    icon,
                    pcConfig || "",
                    "[]"
                )
            } else {
                // New Flow: Preview first
                var json = gameModel.previewSystemImport(name, ext, path, emuId, pType)
                var roms = JSON.parse(json)
                
                romPreviewDialog.systemName = name
                romPreviewDialog.emulatorName = emuName
                romPreviewDialog.setRoms(roms)
                
                // Save other params for commit
                romPreviewDialog.tempParams = {
                    "platformId": "", // New system
                    "name": name,
                    "ext": ext,
                    "path": path,
                    "cmd": cmd,
                    "emuId": emuId,
                    "pType": pType,
                    "icon": icon,
                    "pcConfig": pcConfig
                }
                
                romPreviewDialog.open()
            }
        }
        onManageEmulatorsRequested: emulatorManager.open()
        onOpenImportRequested: (name, platformId) => {
            if (platformId !== "") {
                addContentDialog.isNewMode = false
                addContentDialog.newCollectionName = name
                
                // Find index in sidebar model
                var foundIdx = -1
                var targetId = String(platformId).trim()
                for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
                    var currentId = String(sidebar.platformModel.getId(i)).trim()
                    if (currentId === targetId) {
                        foundIdx = i
                        break
                    }
                }
                addContentDialog.existingCollectionIndex = foundIdx
            } else {
                addContentDialog.isNewMode = true
                addContentDialog.newCollectionName = name
                addContentDialog.existingCollectionIndex = -1
            }
            addContentDialog.isFolderMode = true
            addContentDialog.open()
        }
        onPlatformAdded: (id) => {
            sidebar.platformModel.refresh()
        }
        onPlatformDeleted: (id) => {
            sidebar.platformModel.refresh()
        }
        onDeleteCollectionRequested: (pid, name) => {
             window.deleteCollectionId = pid
             window.deleteCollectionName = name
             deleteCollectionDialog.open()
        }
    }


    AddContentDialog {
        id: addContentDialog
        platformModel: sidebar.platformModel
        
        onFolderSelected: (path, pid, name, exts, emuId, pType, icon, cmd, recursive) => {
            startContentPreview(path, pid, name, exts, emuId, pType, icon, cmd, recursive)
        }
        onFileSelected: (path, pid, name, exts, emuId, pType, icon, cmd) => {
            startContentPreview(path, pid, name, exts, emuId, pType, icon, cmd, false)
        }
    }
    
    function openImportFromDrop(url) {
        var path = decodeURIComponent(url.replace("file://", ""))
        var isDir = gameModel.isDirectory(url)
        
        // Suggest a collection name based on the path
        var suggestedName = ""
        var parts = path.split('/')
        // Remove trailing slash if any
        if (parts.length > 0 && parts[parts.length - 1] === "") {
            parts.pop()
        }
        
        if (isDir) {
            // If it's a directory, use the directory name itself
            suggestedName = parts.length > 0 ? parts[parts.length - 1] : ""
        } else {
            // If it's a file, use the parent directory name
            suggestedName = parts.length > 1 ? parts[parts.length - 2] : ""
        }
        
        // Reset dialog state
        addContentDialog.isNewMode = true 
        addContentDialog.newCollectionName = suggestedName
        addContentDialog.existingCollectionIndex = -1
        
        addContentDialog.isFolderMode = isDir
        addContentDialog.droppedPath = path
        addContentDialog.open()
    }

    function startContentPreview(path, pid, name, exts, emuId, pType, icon, cmd, recursive) {
        // Use existing preview logic
        var previewJson = gameModel.previewSystemImport(name, exts, path, emuId, pType, !!recursive)
        var roms = JSON.parse(previewJson)
        
        romPreviewDialog.systemName = name
        romPreviewDialog.emulatorName = "Auto" // Fallback name or find from emuId
        romPreviewDialog.setRoms(roms)
        
        romPreviewDialog.tempParams = {
            "platformId": pid,
            "name": name,
            "ext": exts,
            "path": path,
            "cmd": cmd,
            "emuId": emuId,
            "pType": pType,
            "icon": icon
        }
        romPreviewDialog.open()
    }

    ROMImportPreviewDialog {
        id: romPreviewDialog
        property var tempParams: ({})
        onImportRequested: (selectedRoms) => {
            var selectedJson = JSON.stringify(selectedRoms)
            if (tempParams.platformId && tempParams.platformId !== "") {
                 gameModel.commitContentImport(
                    tempParams.platformId,
                    tempParams.name,
                    tempParams.ext,
                    tempParams.path,
                    tempParams.cmd,
                    tempParams.emuId,
                    tempParams.pType,
                    tempParams.icon,
                    tempParams.pcConfig || "",
                    selectedJson
                )
            } else {
                 var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                 sidebar.platformModel.updateSystem(
                    newId,
                    tempParams.name,
                    tempParams.ext,
                    tempParams.cmd || "",
                    tempParams.emuId || "",
                    tempParams.pType || "",
                    tempParams.icon || "",
                    tempParams.pcConfig || ""
                 )
                 gameModel.commitContentImport(
                    newId,
                    tempParams.name,
                    tempParams.ext,
                    tempParams.path,
                    tempParams.cmd,
                    tempParams.emuId,
                    tempParams.pType,
                    tempParams.icon,
                    tempParams.pcConfig || "",
                    selectedJson
                )
            }
        }
    }

    AboutDialog {
        id: aboutDialog
        appInfo: appInfo
    }

    PlaylistManagerDialog {
        id: playlistManagerDialog
        dbPath: appInfo.getDataPath() + "/games.db"
        onPlaylistUpdated: {
             window.refreshPlaylists()
        }
    }

    ImportProgressDialog {
        id: importProgressDialog
        onClosed: {
            if (window.pendingBulkScrapeIds.length > 0) {
                 bulkScrapeDialog.showForGames(window.pendingBulkScrapeIds)
                 window.pendingBulkScrapeIds = [] // Clear
            }
        }
    }

    EmulatorManager {
        id: emulatorManager
        onClosed: {
            if (addSystemDialog.visible) {
                 addSystemDialog.refreshEmulators()
            }
        }
    }

    Dialog {
        id: deleteConfirmDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 450
        padding: 25
        
        property bool isFlatpak: false
        
        onAboutToShow: {
            if (window.deleteGameIds.length <= 1) {
                var path = gameModel.getRomPath(window.deleteGameId)
                isFlatpak = path.startsWith("flatpak://")
            } else {
                isFlatpak = false
            }
            uninstallFlatpakCheck.checked = false
            deleteDataCheck.checked = false
            ignoreCheck.checked = appSettings.defaultIgnoreOnDelete
        }

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.border
            border.width: 1
            radius: 12
        }

        contentItem: ColumnLayout {
            spacing: 20


            Text {
                text: window.deleteGameIds.length > 1 ? "Bulk Delete Games" : "Delete Game"
                color: Theme.text
                font.pixelSize: 22
                font.bold: true
                Layout.alignment: Qt.AlignLeft
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 }

            Label {
                text: window.deleteGameIds.length > 1 ?
                      "Are you sure you want to remove <b>" + window.deleteGameIds.length + " games</b> from your library?" :
                      "Are you sure you want to remove <b>" + window.deleteGameTitle + "</b> from your library?"
                color: Theme.text
                font.pixelSize: 15
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                CheckBox {
                    id: ignoreCheck
                    text: "Add to Ignore List (skip during rescan)"
                    Layout.fillWidth: true
                    palette.windowText: Theme.text
                    indicator: Rectangle {
                        implicitWidth: 18; implicitHeight: 18
                        x: ignoreCheck.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 3
                        border.color: ignoreCheck.checked ? Theme.accent : Theme.secondaryText
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: Theme.accent
                            visible: ignoreCheck.checked
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                    opacity: 0.2
                    visible: deleteConfirmDialog.isFlatpak
                }

                CheckBox {
                    id: uninstallFlatpakCheck
                    text: "Uninstall flatpak from system"
                    visible: deleteConfirmDialog.isFlatpak
                    Layout.fillWidth: true
                    palette.windowText: Theme.text
                    indicator: Rectangle {
                        implicitWidth: 18; implicitHeight: 18
                        x: uninstallFlatpakCheck.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 3
                        border.color: uninstallFlatpakCheck.checked ? Theme.accent : Theme.secondaryText
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: Theme.accent
                            visible: uninstallFlatpakCheck.checked
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }
                }

                CheckBox {
                    id: deleteDataCheck
                    text: "Delete game configuration and data"
                    visible: uninstallFlatpakCheck.visible && uninstallFlatpakCheck.checked
                    checked: false
                    leftPadding: 30
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    palette.windowText: Theme.secondaryText
                    indicator: Rectangle {
                        implicitWidth: 18; implicitHeight: 18
                        x: deleteDataCheck.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 3
                        border.color: deleteDataCheck.checked ? Theme.accent : Theme.secondaryText
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: Theme.accent
                            visible: deleteDataCheck.checked
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.2 }

                CheckBox {
                    id: deleteAssetsCheck
                    text: "Delete physical images and metadata sidecars"
                    checked: false
                    Layout.fillWidth: true
                    palette.windowText: Theme.text
                    indicator: Rectangle {
                        implicitWidth: 18; implicitHeight: 18
                        x: deleteAssetsCheck.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 3
                        border.color: deleteAssetsCheck.checked ? Theme.accent : Theme.secondaryText
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: Theme.accent
                            visible: deleteAssetsCheck.checked
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }
                }
            }

            Item { height: 10 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                
                Item { Layout.fillWidth: true }
                
                TheophanyButton {
                    text: "Cancel"
                    onClicked: deleteConfirmDialog.close()
                }
                
                TheophanyButton {
                    text: "Remove"
                    primary: true
                    onClicked: {
                        if (window.deleteGameIds.length > 1) {
                            gameModel.deleteGamesBulk(JSON.stringify(window.deleteGameIds), ignoreCheck.checked, deleteAssetsCheck.checked)
                        } else {
                            gameModel.deleteGame(window.deleteGameId, ignoreCheck.checked, uninstallFlatpakCheck.checked, deleteDataCheck.checked, deleteAssetsCheck.checked)
                        }
                        deleteConfirmDialog.accept()
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteCollectionDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 450
        padding: 25

        property bool deleteAssets: false

        onClosed: {
            deleteAssets = false
        }

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.border
            border.width: 1
            radius: 12
        }

        contentItem: ColumnLayout {
            spacing: 20

            Text {
                text: "Delete Collection"
                color: Theme.text
                font.pixelSize: 22
                font.bold: true
                Layout.alignment: Qt.AlignLeft
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 }

            Label {
                text: "Are you sure you want to delete <b>" + window.deleteCollectionName + "</b>?<br><br>This will remove the collection and its games from the app library.<br><br>Note: Your game files on disk will NOT be deleted."
                color: Theme.text
                font.pixelSize: 15
                wrapMode: Text.WordWrap
                textFormat: Text.RichText
                Layout.fillWidth: true
            }

            CheckBox {
                id: deleteCollectionAssetsCheck
                text: "Delete local metadata and assets"
                checked: deleteCollectionDialog.deleteAssets
                onCheckedChanged: deleteCollectionDialog.deleteAssets = checked
                Layout.fillWidth: true
                palette.windowText: Theme.text
                indicator: Rectangle {
                    implicitWidth: 18; implicitHeight: 18
                    x: deleteCollectionAssetsCheck.leftPadding
                    y: parent.height / 2 - height / 2
                    radius: 3
                    border.color: deleteCollectionAssetsCheck.checked ? Theme.accent : Theme.secondaryText
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.accent
                        visible: deleteCollectionAssetsCheck.checked
                        font.bold: true
                        font.pixelSize: 14
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                
                Item { Layout.fillWidth: true }
                
                TheophanyButton {
                    text: "Cancel"
                    onClicked: deleteCollectionDialog.close()
                }
                
                TheophanyButton {
                    text: "Delete"
                    primary: true
                    onClicked: {
                         sidebar.platformModel.deleteSystem(window.deleteCollectionId, deleteCollectionDialog.deleteAssets)
                         // Signal deletion if current view was this platform
                         if (sidebar.activeViewType === "platform" && sidebar.activeId === window.deleteCollectionId) {
                              sidebar.activeViewType = "all"
                              window.currentPlatformId = ""
                              window.currentViewTitle = "All Games"
                              window.currentPlatformIcon = "🎮"
                              gameModel.refresh()
                         }
                         addSystemDialog.selectedIndex = -1
                         sidebar.systemDeleted()
                         deleteCollectionDialog.accept()
                    }
                }
            }
        }
    }

    ScrapeSearchDialog {
        id: mainScrapeDialog
        property string gameId: ""
        property int pendingDownloads: 0
        
        ollamaUrl: appSettings.ollamaUrl
        ollamaModel: appSettings.ollamaModel
        geminiKey: appSettings.geminiApiKey
        openaiKey: appSettings.openaiApiKey
        llmProvider: appSettings.llmApiProvider
        preferredScraper: appSettings.activeMetadataScraper
        preferredImageScraper: appSettings.activeImageScraper
        
        onOpened: {

            // Auto-fetch platform if we have gameId but no platform
            if (gameId !== "" && platform === "") {

                try {
                    var metaJson = gameModel.getGameMetadata(gameId)
                    var meta = JSON.parse(metaJson)
                    // We need platform info. 
                    // Wait, getGameMetadata returns metadata from the DB. Does it have platform?
                    // Let's check the Rust implementation. 
                    // Actually, let's use a more direct method if available.
                    
                    // Fallback to model data but with a safer check
                    var index = gameModel.getRowById(gameId)
                    if (index >= 0) {
                        var pType = gameModel.data(gameModel.index(index, 0), 261)
                        var pName = gameModel.data(gameModel.index(index, 0), 260)
                        platform = (pType && pType !== "--") ? pType : ((pName && pName !== "--") ? pName : "")

                    }
                } catch (e) {
 
                }
            } else if (gameId === "") {

            }
        }
        
        onResultSelected: (sourceId, provider) => {
            mainScrapeDialog.fetchingDetails = true
            gameModel.fetchOnlineMetadata(sourceId, provider, appSettings.ollamaUrl, appSettings.ollamaModel, appSettings.geminiApiKey, appSettings.openaiApiKey, appSettings.llmApiProvider)
        }
        onImageSelected: (url, category) => {
             pendingDownloads++
             gameModel.downloadAsset(mainScrapeDialog.gameId, category, url)
        }
    }

    MetadataCompareDialog {
        id: mainCompareDialog
        onMetadataApplied: (data) => {
            // Update game via model
             gameModel.updateGameMetadata(mainScrapeDialog.gameId, JSON.stringify(data))
             // Force refresh logic might be needed if not auto-handled by signals
             window.loadGameDetails(gameModel.getRowById(mainScrapeDialog.gameId))
        }
    }


    Platform.MessageDialog {
        id: mainAutoScrapeErrorDialog
        title: "Auto Fetch Failed"
        buttons: Platform.MessageDialog.Ok
        onAccepted: {
            mainScrapeDialog.currentTab = 0
            mainScrapeDialog.open()
        }
    }

    Connections {
        target: gameModel
        
        function onAutoScrapeFinished(rom_id, json) {
            // If the Edit Dialog is open, it handles its own auto-scrape logic.
            if (gameEditDialog.visible) {

                 return;
            }
            
            try {
                var data = JSON.parse(json)
                var id = rom_id 
                if (!id) {
 
                    return
                }


                
                var currentJson = gameModel.getGameMetadata(id)
                var currentData = JSON.parse(currentJson)
                
                var merged = {
                    title: currentData.title, // NEVER OVERWRITE TITLE (as requested)
                    description: data.description || currentData.description || "",
                    developer: data.developer || currentData.developer || "",
                    publisher: data.publisher || currentData.publisher || "",
                    genre: data.genre || currentData.genre || "",
                    tags: data.tags || currentData.tags || "",
                    region: data.region || currentData.region || "",
                    rating: (data.rating !== undefined && data.rating !== 0) ? data.rating : (currentData.rating || 0),
                    release_date: (data.release_year !== undefined && data.release_year !== 0) ? data.release_year.toString() : (currentData.release_date || "")
                }
                
                // Merge Assets (Overwrite/Add new)
                if (data.assets) {
                    merged.assets = {}
                    for (var k in data.assets) {
                         merged.assets[k] = data.assets[k]
                    }
                }
                

                gameModel.updateGameMetadata(id, JSON.stringify(merged))
                
                // Add Resources (Links)
                if (data.resources && Array.isArray(data.resources)) {

                     for (var i = 0; i < data.resources.length; i++) {
                         var r = data.resources[i]
                         if (r.url && r.url !== "") {
                              gameModel.addGameResource(id, r.type || "Link", r.url, r.label || "")
                         }
                     }
                }
                
                // Refresh details if this is the currently selected game
                
                // Refresh details if this is the currently selected game (Check index-based ID)
                var currentIndex = (viewStack.currentIndex === 0) ? gameGrid.currentIndex : gameList.currentIndex;
                var currentId = (currentIndex >= 0) ? gameModel.getGameId(currentIndex) : ""
                

                
                if (String(currentId) === String(id)) {

                    loadGameDetails(currentIndex)
                }
            } catch (e) {

            }
        }

        function onAutoScrapeFailed(rom_id, message) {
            // Only show if we initiated it from Main context (Edit Dialog is closed)
            if (gameEditDialog.visible) return;


             mainAutoScrapeErrorDialog.text = message
             mainAutoScrapeErrorDialog.open()
        }

        function onFetchFinished(json) {
            mainScrapeDialog.fetchingDetails = false // Reset busy state
            if (mainScrapeDialog.visible) {
                 try {
                    var meta = JSON.parse(json)
                    // We need current game data for comparison
                    var id = mainScrapeDialog.gameId
                    var currentJson = gameModel.getGameMetadata(id)
                    var currentData = JSON.parse(currentJson)
                    
                    var current = {
                        title: currentData.title || "",
                        description: currentData.description || "",
                        developer: currentData.developer || "",
                        publisher: currentData.publisher || "",
                        genre: currentData.genre || "",
                        tags: currentData.tags || "",
                        region: currentData.region || "",
                        rating: currentData.rating || 0,
                        release_year: currentData.release_date || 0,
                        resources: currentData.resources || []
                    }
                    
                    mainScrapeDialog.close()
                    mainCompareDialog.init(current, meta)
                    mainCompareDialog.open()
                 } catch (e) { 

                     mainScrapeDialog.showToast("Error processing metadata: " + e, true)
                 }
            }
        }

        function onFetchFailed(message) {
            mainScrapeDialog.fetchingDetails = false
            if (mainScrapeDialog.visible) {

                mainScrapeDialog.showToast("Failed to fetch metadata: " + message, true)
            }
        }
        
        function onAssetDownloadFinished(category, localPath) {
             // If we are in the context of the main scrape dialog (tracked via pendingDownloads)
            if (mainScrapeDialog.pendingDownloads > 0) {
                mainScrapeDialog.pendingDownloads-- 
                
                // Then refresh details for the currently viewed game if it matches
                if (detailsPanel.gameId === mainScrapeDialog.gameId) {
                     var row = gameModel.getRowById(mainScrapeDialog.gameId)
                     if (row >= 0) window.loadGameDetails(row)
                }
            }
        }
    }

    function refreshPlaylists() {
        sidebar.refresh()
        playlistModel.refresh()
    }

    MassEditDialog {
        id: massEditDialog
    }
    
    function openMassEdit(ids) {
        massEditDialog.openFor(ids)
    }

    RetroAchievementsDashboard {
        id: raDashboard
    }

    function openRaDashboard() {
        if (appSettings.retroAchievementsEnabled && appSettings.retroAchievementsUser !== "") {
            raBridge.fetchUserSummary(appSettings.retroAchievementsUser, appSettings.retroAchievementsToken)
        }
        raDashboard.open()
    }
}
