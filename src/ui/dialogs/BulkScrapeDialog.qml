import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../style"

import Qt5Compat.GraphicalEffects

Dialog {
    id: root
    
    // Responsive Sizing
    width: parent.width * 0.45
    height: Math.min(750, parent.height * 0.9)
    
    component StyledCheckBox : CheckBox {
        id: control
        palette.windowText: Theme.text
        font.pixelSize: 13
        indicator: Rectangle {
            implicitWidth: 18; implicitHeight: 18
            x: control.leftPadding
            y: parent.height / 2 - height / 2
            radius: 3
            border.color: control.checked ? Theme.accent : Theme.secondaryText
            color: "transparent"
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: Theme.accent
                visible: control.checked
                font.bold: true
                font.pixelSize: 14
            }
        }
        contentItem: Text {
            text: control.text
            font: control.font
            color: Theme.text
            verticalAlignment: Text.AlignVCenter
            leftPadding: control.indicator.width + 8
        }
    }
    
    anchors.centerIn: parent
    
    title: "Bulk Auto-Fetcher"
    header: null
    modal: false // Allow interaction with main window for background scraping
    standardButtons: Dialog.NoButton
    
    // Config Properties
    property alias scrapeMetadata: checkMetadata.checked
    property alias scrapeRetroAchievements: checkRa.checked
    property alias scrapeSteamAchievements: checkSteamAchievements.checked
    property alias minDelay: spinMinDelay.value
    property alias maxDelay: spinMaxDelay.value
    
    property var gameIds: [] // IDs to scrape
    property bool hasSteamGames: false
    property bool hasRaGames: false
    
    onGameIdsChanged: updatePlatformSupport()
    
    function updatePlatformSupport() {
        var steam = false
        var ra = false
        for (var i = 0; i < gameIds.length; i++) {
            var metaStr = gameModel.getGameMetadata(gameIds[i])
            if (metaStr) {
                try {
                    var meta = JSON.parse(metaStr)
                    var pId = meta.platform_id || ""
                    var pType = meta.platform_type || ""
                    var pName = meta.platform_name || ""
                    
                    if (pId === "steam" || pName === "Steam" || gameIds[i].startsWith("steam-")) {
                        steam = true
                    } else if (appSettings.isPlatformRaActive(pType) || appSettings.isPlatformRaActive(pName)) {
                        ra = true
                    }
                } catch(e) {}
            }
        }
        hasSteamGames = steam
        hasRaGames = ra
        
        // Auto-check defaults if credentials exist
        checkSteamAchievements.checked = steam && appSettings.steamId !== "" && appSettings.steamApiKey !== ""
        checkRa.checked = ra && appSettings.retroAchievementsUser !== "" && appSettings.retroAchievementsToken !== ""
    }
    
    // Close Policy: Don't allow closing if scraping is active (unless cancelled via button)
    // Close Policy: Allow closing (minimizing) even when scraping
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: {
        var defaultScraper = appSettings.activeMetadataScraper
        for (var i = 0; i < comboMetadataProvider.model.length; i++) {
            if (comboMetadataProvider.model[i] === defaultScraper) {
                comboMetadataProvider.currentIndex = i
                break
            }
        }
    }

    function showForGames(ids) {
        root.gameIds = ids
        root.open()
    }

    // Internal Confirmation Popup
    Dialog {
        id: confirmDialog
        title: "Scrape Finished"
        width: 300
        height: 150
        modal: true
        anchors.centerIn: parent
        
        background: Rectangle { // Consistent Theme
            color: Theme.background
            border.color: Theme.accent
            radius: 8
        }
        
        header: null
        standardButtons: Dialog.NoButton
        
        contentItem: ColumnLayout {
            spacing: 15
            Label {
                text: "Success"
                color: Theme.text
                font.bold: true
                font.pixelSize: 16
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: gameModel.bulkStatus
                color: Theme.secondaryText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            TheophanyButton {
                text: "OK"
                primary: true
                Layout.fillWidth: true
                onClicked: {
                    confirmDialog.close()
                    root.accept() // Close main dialog
                }
            }
        }
    }

    // Item-by-item Progress Model
    ListModel {
        id: bulkScrapeModel
    }

    function updateItemStatus(romId, status) {
        for (var i = 0; i < bulkScrapeModel.count; i++) {
            if (bulkScrapeModel.get(i).romId === romId) {
                bulkScrapeModel.setProperty(i, "status", status)
                break
            }
        }
    }

    Connections {
        target: gameModel
        function onBulkScrapingChanged() {
            if (!gameModel.bulkScraping) {
                 if (gameModel.bulkStatus.startsWith("Finished")) {
                     root.open() // Ensure main dialog is visible
                     confirmDialog.open()
                 }
            }
        }
        
        function onBulkProgressChanged() {
            var status = gameModel.bulkStatus
            // Extract title if possible
            var title = ""
            if (status.startsWith("Processing: ")) title = status.substring(12).trim()
            else if (status.startsWith("Fetching Metadata: ")) title = status.substring(19).trim()
            else if (status.startsWith("Checking Achievements: ")) title = status.substring(23).trim()
            
            if (title) {
                for (var i = 0; i < bulkScrapeModel.count; i++) {
                    var item = bulkScrapeModel.get(i)
                    if (item.title.trim() === title) {
                        if (item.status === "waiting") {
                            bulkScrapeModel.setProperty(i, "status", "processing")
                        }
                        break
                    }
                }
            }
        }

        function onBulkItemFinished(romId) {
            updateItemStatus(romId, "complete")
        }
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
        
        // Premium subtle glow
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }
    
    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 25
        spacing: 20
        
        // --- Header ---
        RowLayout {
            Layout.fillWidth: true
            
            Text {
                text: root.title
                color: Theme.text
                font.pixelSize: 22
                font.bold: true
                Layout.fillWidth: true
            }
            
            
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // --- Settings Section ---
        ColumnLayout {
            visible: !gameModel.bulkScraping
            spacing: 15
            Layout.fillWidth: true
            
            // Categories
            ColumnLayout {
                spacing: 8
                Label {
                    text: "Select Categories"
                    color: Theme.accent
                    font.bold: true
                    font.pixelSize: 12
                }
                
                StyledCheckBox {
                    id: checkMetadata
                    text: "Game Metadata"
                    checked: true
                }
                
                TheophanyComboBox {
                    id: comboMetadataProvider
                    visible: checkMetadata.checked
                    Layout.fillWidth: true
                    model: gameModel.getAvailableScrapers()
                }

                // Granular Fields
                GridLayout {
                    visible: checkMetadata.checked
                    columns: 2
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    columnSpacing: 10
                    rowSpacing: 0

                    property bool allChecked: true 

                    StyledCheckBox { id: checkTitle; text: "Title"; checked: true }
                    StyledCheckBox { id: checkDesc; text: "Description"; checked: true }
                    StyledCheckBox { id: checkDev; text: "Dev / Pub"; checked: true }
                    StyledCheckBox { id: checkGenre; text: "Genre / Tags"; checked: true }
                    StyledCheckBox { id: checkDate; text: "Release Date"; checked: true }
                    StyledCheckBox { id: checkRating; text: "Rating"; checked: true }
                    StyledCheckBox { id: checkRes; text: "Links (Resources)"; checked: true }
                }

                Label {
                    visible: checkMetadata.checked
                    text: "Select Images"
                    color: Theme.accent
                    font.bold: true
                    font.pixelSize: 12
                    Layout.topMargin: 5
                }

                GridLayout {
                    visible: checkMetadata.checked
                    columns: 2
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    columnSpacing: 10
                    rowSpacing: 0

                    StyledCheckBox { id: checkAssetBoxart; text: "Box Front"; checked: true }
                    StyledCheckBox { id: checkAssetIcon; text: "Game Icon"; checked: true }
                    StyledCheckBox { id: checkAssetLogo; text: "Clear Logo"; checked: true }
                    StyledCheckBox { id: checkAssetScreenshot; text: "Screenshots"; checked: true }
                    StyledCheckBox { id: checkAssetBackground; text: "Background"; checked: true }
                }

                StyledCheckBox {
                    id: checkRa
                    text: "RetroAchievements (Hash Check)"
                    checked: false
                    visible: hasRaGames && appSettings.retroAchievementsUser !== "" && appSettings.retroAchievementsToken !== ""
                }

                StyledCheckBox {
                    id: checkSteamAchievements
                    text: "Steam Achievements"
                    checked: false
                    visible: hasSteamGames && appSettings.steamId !== "" && appSettings.steamApiKey !== ""
                }
            }

            // Priority (Conditional)
            ColumnLayout {
                visible: (checkMetadata.checked && checkRa.checked && checkRa.visible) || (checkMetadata.checked && checkSteamAchievements.checked && checkSteamAchievements.visible)
                spacing: 8
                Layout.topMargin: 5
                
                Label {
                    text: "Processing Priority"
                    color: Theme.accent
                    font.bold: true
                    font.pixelSize: 12
                }
                
                TheophanyComboBox {
                    id: comboPreferred
                    Layout.fillWidth: true
                    model: [comboMetadataProvider.currentText, "RetroAchievements"]
                    currentIndex: 0
                }
            }
            
            // Pacing (Hidden, using defaults 2-5s)
            ColumnLayout {
                visible: false
                spacing: 8
                Layout.topMargin: 5
                
                Label {
                    text: "Pacing (Seconds)"
                    color: Theme.accent
                    font.bold: true
                    font.pixelSize: 12
                }
                
                RowLayout {
                    spacing: 15
                    Label { text: "Min Delay:"; color: Theme.secondaryText }
                    TheophanySpinBox {
                        id: spinMinDelay
                        from: 1
                        to: 60
                        value: 2
                    }
                    
                    Label { text: "Max Delay:"; color: Theme.secondaryText }
                    TheophanySpinBox {
                        id: spinMaxDelay
                        from: 1
                        to: 60
                        value: 5
                    }
                }
            }
            
            Label {
                text: "Processing " + root.gameIds.length + " items."
                color: Theme.secondaryText
                font.italic: true
                Layout.topMargin: 10
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }
        
        // --- Progress Section ---
        ColumnLayout {
            visible: gameModel.bulkScraping
            spacing: 15
            Layout.fillWidth: true
            
            Label {
                text: gameModel.bulkStatus
                color: Theme.text
                elide: Text.ElideRight
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
            }
            
            ProgressBar {
                Layout.fillWidth: true
                from: 0.0
                to: 1.0
                value: gameModel.bulkProgress
                
                background: Rectangle {
                    implicitWidth: 200
                    implicitHeight: 8
                    color: Theme.background
                    radius: 4
                }
                
                contentItem: Item {
                    implicitWidth: 200
                    implicitHeight: 8
                    Rectangle {
                        width: parent.width * (parent.value < 0 ? 0 : (parent.value > 1 ? 1 : parent.value))
                        height: parent.height
                        radius: 4
                        color: Theme.accent
                    }
                }
            }
            
            Label {
                text: Math.round(gameModel.bulkProgress * 100) + "%"
                color: Theme.secondaryText
                Layout.alignment: Qt.AlignRight
            }

            // --- Item List ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 250
                color: Theme.background
                radius: 8
                border.color: Theme.border
                clip: true

                ListView {
                    id: progressList
                    anchors.fill: parent
                    anchors.margins: 10
                    model: bulkScrapeModel
                    spacing: 8
                    
                    delegate: RowLayout {
                        width: progressList.width
                        spacing: 12
                        
                        // Status Icon
                        Rectangle {
                            width: 16; height: 16
                            radius: 8
                            color: "transparent"
                            
                            // Waiting
                            Rectangle {
                                anchors.centerIn: parent
                                width: 6; height: 6; radius: 3
                                color: Theme.secondaryText
                                visible: model.status === "waiting"
                            }
                            
                            // Processing (Spinner-ish)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14; height: 14; radius: 7
                                border.color: Theme.accent
                                border.width: 2
                                color: "transparent"
                                visible: model.status === "processing"
                                // Micro-animation would go here
                            }
                            
                            // Complete
                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: Theme.accent
                                font.bold: true
                                font.pixelSize: 14
                                visible: model.status === "complete"
                            }
                        }
                        
                        Label {
                            text: model.title
                            color: model.status === "complete" ? Theme.secondaryText : Theme.text
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        
                        Label {
                            text: model.status === "complete" ? "Done" : (model.status === "processing" ? "Processing..." : "")
                            color: model.status === "complete" ? Theme.accent : Theme.secondaryText
                            font.pixelSize: 11
                            font.italic: true
                        }
                    }
                    
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                    
                    // Auto-scroll to current item
                    onCountChanged: {
                        if (gameModel.bulkScraping) {
                            // Find first processing or waiting
                            for (var i = 0; i < count; i++) {
                                if (model.get(i).status === "processing") {
                                    positionViewAtIndex(i, ListView.Beginning)
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 15
            
            // Minimalist Controls
            TheophanyButton {
                text: "Minimize"
                onClicked: root.close()
            }

            Item { Layout.fillWidth: true } // Spacer to push action buttons right
            
            // Start Button
            TheophanyButton {
                text: "Start Scrape"
                visible: !gameModel.bulkScraping
                primary: true
                onClicked: {
                    var categories = []
                    if (checkMetadata.checked) categories.push("Metadata")
                    if (checkRa.checked) categories.push("RetroAchievements")
                    if (checkSteamAchievements.checked && checkSteamAchievements.visible) categories.push("SteamAchievements")
                    
                    if (categories.length === 0) return 
                    
                    // Validate Pacing
                    if (spinMinDelay.value > spinMaxDelay.value) {
                        spinMaxDelay.value = spinMinDelay.value
                    }
                    
                    // Construct Field Config
                    var fieldConfig = {
                        "title": checkTitle.checked,
                        "description": checkDesc.checked,
                        "dev_pub": checkDev.checked,
                        "genre_tags": checkGenre.checked,
                        "date": checkDate.checked,
                        "rating": checkRating.checked,
                        "resources": checkRes.checked,
                        "asset_boxart": checkAssetBoxart.checked,
                        "asset_icon": checkAssetIcon.checked,
                        "asset_logo": checkAssetLogo.checked,
                        "asset_screenshot": checkAssetScreenshot.checked,
                        "asset_background": checkAssetBackground.checked
                    }
                    
                    // Populate Progress Model
                    bulkScrapeModel.clear()
                    for (var i = 0; i < root.gameIds.length; i++) {
                        var gid = root.gameIds[i]
                        var gtitle = "Unknown Game"
                        // Find title from gameModel if possible
                        var row = gameModel.getRowById(gid)
                        if (row >= 0) {
                            gtitle = gameModel.getGameId(row) // Wait, getGameId returns ID. I need title.
                            // Actually search in gameModel's data is better in QML if we have a way.
                            // For now, let's just use the ID or placeholder, or I can fetch it.
                            // Better: gameModel has a lot of data. 
                        }
                        
                        bulkScrapeModel.append({
                            "romId": gid,
                            "title": gid, // Fallback
                            "status": "waiting"
                        })
                    }
                    // Refined title fetch:
                    for (var j = 0; j < bulkScrapeModel.count; j++) {
                        var metaStr = gameModel.getGameMetadata(bulkScrapeModel.get(j).romId)
                        if (metaStr) {
                            var meta = JSON.parse(metaStr)
                            bulkScrapeModel.setProperty(j, "title", meta.title || bulkScrapeModel.get(j).romId)
                        }
                    }
                    
                    gameModel.startBulkScrape(
                        JSON.stringify(root.gameIds),
                        JSON.stringify(categories),
                        JSON.stringify(fieldConfig),
                        spinMinDelay.value * 1000,
                        spinMaxDelay.value * 1000,
                        appSettings.retroAchievementsUser,
                        appSettings.retroAchievementsToken,
                        comboMetadataProvider.currentText,
                        comboPreferred.currentIndex === 1,
                        appSettings.ollamaUrl,
                        appSettings.ollamaModel,
                        appSettings.geminiApiKey,
                        appSettings.openaiApiKey,
                        appSettings.llmApiProvider
                    )
                }
            }
            
            // Running Controls
            RowLayout {
                visible: gameModel.bulkScraping
                spacing: 10
                
                TheophanyButton {
                    text: gameModel.bulkPaused ? "Resume" : "Pause"
                    onClicked: {
                        if (gameModel.bulkPaused) gameModel.resumeBulkScrape()
                        else gameModel.pauseBulkScrape()
                    }
                }
                
                TheophanyButton {
                    text: "Stop"
                    primary: true
                    onClicked: gameModel.stopBulkScrape()
                }
            }
        }
    }
}
