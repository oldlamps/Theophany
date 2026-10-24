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
            if (method === "TitleAZ" || method === "Title") {
                sortColumn = "Title"
                sortDescending = false
            } else if (method === "TitleZA" || method === "TitleDESC") {
                sortColumn = "Title"
                sortDescending = true
            } else if (method === "Recent" || method === "DateAddedDESC") {
                sortColumn = "DateAdded"
                sortDescending = true
            } else if (method === "DateAdded") {
                sortColumn = "DateAdded"
                sortDescending = false
            } else if (method === "LastPlayed") {
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
        if (typeof window !== "undefined" && window.setCollectionSort) {
            window.setCollectionSort(window.currentPlatformId, method)
        } else {
            gameModel.setSortMethod(method)
        }
        listView.forceActiveFocus()
    }

    property int iconWidth: 30
    property int titleWidth: 265
    property int platformWidth: 150
    property int regionWidth: 80
    property int genreWidth: 150
    property int developerWidth: 150
    property int publisherWidth: 150
    property int yearWidth: 60
    property int ratingWidth: 60
    property int tagsWidth: 200
    property int dateAddedWidth: 150
    property int pathWidth: 300
    property int columnGap: 10

    function setColumnWidth(name, val) {
        if (name === "icon") iconWidth = val
        else if (name === "title") titleWidth = val
        else if (name === "platform") platformWidth = val
        else if (name === "region") regionWidth = val
        else if (name === "genre") genreWidth = val
        else if (name === "developer") developerWidth = val
        else if (name === "publisher") publisherWidth = val
        else if (name === "year") yearWidth = val
        else if (name === "rating") ratingWidth = val
        else if (name === "tags") tagsWidth = val
        else if (name === "dateAdded") dateAddedWidth = val
        else if (name === "path") pathWidth = val
    }

    function getX(colName) {
        var x = 5; 
        var gap = rootRoot.columnGap;

        if (colName === "icon") return x;
        x += iconWidth + gap;

        if (colName === "title") return x;
        x += titleWidth + gap;

        if (colName === "platform") return x;
        x += platformWidth + gap;

        if (colName === "region") return x;
        x += regionWidth + gap;

        if (colName === "genre") return x;
        x += genreWidth + gap;

        if (colName === "developer") return x;
        x += developerWidth + gap;

        if (colName === "publisher") return x;
        x += publisherWidth + gap;

        if (colName === "year") return x;
        x += yearWidth + gap;

        if (colName === "rating") return x;
        x += ratingWidth + gap;

        if (colName === "tags") return x;
        x += tagsWidth + gap;

        if (colName === "dateAdded") return x;
        x += dateAddedWidth + gap;

        if (colName === "path") return x;
        
        return x;
    }

    Flickable {
        id: horizontalFlick
        anchors.fill: parent
        
        contentWidth: Math.max(parent.width, getX("path") + pathWidth + 100)
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

            Rectangle {
                width: parent.width
                height: 35
                color: Theme.secondaryBackground
                z: 2
                
                Row { // Using Row instead of RowLayout for absolute control with ResizeHandles
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    spacing: 10
                    
                    component HeaderButton: Item {
                        id: hbRoot
                        property string text
                        property string sortId
                        property string widthProp 
                        
                        width: {
                            if (widthProp === "icon") return rootRoot.iconWidth
                            if (widthProp === "title") return rootRoot.titleWidth
                            if (widthProp === "platform") return rootRoot.platformWidth
                            if (widthProp === "region") return rootRoot.regionWidth
                            if (widthProp === "genre") return rootRoot.genreWidth
                            if (widthProp === "developer") return rootRoot.developerWidth
                            if (widthProp === "publisher") return rootRoot.publisherWidth
                            if (widthProp === "year") return rootRoot.yearWidth
                            if (widthProp === "rating") return rootRoot.ratingWidth
                            if (widthProp === "tags") return rootRoot.tagsWidth
                            if (widthProp === "dateAdded") return rootRoot.dateAddedWidth
                            if (widthProp === "path") return rootRoot.pathWidth
                            return 100
                        }
                        height: parent.height

                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 5
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

                        MouseArea {
                            width: 10
                            height: parent.height
                            anchors.right: parent.right
                            anchors.rightMargin: -5 
                            cursorShape: Qt.SplitHCursor
                            preventStealing: true
                            z: 10
                            
                            property int startX: 0
                            property int startWidth: 0
                            
                            onPressed: (mouse) => {
                                var p = mapToItem(rootRoot, mouse.x, mouse.y)
                                startX = p.x
                                startWidth = hbRoot.width
                            }
                            
                            onPositionChanged: (mouse) => {
                                var p = mapToItem(rootRoot, mouse.x, mouse.y)
                                var delta = p.x - startX
                                var newWidth = Math.max(30, startWidth + delta)
                                rootRoot.setColumnWidth(widthProp, newWidth)
                                rootRoot.triggerSave()
                            }
                        }
                    }

                    Item { 
                        width: rootRoot.iconWidth
                        height: parent.height 
                    }

                    HeaderButton { text: "TITLE"; sortId: "Title"; widthProp: "title" }
                    
                    HeaderButton { text: "Platform"; sortId: "Platform"; widthProp: "platform" }
                    
                    HeaderButton { text: "Region"; sortId: "Region"; widthProp: "region" }
                    
                    HeaderButton { text: "Genre"; sortId: "Genre"; widthProp: "genre" }
                    
                    HeaderButton { text: "Developer"; sortId: "Developer"; widthProp: "developer" }
                    
                    HeaderButton { text: "Publisher"; sortId: "Publisher"; widthProp: "publisher" }
                    
                    HeaderButton { text: "Year"; sortId: "Year"; widthProp: "year" }
                    
                    HeaderButton { text: "Rating"; sortId: "Rating"; widthProp: "rating" }
                    
                    HeaderButton { text: "Tags"; sortId: "Tags"; widthProp: "tags" }
                    
                    HeaderButton { text: "Date Added"; sortId: "DateAdded"; widthProp: "dateAdded" }
                    
                    HeaderButton { text: "Path"; sortId: "Path"; widthProp: "path" }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
            }

            ListView {
                id: listView
                width: parent.width
                height: parent.height - 35
                clip: true
                focus: true
                highlightMoveDuration: 0
                flickableDirection: Flickable.VerticalFlick
                
                function formatDate(timestamp) {
                    if (!timestamp || timestamp <= 0) return ""
                    var d = new Date(timestamp * 1000)
                    return d.getFullYear() + "-" + 
                           String(d.getMonth() + 1).padStart(2, '0') + "-" + 
                           String(d.getDate()).padStart(2, '0')
                }
                
                cacheBuffer: 500
                reuseItems: true
                displayMarginBeginning: 100
                displayMarginEnd: 100
                
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
                    
                    Item {
                        x: rootRoot.getX("icon"); width: rootRoot.iconWidth; height: parent.height
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

                    Text { 
                        x: rootRoot.getX("title"); width: rootRoot.titleWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameTitle 
                        color: Theme.text 
                        elide: Text.ElideRight
                    }
                    
                    Item {
                        x: rootRoot.getX("platform"); width: rootRoot.platformWidth; height: parent.height
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
                    
                    Text { 
                        x: rootRoot.getX("region"); width: rootRoot.regionWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameRegion ? gameRegion : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("genre"); width: rootRoot.genreWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameGenre ? gameGenre : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("developer"); width: rootRoot.developerWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameDeveloper ? gameDeveloper : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("publisher"); width: rootRoot.publisherWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gamePublisher ? gamePublisher : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("year"); width: rootRoot.yearWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameReleaseYear && gameReleaseYear > 0 ? gameReleaseYear : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("rating"); width: rootRoot.ratingWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameRating && gameRating > 0 ? gameRating.toFixed(1) : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("tags"); width: rootRoot.tagsWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gameTags ? gameTags : ""
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text {
                        x: rootRoot.getX("dateAdded"); width: rootRoot.dateAddedWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: listView.formatDate(gameDateAdded)
                        color: Theme.secondaryText
                        elide: Text.ElideRight
                    }

                    Text { 
                        x: rootRoot.getX("path"); 
                        width: rootRoot.pathWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: gamePath
                        color: Theme.secondaryText
                        elide: Text.ElideLeft
                    }
                    
                    readonly property bool isSelected: rootRoot.selectedIndices.indexOf(index) !== -1 || (index === listView.currentIndex && listView.activeFocus)
                    color: isSelected ? Qt.alpha(Theme.accent, 0.4) : (ma.containsMouse ? Theme.hover : (index % 2 === 0 ? Qt.alpha(Theme.text, 0.05) : "transparent"))

                    MouseArea { 
                        id: ma; 
                        anchors.fill: parent; 
                        hoverEnabled: true; 
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        propagateComposedEvents: true 
                        onClicked: (mouse) => { 
                            listView.forceActiveFocus()
                            
                            if (mouse.button === Qt.LeftButton) {
                                if (mouse.modifiers & Qt.ControlModifier) {
                                    var current = rootRoot.selectedIndices.slice() 
                                    var idx = current.indexOf(index)
                                    rootRoot.ignoreNextReset = true
                                    if (idx !== -1) {
                                        current.splice(idx, 1)
                                        rootRoot.selectedIndices = current
                                    } else {
                                        current.push(index)
                                        rootRoot.selectedIndices = current
                                        listView.currentIndex = index 
                                        rootRoot.selectionAnchor = index
                                    }
                                } else if (mouse.modifiers & Qt.ShiftModifier) {
                                    rootRoot.updateRangeSelection(index)
                                } else {
                                    listView.currentIndex = index
                                    rootRoot.selectedIndices = [index]
                                    rootRoot.selectionAnchor = index
                                }
                            } else if (mouse.button === Qt.RightButton) {
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
                                        detailsPanel.gameId,
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
                                text: "Create Application Shortcut"
                                iconSource: "📌"
                                visible: rootRoot.selectedIndices.length === 1
                                onTriggered: {
                                    var res = gameModel.createApplicationShortcut(gameId)
                                    shortcutStatusDialog.text = res
                                    shortcutStatusDialog.open()
                                }
                            }
                            TheophanyMenuItem {
                                text: "Create Desktop Shortcut"
                                iconSource: "🖥️"
                                visible: rootRoot.selectedIndices.length === 1
                                onTriggered: {
                                    var res = gameModel.createDesktopShortcut(gameId)
                                    shortcutStatusDialog.text = res
                                    shortcutStatusDialog.open()
                                }
                            }
                            TheophanyMenuItem {
                                text: "Browse Local"
                                iconSource: "📂"
                                visible: rootRoot.selectedIndices.length === 1
                                onTriggered: window.browseGameLocation(gameId)
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
                icon: iconWidth,
                title: titleWidth,
                platform: platformWidth,
                region: regionWidth,
                genre: genreWidth,
                developer: developerWidth,
                publisher: publisherWidth,
                year: yearWidth,
                rating: ratingWidth,
                tags: tagsWidth,
                dateAdded: dateAddedWidth,
                path: pathWidth
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
                if (saved.icon) iconWidth = saved.icon;
                if (saved.title) titleWidth = saved.title;
                if (saved.platform) platformWidth = saved.platform;
                if (saved.region) regionWidth = saved.region;
                if (saved.genre) genreWidth = saved.genre;
                if (saved.developer) developerWidth = saved.developer;
                if (saved.publisher) publisherWidth = saved.publisher;
                if (saved.year) yearWidth = saved.year;
                if (saved.rating) ratingWidth = saved.rating;
                if (saved.tags) tagsWidth = saved.tags;
                if (saved.dateAdded) dateAddedWidth = saved.dateAdded;
                if (saved.path) pathWidth = saved.path;

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
