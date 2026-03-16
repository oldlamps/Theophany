import QtQuick
import "../components"
import "../style"
import QtQuick.Controls
import QtQuick.Layouts
import Theophany.Bridge 1.0

FocusScope {
    id: rootRoot
    
    // Forward focus to listview
    property alias currentIndex: listView.currentIndex
    property alias count: listView.count
    property alias model: listView.model
    property var selectedIndices: []
    property int selectionAnchor: -1
    property bool ignoreNextReset: false
    
    function selectAll() {
        var newSel = []
        for (var i = 0; i < count; i++) {
            newSel.push(i)
        }
        selectedIndices = newSel
    }

    function updateRangeSelection(targetIndex) {
        if (selectionAnchor === -1) selectionAnchor = currentIndex
        var start = Math.min(selectionAnchor, targetIndex)
        var end = Math.max(selectionAnchor, targetIndex)
        var newSel = []
        for (var i = start; i <= end; i++) {
            newSel.push(i)
        }
        ignoreNextReset = true
        selectedIndices = newSel
        currentIndex = targetIndex // Primary focus follows
    }
    
    // Reset selection when model changes or sort changes
    Connections {
        target: gameModel
        function onSortMethodChanged() {
            var method = gameModel.sortMethod
            if (method === "TitleAZ") {
                sortColumn = "Title"
                sortDescending = false
            } else if (method === "TitleZA" || method === "TitleDESC") {
                sortColumn = "Title"
                sortDescending = true
            } else if (method === "Recent") {
                sortColumn = ""
                sortDescending = false
            } else if (method.endsWith("DESC")) {
                sortColumn = method.substring(0, method.length - 4)
                sortDescending = true
            } else {
                sortColumn = method
                sortDescending = false
            }
        }
    }

    function positionViewAtIndex(index, mode) {
        listView.positionViewAtIndex(index, mode)
    }

    // Sorting State
    property string sortColumn: "Title"
    property bool sortDescending: false

    function toggleSort(column) {
        if (sortColumn === column) {
            sortDescending = !sortDescending
        } else {
            sortColumn = column
            sortDescending = false
            // Default to descending for specific numeric fields if logical? No, standard is ASC first.
            if (column === "Year" || column === "Rating") sortDescending = true
        }
        
        var method = sortColumn + (sortDescending ? "DESC" : "")
        gameModel.setSortMethod(method)
        listView.forceActiveFocus()
    }

    // --- Column Width State ---
    QtObject {
        id: colWidths
        property int icon: 30
        property int title: 265
        property int platform: 150
        property int region: 80
        property int genre: 150
        property int developer: 150
        property int publisher: 150
        property int year: 60
        property int rating: 60
        property int tags: 200
        // Path fills remaining space
    }

    // Helper to calculate X positions consistently
    // Spacing is 10px between columns in the header RowLayout logic
    // We need to match that in the manual positioning of the delegate
    // Header Structure:
    // Spacer(5) + IconRegion(30) + Gap(10) + Title(W) + Gap(10) ...
    // Actually, looking at previous code:
    // Header had: anchors.leftMargin: 5, spacing: 10
    // Item { width: 30 } (Icon placeholder) ...
    
    function getX(colName) {
        // Base start X (matches header leftMargin)
        var x = 5; 
        var gap = 10;

        // 1. Icon (Always first, fixed structural column)
        if (colName === "icon") return x;
        x += colWidths.icon + gap;

        // 2. Title
        if (colName === "title") return x;
        x += colWidths.title + gap;

        // 3. Platform
        if (colName === "platform") return x;
        x += colWidths.platform + gap;

        // 4. Region
        if (colName === "region") return x;
        x += colWidths.region + gap;

        // 5. Genre
        if (colName === "genre") return x;
        x += colWidths.genre + gap;

        // 6. Developer
        if (colName === "developer") return x;
        x += colWidths.developer + gap;

        // 7. Publisher
        if (colName === "publisher") return x;
        x += colWidths.publisher + gap;

        // 8. Year
        if (colName === "year") return x;
        x += colWidths.year + gap;

        // 9. Rating
        if (colName === "rating") return x;
        x += colWidths.rating + gap;

        // 10. Tags
        if (colName === "tags") return x;
        x += colWidths.tags + gap;

        // 11. Path
        if (colName === "path") return x;
        
        return x;
    }

    // Horizontal Scroll Wrapper
    Flickable {
        id: horizontalFlick
        anchors.fill: parent
        
        // Calculate total content width dynamically
        contentWidth: Math.max(parent.width, getX("path") + 200) // Ensure some space for path
        contentHeight: parent.height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        
        ScrollBar.horizontal: TheophanyScrollBar { 
            policy: ScrollBar.AlwaysOn
            height: 12
            anchors.bottom: parent.bottom
        }

        Column {
            width: horizontalFlick.contentWidth
            height: parent.height

            // Header
            Rectangle {
                width: parent.width
                height: 35
                color: Theme.secondaryBackground
                z: 2
                
                Row { // Using Row instead of RowLayout for absolute control with ResizeHandles
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    spacing: 10
                    
                    // Component for Header Button with Resize Handle
                    component HeaderButton: Item {
                        id: hbRoot
                        property string text
                        property string sortId
                        property string widthProp // Name of property in colWidths
                        
                        width: colWidths[widthProp]
                        height: parent.height

                        // Sort Interaction
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 5 // Leave room for resize handle
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootRoot.toggleSort(sortId)
                            
                            RowLayout {
                                anchors.fill: parent
                                spacing: 2
                                Text { 
                                    text: hbRoot.text
                                    color: rootRoot.sortColumn === hbRoot.sortId ? Theme.text : Theme.secondaryText
                                    font.bold: true
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: rootRoot.sortDescending ? "▼" : "▲"
                                    color: Theme.text
                                    visible: rootRoot.sortColumn === hbRoot.sortId
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Resize Handle
                        MouseArea {
                            width: 10 // Hit area
                            height: parent.height
                            anchors.right: parent.right
                            anchors.rightMargin: -5 // Center over the gap
                            cursorShape: Qt.SplitHCursor
                            preventStealing: true
                            z: 10
                            
                            property int startX: 0
                            property int startWidth: 0
                            
                            onPressed: (mouse) => {
                                // Use global/root coordinates to avoid feedback loop when parent resizes
                                var p = mapToItem(rootRoot, mouse.x, mouse.y)
                                startX = p.x
                                startWidth = colWidths[widthProp]
                            }
                            
                            onPositionChanged: (mouse) => {
                                var p = mapToItem(rootRoot, mouse.x, mouse.y)
                                var delta = p.x - startX
                                var newWidth = Math.max(30, startWidth + delta)
                                colWidths[widthProp] = newWidth
                                rootRoot.triggerSave()
                            }
                        }
                    }

                    // 1. Icon Spacer (Not sortable, fixed structural)
                    Item { 
                        width: colWidths.icon
                        height: parent.height 
                        // No text, just spacer
                    }

                    // 2. Title
                    HeaderButton { text: "TITLE"; sortId: "Title"; widthProp: "title" }
                    
                    // 3. Platform
                    HeaderButton { text: "Platform"; sortId: "Platform"; widthProp: "platform" }
                    
                    // 4. Region
                    HeaderButton { text: "Region"; sortId: "Region"; widthProp: "region" }
                    
                    // 5. Genre
                    HeaderButton { text: "Genre"; sortId: "Genre"; widthProp: "genre" }
                    
                    // 6. Developer
                    HeaderButton { text: "Developer"; sortId: "Developer"; widthProp: "developer" }
                    
                    // 7. Publisher
                    HeaderButton { text: "Publisher"; sortId: "Publisher"; widthProp: "publisher" }
                    
                    // 8. Year
                    HeaderButton { text: "Year"; sortId: "Year"; widthProp: "year" }
                    
                    // 9. Rating
                    HeaderButton { text: "Rating"; sortId: "Rating"; widthProp: "rating" }
                    
                    // 10. Tags
                    HeaderButton { text: "Tags"; sortId: "Tags"; widthProp: "tags" }
                    
                    // 11. Path (Not sortable, fills rest)
                    Item {
                        width: 100 // Minimum width for label
                        height: parent.height
                        Label { 
                            text: "Path"; color: Theme.secondaryText; font.bold: true; 
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
            }

            // List
            ListView {
                id: listView
                width: parent.width
                height: parent.height - 35
                clip: true
                focus: true
                highlightMoveDuration: 0
                flickableDirection: Flickable.VerticalFlick
                
                // Performance optimizations for large lists (4500+ items)
                cacheBuffer: 500 // Increase cache buffer to pre-render more items off-screen
                reuseItems: true // Reuse delegate items instead of creating/destroying
                displayMarginBeginning: 100 // Reduce overdraw at the beginning
                displayMarginEnd: 100 // Reduce overdraw at the end
                
                // Key handling reused
                Keys.onReturnPressed: {
                    if (currentIndex >= 0) {
                        var id = gameModel.getGameId(currentIndex)
                        window.launchGame(id)
                    }
                }
                
                Keys.onPressed: (event) => {
                    var isShift = event.modifiers & Qt.ShiftModifier
                    var isCtrl = event.modifiers & Qt.ControlModifier
                    
                    if (event.key === Qt.Key_A && isCtrl) {
                        rootRoot.selectAll()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                        if (isShift) {
                            var newIdx = event.key === Qt.Key_Up ? Math.max(0, currentIndex - 1) : Math.min(count - 1, currentIndex + 1)
                            rootRoot.updateRangeSelection(newIdx)
                            event.accepted = true
                        } else if (isCtrl) {
                            rootRoot.ignoreNextReset = true
                        }
                    }
                }

                Keys.onTabPressed: (event) => { event.accepted = true }
                Keys.onBacktabPressed: (event) => { event.accepted = true }

                onCurrentIndexChanged: { 
                    if (currentIndex >= 0 && focus) {
                        // Reset selection if not in a multi-selection state (manual movement without Shift/Ctrl)
                        if (!rootRoot.ignoreNextReset) {
                            rootRoot.selectedIndices = [currentIndex]
                            rootRoot.selectionAnchor = currentIndex
                        }
                        rootRoot.ignoreNextReset = false
                        window.loadGameDetails(currentIndex) 
                    }
                }

                delegate: Rectangle {
                    width: listView.width
                    height: 30
                    
                    // --- Optimized Static Layout using calculated X positions ---
                    
                    // Icon
                    Item {
                        x: rootRoot.getX("icon"); width: colWidths.icon; height: parent.height
                        Image {
                            id: listGameIcon
                            anchors.centerIn: parent
                            width: Math.min(parent.width, 24); height: 24
                            source: gameIcon
                            fillMode: Image.PreserveAspectFit
                            visible: source != ""
                            cache: true
                            asynchronous: true
                            sourceSize: Qt.size(24, 24)
                            opacity: (typeof gameIsInstalled !== "undefined" && !gameIsInstalled) ? 0.5 : 1.0
                        }

                        // Cloud badge for uninstalled games
                        Rectangle {
                            visible: typeof gameIsInstalled !== "undefined" && !gameIsInstalled
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: 2
                            anchors.rightMargin: 0
                            width: 16; height: 16
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.65)

                            Text {
                                anchors.centerIn: parent
                                text: "☁"
                                color: "white"
                                font.pixelSize: 9
                                lineHeight: 1.0
                                lineHeightMode: Text.FixedHeight
                                height: 14
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Running indicator badge
                        Rectangle {
                            visible: (typeof gameIsRunning !== "undefined") && gameIsRunning
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.bottomMargin: 2
                            anchors.leftMargin: 0
                            width: 16; height: 16
                            radius: 8
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "▶\ufe0e"
                                color: "white"
                                font.pixelSize: 8
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Title
                    Text { 
                        x: rootRoot.getX("title"); width: colWidths.title
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameTitle 
                        color: Theme.text 
                        elide: Text.ElideRight
                    }
                    
                    // Platform (Icon + Name)
                    Item {
                        x: rootRoot.getX("platform"); width: colWidths.platform; height: parent.height
                        Image {
                            id: pIcon
                            width: 16; height: 16
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            fillMode: Image.PreserveAspectFit
                            visible: source != ""
                            source: gamePlatformIcon
                            sourceSize.width: 32
                            sourceSize.height: 32
                            mipmap: true
                            asynchronous: true
                        }
                        Text { 
                            anchors.left: pIcon.right; anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: gamePlatformType ? gamePlatformType : gamePlatformName
                            color: Theme.secondaryText
                            elide: Text.ElideRight
                        }
                    }
                    
                    // Region
                    Text { 
                        x: rootRoot.getX("region"); width: colWidths.region
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameRegion ? gameRegion : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Genre
                    Text {
                        x: rootRoot.getX("genre"); width: colWidths.genre
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameGenre ? gameGenre : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Developer
                    Text {
                        x: rootRoot.getX("developer"); width: colWidths.developer
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameDeveloper ? gameDeveloper : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Publisher
                    Text {
                        x: rootRoot.getX("publisher"); width: colWidths.publisher
                        anchors.verticalCenter: parent.verticalCenter
                        text: gamePublisher ? gamePublisher : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Year
                    Text {
                        x: rootRoot.getX("year"); width: colWidths.year
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameReleaseYear && gameReleaseYear > 0 ? gameReleaseYear : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Rating
                    Text {
                        x: rootRoot.getX("rating"); width: colWidths.rating
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameRating && gameRating > 0 ? gameRating.toFixed(1) : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Tags
                    Text {
                        x: rootRoot.getX("tags"); width: colWidths.tags
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameTags ? gameTags : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    // Path
                    Text { 
                        x: rootRoot.getX("path"); 
                        width: parent.width - x - 5
                        anchors.verticalCenter: parent.verticalCenter
                        text: gamePath
                        color: Theme.secondaryText
                        elide: Text.ElideLeft
                    }
                    
                    // Selection/Hover state
                    // Check if index is in selectedIndices array OR if it's the current keyboard focus
                    readonly property bool isSelected: rootRoot.selectedIndices.indexOf(index) !== -1 || (index === listView.currentIndex && listView.activeFocus)
                    color: isSelected ? Qt.alpha(Theme.accent, 0.4) : (ma.containsMouse ? Theme.hover : (index % 2 === 0 ? Qt.alpha(Theme.text, 0.05) : "transparent"))

                    MouseArea { 
                        id: ma; 
                        anchors.fill: parent; 
                        hoverEnabled: true; 
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        propagateComposedEvents: true // Allow flick gestures to propagate to ListView
                        onClicked: (mouse) => { 
                            listView.forceActiveFocus()
                            
                            // Multi-Selection Logic
                            if (mouse.button === Qt.LeftButton) {
                                if (mouse.modifiers & Qt.ControlModifier) {
                                    // Toggle selection
                                    var current = rootRoot.selectedIndices.slice() // Clone
                                    var idx = current.indexOf(index)
                                    rootRoot.ignoreNextReset = true
                                    if (idx !== -1) {
                                        current.splice(idx, 1)
                                        rootRoot.selectedIndices = current
                                    } else {
                                        current.push(index)
                                        rootRoot.selectedIndices = current
                                        listView.currentIndex = index // Primary focus
                                        rootRoot.selectionAnchor = index
                                    }
                                } else if (mouse.modifiers & Qt.ShiftModifier) {
                                    // Range selection using anchor
                                    rootRoot.updateRangeSelection(index)
                                } else {
                                    // Single selection
                                    listView.currentIndex = index
                                    rootRoot.selectedIndices = [index]
                                    rootRoot.selectionAnchor = index
                                }
                            } else if (mouse.button === Qt.RightButton) {
                                // If right clicking on an item NOT in selection, select it solely
                                if (rootRoot.selectedIndices.indexOf(index) === -1) {
                                    listView.currentIndex = index
                                    rootRoot.selectedIndices = [index]
                                }
                                contextMenu.popup()
                            }
                            mouse.accepted = true
                        } 
                        onDoubleClicked: window.launchGame(gameId)
                        
                        TheophanyMenu {
                            id: contextMenu
                            
                            // Mass Edit Option
                            TheophanyMenuItem {
                                text: "Mass Edit (" + rootRoot.selectedIndices.length + ")"
                                iconSource: "📝"
                                visible: rootRoot.selectedIndices.length > 1
                                onTriggered: {
                                    var ids = []
                                    for (var i = 0; i < rootRoot.selectedIndices.length; i++) {
                                        ids.push(gameModel.getGameId(rootRoot.selectedIndices[i]))
                                    }
                                    window.openMassEdit(ids)
                                }
                            }
                            TheophanyMenuSeparator { visible: rootRoot.selectedIndices.length > 1 }

                            TheophanyMenuItem {
                                text: "Run Game"
                                iconSource: "🚀"
                                visible: rootRoot.selectedIndices.length === 1
                                onTriggered: window.launchGame(gameId)
                            }
                            TheophanyMenuItem {
                                text: "Uninstall Game"
                                iconSource: "🗑️"
                                visible: rootRoot.selectedIndices.length === 1
                                         && (typeof gamePlatformType !== "undefined" && gamePlatformType.toLowerCase() === "steam")
                                         && (typeof gameIsInstalled !== "undefined" && gameIsInstalled)
                                onTriggered: gameModel.uninstallSteamGame(gameId)
                            }
                            TheophanyMenuSeparator { visible: rootRoot.selectedIndices.length === 1 }
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
                                            contextMenu.close()
                                            listView.forceActiveFocus()
                                            for(var i=0; i<rootRoot.selectedIndices.length; i++) {
                                                var gId = gameModel.getGameId(rootRoot.selectedIndices[i])
                                                gameModel.addToPlaylist(playlistId, gId)
                                            }
                                            playlistModel.refresh()
                                        }
                                    }
                                    onObjectAdded: (index, object) => addToPlaylistMenu.insertItem(index, object)
                                    onObjectRemoved: (index, object) => addToPlaylistMenu.removeItem(object)
                                }
                                TheophanyMenuSeparator { visible: playlistModel.rowCount() > 0 }
                                TheophanyMenuItem {
                                    text: "Create New Playlist..."
                                    iconSource: "➕"
                                    onTriggered: {
                                        newPlaylistDialog.open()
                                        contextMenu.close()
                                    }
                                }
                            }
                            TheophanyMenu {
                                id: metadataMenu
                                title: "Metadata"
                                property string iconSource: "📋"
                                
                                TheophanyMenuItem {
                                    text: rootRoot.selectedIndices.length > 1 ? "Bulk Auto-Scrape..." : "Auto Populate Metadata"
                                    iconSource: "🤖"
                                    onTriggered: {
                                        if (rootRoot.selectedIndices.length > 1) {
                                            var ids = []
                                            for (var i = 0; i < rootRoot.selectedIndices.length; i++) {
                                                ids.push(gameModel.getGameId(rootRoot.selectedIndices[i]))
                                            }
                                            window.openBulkScrape(ids)
                                        } else {
                                            // Get game ID and title from model using index
                                            var gId = gameModel.getGameId(index)
                                            var gTitle = gameTitle
                                            
                                            // Store ID in the dialog for context (same as Shift+A)
                                            mainScrapeDialog.gameId = gId
                                            mainScrapeDialog.query = gTitle
                                            

                                            gameModel.autoScrape(gId)
                                        }
                                    }
                                }
                                TheophanyMenuItem {
                                    text: "Fetch Enhanced Steam Metadata"
                                    iconSource: "qrc:/ui/assets/systems/steam.png"
                                    visible: (typeof gamePlatformType !== "undefined" && gamePlatformType.toLowerCase() === "steam") || (typeof gamePlatformName !== "undefined" && gamePlatformName.toLowerCase() === "steam") || gameId.startsWith("steam-")
                                    onTriggered: {
                                        if (rootRoot.selectedIndices.length > 1) {
                                            var ids = []
                                            for (var i = 0; i < rootRoot.selectedIndices.length; i++) {
                                                ids.push(gameModel.getGameId(rootRoot.selectedIndices[i]))
                                            }
                                            bulkScrapeDialog.showForGames(ids, "Steam")
                                        } else {
                                            var gId = gameModel.getGameId(index)
                                            bulkScrapeDialog.showForGames([gId], "Steam")
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
                                        // Get game ID and title from model
                                        var gId = gameModel.getGameId(index)
                                        var gTitle = gameTitle
                                        
                                        // Open scrape dialog (same as Shift+S)
                                        mainScrapeDialog.gameId = gId
                                        mainScrapeDialog.query = gTitle
                                        mainScrapeDialog.platform = gamePlatformName ? gamePlatformName : gamePlatformType
                                        mainScrapeDialog.targetCategory = "Box - Front" // Default
                                        mainScrapeDialog.currentTab = 0
                                        mainScrapeDialog.open()
                                    }
                                }
                                TheophanyMenuItem {
                                    text: "Refresh Assets"
                                    iconSource: "🔄"
                                    onTriggered: {
                                        for(var i=0; i<rootRoot.selectedIndices.length; i++) {
                                            var gId = gameModel.getGameId(rootRoot.selectedIndices[i])
                                            gameModel.refreshGameAssets(gId)
                                        }
                                    }
                                }
                                TheophanyMenuItem {
                                    text: "Refresh Extras"
                                    iconSource: "qrc:/ui/assets/systems/exodos.png"
                                    visible: gamePlatformName === "eXoDOS" && rootRoot.selectedIndices.length === 1
                                    onTriggered: gameModel.refreshExoDosResources(gameId)
                                }
                            }
                            TheophanyMenuItem {
                                text: "Video Explorer"
                                iconSource: "🎬"
                                visible: rootRoot.selectedIndices.length === 1
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
                                visible: rootRoot.selectedIndices.length === 1
                                onTriggered: {
                                    // Open image viewer (same as I key)
                                    detailsPanel.openImageViewer()
                                }
                            }
                            TheophanyMenuSeparator {}
                            TheophanyMenuItem {
                                text: gameIsFavorite ? "Remove from Favorites" : "Add to Favorites"
                                iconSource: "⭐"
                                onTriggered: {
                                     for(var i=0; i<rootRoot.selectedIndices.length; i++) {
                                        var gId = gameModel.getGameId(rootRoot.selectedIndices[i])
                                        // Logic is tricky for bulk toggle; usually "Set" is better, but toggle per item works
                                        gameModel.toggleFavorite(gId)
                                    }
                                }
                            }
                            TheophanyMenuItem {
                                text: "Game Properties"
                                iconSource: "📝"
                                visible: rootRoot.selectedIndices.length === 1
                                onTriggered: window.openGameEdit(gameId)
                            }
                            TheophanyMenuSeparator {}
                            TheophanyMenuItem {
                                text: "Delete from Library"
                                iconSource: "🗑️"
                                onTriggered: {
                                    if (rootRoot.selectedIndices.length <= 1) {
                                        window.deleteGameId = gameId
                                        window.deleteGameTitle = gameTitle
                                        window.deleteGameIds = [gameId]
                                        deleteConfirmDialog.open()
                                    } else {
                                        var ids = []
                                        for (var i = 0; i < rootRoot.selectedIndices.length; i++) {
                                            ids.push(gameModel.getGameId(rootRoot.selectedIndices[i]))
                                        }
                                        window.deleteGameIds = ids
                                        deleteConfirmDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    TheophanyScrollBar {
        id: vBar
        anchors.top: parent.top
        anchors.bottom: parent.bottom 
        anchors.right: parent.right
        anchors.topMargin: 35 
        anchors.bottomMargin: 12
        
        policy: ScrollBar.AlwaysOn
        size: listView.visibleArea.heightRatio
        position: listView.visibleArea.yPosition
        active: listView.moving || listView.flicking
        orientation: Qt.Vertical
    }

    Connections {
       target: vBar
       function onPositionChanged() { 
           if (vBar.pressed) listView.contentY = vBar.position * listView.contentHeight 
       }
    }

    // --- Persistence Logic ---
    Timer {
        id: saveWidthsTimer
        interval: 1000
        repeat: false
        onTriggered: {
            var widths = {
                icon: colWidths.icon,
                title: colWidths.title,
                platform: colWidths.platform,
                region: colWidths.region,
                genre: colWidths.genre,
                developer: colWidths.developer,
                publisher: colWidths.publisher,
                year: colWidths.year,
                rating: colWidths.rating,
                tags: colWidths.tags
            };
            appSettings.columnWidths = JSON.stringify(widths);
            appSettings.save();

        }
    }

    function triggerSave() {
        saveWidthsTimer.restart();
    }

    function applySavedWidths() {
        if (appSettings.columnWidths && appSettings.columnWidths !== "") {
            try {
                var saved = JSON.parse(appSettings.columnWidths);
                if (saved.icon) colWidths.icon = saved.icon;
                if (saved.title) colWidths.title = saved.title;
                if (saved.platform) colWidths.platform = saved.platform;
                if (saved.region) colWidths.region = saved.region;
                if (saved.genre) colWidths.genre = saved.genre;
                if (saved.developer) colWidths.developer = saved.developer;
                if (saved.publisher) colWidths.publisher = saved.publisher;
                if (saved.year) colWidths.year = saved.year;
                if (saved.rating) colWidths.rating = saved.rating;
                if (saved.tags) colWidths.tags = saved.tags;

            } catch (e) {

            }
        }
    }

    Connections {
        target: appSettings
        function onSettingsChanged() {
            rootRoot.applySavedWidths();
        }
    }

    Component.onCompleted: {
        applySavedWidths();
    }

    Dialog {
        id: newPlaylistDialog
        title: "New Playlist"
        standardButtons: Dialog.Ok | Dialog.Cancel
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        property alias text: nameInput.text
        ColumnLayout {
            Label { text: "Playlist Name:" }
            TextField { id: nameInput; Layout.fillWidth: true }
        }
        onAccepted: {
            if (nameInput.text !== "") {
                playlistModel.createPlaylist(nameInput.text)
                nameInput.text = ""
                window.refreshPlaylists()
            }
        }
    }
}
