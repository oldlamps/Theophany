import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.platform 1.1 as Platform
import "../components"
import "../style"
import Theophany.Bridge 1.0

Dialog {
    id: root
    width: Math.max(700, window.width * 0.66)
    height: Math.max(500, window.height * 0.66)
    title: "Edit Game Details"
    modal: true
    
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
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

    property string gameId: ""
    property var currentData: ({})
    property int activeTab: 0
    
    // PC Config Properties
    property string platformType: ""
    property string platformName: ""
    property string platformId: ""
    property var currentConfig: ({})
    property var platformDefaults: ({})
    property bool eosOverlayEnabled: false
    property bool advancedCollapsed: true
    property bool isPc: platformType.includes("PC") || platformId === "epic" || gameId.includes("legendary-")
    property bool isWindows: platformType === "PC (Windows)" || platformId === "epic" || gameId.includes("legendary-")



    // AI Props
    property bool aiEnabled: false
    property string ollamaUrl: ""
    property string ollamaModel: ""
    property string aiDescriptionPrompt: ""
    property string geminiKey: ""
    property string openaiKey: ""
    property string llmProvider: ""

    Connections {
        target: gameModel
        function onEosOverlayEnabledResult(rId, enabled) {
            if (rId === root.gameId) {
                root.eosOverlayEnabled = enabled
            }
        }
    }
    property var platformModel: null

    property var allGenres: []
    property var allTags: []
    property var allDevelopers: []
    property var allPublishers: []
    property var allRegions: []
    property var allYears: []



    function load(id, targetTab) {
        gameId = id
        activeTab = targetTab || 0
        root.eosOverlayEnabled = false // Reset state to prevent sticking from previous games
        var json = gameModel.getGameMetadata(id)

        try {
            currentData = JSON.parse(json)
            platformType = currentData.platform_type || ""
            platformName = currentData.platform_name || ""
            platformId = currentData.platform_id || ""
            
            // Populate Fields
            titleField.text = currentData.title || ""
            descField.text = currentData.description || ""
            devField.text = currentData.developer || ""
            pubField.text = currentData.publisher || ""
            genreField.text = currentData.genre || ""
            tagsField.text = currentData.tags || ""
            regionField.text = currentData.region || ""
            ratingField.value = Math.round((currentData.rating || 0) * 10) // Internal SpinBox is 0-100, DB is 0-10
            releaseField.text = currentData.release_date || ""
            
            // Load available metadata for suggestions
            allGenres = gameModel.getAllGenres()
            allTags = gameModel.getAllTags()
            allDevelopers = gameModel.getAllDevelopers()
            allPublishers = gameModel.getAllPublishers()
            allRegions = gameModel.getAllRegions()
            allYears = gameModel.getAllYears()
            


            // Load PC Config if applicable
            if (isPc) {
                if (isWindows) refreshProtonVersions()
                loadPcConfig()
                
                // Load EOS Overlay status
                if (gameId.indexOf("legendary-") === 0 || platformId === "epic") {
                    gameModel.checkEosOverlayEnabled(gameId)
                }
            }
             
        } catch (e) {

        }
    }

    function loadPcConfig() {
        // Fetch platform defaults
        var defaultsStr = gameModel.getPlatformPcDefaults(gameId)
        try { platformDefaults = JSON.parse(defaultsStr) } catch(e) { platformDefaults = {} }

        // Load primary executable path
        var currentExe = gameModel.getRomPath(gameId).toString()
        exePathField.text = currentExe
        
        // Initial folders for dialogs
        if (currentExe && currentExe !== "") {
            var lastSlash = currentExe.lastIndexOf('/')
            if (lastSlash === -1) lastSlash = currentExe.lastIndexOf('\\')
            if (lastSlash !== -1) {
                var dir = currentExe.substring(0, lastSlash)
                var folderUrl = "file://" + dir
                exePathFileDialog.folder = folderUrl
                workingFolderDialog.folder = folderUrl
                protonFolderDialog.folder = folderUrl
                prefixFolderDialog.folder = folderUrl
            }
        }

        var jsonStr = gameModel.getPcConfig(gameId)
        try {
            currentConfig = JSON.parse(jsonStr)
            
            // Universal Settings
            wrapperField.text = (currentConfig.wrapper !== undefined) ? (currentConfig.wrapper || "") : (platformDefaults.wrapper || "")
            wrapperField.placeholderText = platformDefaults.wrapper || "e.g. firejail --net=none"
            extraArgsField.text = (currentConfig.extra_args !== undefined) ? (currentConfig.extra_args || "") : (platformDefaults.extra_args || "")
            extraArgsField.placeholderText = platformDefaults.extra_args || "e.g. -novid"
            workingDirField.text = (currentConfig.working_dir !== undefined) ? (currentConfig.working_dir || "") : (platformDefaults.working_dir || "")
            workingDirField.placeholderText = platformDefaults.working_dir || "EXE directory"

            mangohudCheck.checked = (currentConfig.use_mangohud !== undefined) ? !!currentConfig.use_mangohud : !!platformDefaults.use_mangohud
            preLaunchField.text = (currentConfig.pre_launch_script !== undefined) ? (currentConfig.pre_launch_script || "") : ""
            postLaunchField.text = (currentConfig.post_launch_script !== undefined) ? (currentConfig.post_launch_script || "") : ""

            // Cloud Saves
            cloudSavesCheck.checked = !!currentConfig.cloud_saves_enabled
            cloudSavePathField.text = currentConfig.cloud_save_path || ""
            cloudSaveAutoSyncCheck.checked = !!currentConfig.cloud_save_auto_sync

            // Gamescope
            gamescopeCheck.checked = (currentConfig.use_gamescope !== undefined) ? !!currentConfig.use_gamescope : !!platformDefaults.use_gamescope
            if (currentConfig.gs_state || platformDefaults.gs_state) {
                var gs = currentConfig.gs_state || {}
                var defGs = platformDefaults.gs_state || {}
                
                // If local config exists for Gamescope, we use its state exclusively if defined
                var hasLocalGs = currentConfig.use_gamescope !== undefined
                
                gsWidthField.text = (hasLocalGs && gs.w !== undefined) ? (gs.w || "") : (defGs.w || "")
                gsWidthField.placeholderText = defGs.w || "1920"
                gsHeightField.text = (hasLocalGs && gs.h !== undefined) ? (gs.h || "") : (defGs.h || "")
                gsHeightField.placeholderText = defGs.h || "1080"
                gsOutWidthField.text = (hasLocalGs && gs.W !== undefined) ? (gs.W || "") : (defGs.W || "")
                gsOutWidthField.placeholderText = defGs.W || "3840"
                gsOutHeightField.text = (hasLocalGs && gs.H !== undefined) ? (gs.H || "") : (defGs.H || "")
                gsOutHeightField.placeholderText = defGs.H || "2160"
                gsRefreshField.text = (hasLocalGs && gs.r !== undefined) ? (gs.r || "") : (defGs.r || "")
                gsRefreshField.placeholderText = defGs.r || "60"
                
                gsScalingCombo.currentIndex = (hasLocalGs && gs.S !== undefined) ? gs.S : (defGs.S !== undefined ? defGs.S : 0)
                gsUpscalerCombo.currentIndex = (hasLocalGs && gs.U !== undefined) ? gs.U : (defGs.U !== undefined ? defGs.U : 0)
                gsFullscreenCheck.checked = (hasLocalGs && gs.f !== undefined) ? !!gs.f : !!defGs.f
            }

            // Windows/Proton specific
            if (isWindows) {
                // Match Proton version by name or path
                var pVal = (currentConfig.umu_proton_version !== undefined) ? (currentConfig.umu_proton_version || "") : (platformDefaults.umu_proton_version || "")
                var pIndex = -1
                for (var j = 0; j < protonVersionsModel.count; j++) {
                    if (protonVersionsModel.get(j).name === pVal || protonVersionsModel.get(j).path === pVal) {
                        pIndex = j
                        break
                    }
                }
                
                if (pIndex !== -1) {
                    protonCombo.currentIndex = pIndex
                    protonField.text = ""
                } else {
                    protonCombo.currentIndex = 0
                    protonField.text = pVal
                }

                prefixField.text = (currentConfig.wine_prefix !== undefined) ? (currentConfig.wine_prefix || "") : (platformDefaults.wine_prefix || "")
                prefixField.placeholderText = platformDefaults.wine_prefix || "Default prefix"
                storeField.text = (currentConfig.umu_store !== undefined) ? (currentConfig.umu_store || "") : (platformDefaults.umu_store || "")
                storeField.placeholderText = platformDefaults.umu_store || "e.g. steam, gog"
                umuIdField.text = (currentConfig.umu_id !== undefined) ? (currentConfig.umu_id || "") : (platformDefaults.umu_id || "")
                umuIdField.placeholderText = platformDefaults.umu_id || "umu-database ID"
                protonVerbField.text = (currentConfig.proton_verb !== undefined) ? (currentConfig.proton_verb || "") : (platformDefaults.proton_verb || "")
                protonVerbField.placeholderText = platformDefaults.proton_verb || "waitforexitandrun"
                disableFixesCheck.checked = currentConfig.disable_fixes !== undefined ? !!currentConfig.disable_fixes : !!platformDefaults.disable_fixes
                noRuntimeCheck.checked = currentConfig.no_runtime !== undefined ? !!currentConfig.no_runtime : !!platformDefaults.no_runtime
                var logLevel = (currentConfig.log_level !== undefined) ? (currentConfig.log_level || "Default (1)") : (platformDefaults.log_level || "Default (1)")
                var logIdx = ["None", "Default (1)", "Debug"].indexOf(logLevel)
                logLevelCombo.currentIndex = logIdx !== -1 ? logIdx : 1
            }

            // Env vars
            envModel.clear()
            if (currentConfig.env_vars) {
                try {
                    var envs = JSON.parse(currentConfig.env_vars)
                    for (var k in envs) {
                        envModel.append({ "key": k, "value": envs[k] })
                    }
                } catch(e) {}
            }
        } catch (e) {

        }
    }

    function getGamescopeArgs() {
        if (!gamescopeCheck.checked) return ""
        var args = []
        if (gsWidthField.text) args.push("-w", gsWidthField.text)
        if (gsHeightField.text) args.push("-h", gsHeightField.text)
        if (gsOutWidthField.text) args.push("-W", gsOutWidthField.text)
        if (gsOutHeightField.text) args.push("-H", gsOutHeightField.text)
        if (gsRefreshField.text) args.push("-r", gsRefreshField.text)
        if (gsScalingCombo.currentText !== "Auto") args.push("-S", gsScalingCombo.currentText.toLowerCase())
        if (gsUpscalerCombo.currentText !== "None") args.push("-U", gsUpscalerCombo.currentText.toLowerCase())
        if (gsFullscreenCheck.checked) args.push("-f")
        return args.join(" ")
    }

    function getAssetPath(key) {
        if (currentData.assets && currentData.assets[key]) {
            var assets = currentData.assets[key]
            if (assets.length > 0) {
                return "file://" + assets[0]
            }
        }
        return ""
    }

    function getAssetCount(key) {
        if (currentData.assets && currentData.assets[key]) {
            return currentData.assets[key].length
        }
        return 0
    }

    function formatBytes(bytes) {
        if (bytes === 0) return "0 Bytes"
        const k = 1024
        const sizes = ["Bytes", "KB", "MB", "GB", "TB"]
        const i = Math.floor(Math.log(bytes) / Math.log(k))
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i]
    }

    function formatPlaytime(seconds) {
        if (!seconds || seconds === 0) return "Never Played"
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m"
    }

    function formatDate(timestamp) {
        if (!timestamp || timestamp === 0) return "Never"
        var d = new Date(timestamp * 1000)
        return d.toLocaleDateString()
    }

    // Modal is headerless essentially, we'll draw our own
    header: Item { height: 0 }
    
    contentItem: Item {
        id: editContainer
        clip: true

        // Global mouse trap to prevent events leaking to background grids/lists
        MouseArea {
            anchors.fill: parent
            z: -1 // Behind all actual dialog content but in front of everything else
            onClicked: (mouse) => { mouse.accepted = true; }
            onDoubleClicked: (mouse) => { mouse.accepted = true; }
            onWheel: (wheel) => { wheel.accepted = true; }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Sidebar
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 200
                color: Theme.background
                
                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Theme.border
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 0
                    spacing: 0

                    // Sidebar Header
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        Label {
                            anchors.centerIn: parent
                            text: "EDIT GAME"
                            font.bold: true
                            font.pixelSize: 18
                            font.letterSpacing: 2
                            color: Theme.accent
                        }
                    }

                    // Navigation Items
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 4
                        
                        Repeater {
                            model: {
                                var m = ["General", "Metadata", "Assets"]
                                if (root.isPc) m.push("Configuration")
                                return m
                            }
                            delegate: Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    radius: 6
                                    color: root.activeTab === index ? Theme.secondaryBackground : "transparent"
                                    
                                    Rectangle {
                                        visible: root.activeTab === index
                                        anchors.left: parent.left
                                        width: 4
                                        height: parent.height * 0.6
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: 2
                                        color: Theme.accent
                                    }

                                    Label {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        font.pixelSize: 14
                                        font.bold: root.activeTab === index
                                        color: root.activeTab === index ? Theme.text : Theme.secondaryText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.activeTab = index
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Main Content Area
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Content Header
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    color: "transparent"
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        spacing: 20

                        Label {
                            text: {
                                if (root.activeTab === 0) return "General Overview"
                                if (root.activeTab === 1) return "Edit Metadata"
                                if (root.activeTab === 2) return "Manage Assets"
                                return "Game Configuration"
                            }
                            font.pixelSize: 22
                            font.bold: true
                            color: Theme.text
                            Layout.fillWidth: true
                        }

                        TheophanyButton {
                            visible: root.activeTab === 1
                            text: "Scrape Online..."
                            onClicked: scrapeDialog.open()
                        }
                    }
                }

                // Scrollable Content
                ScrollView {
                    id: contentScrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: -1
                    contentHeight: contentStack.children[contentStack.currentIndex] ? contentStack.children[contentStack.currentIndex].implicitHeight : 0
                    clip: true
                    
                    // Reset scroll position when tab changes
                    Connections {
                        target: root
                        function onActiveTabChanged() {
                            contentScrollView.ScrollBar.vertical.position = 0
                        }
                    }
                    
                    StackLayout {
                        id: contentStack
                        width: parent.width
                        currentIndex: root.activeTab
                        
                        // GENERAL OVERVIEW TAB
                        Item {
                            implicitHeight: generalGrid.height + 100
                            ColumnLayout {
                                id: generalGrid
                                anchors.top: parent.top
                                anchors.topMargin: 20
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.9
                                spacing: 25

                                // File Details Section
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 15
                                    Text { text: "FILE INFORMATION"; color: Theme.accent; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.5 }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: fileInfoGrid.implicitHeight + 40
                                        color: Theme.secondaryBackground
                                        radius: 10
                                        border.color: Theme.border

                                        GridLayout {
                                            id: fileInfoGrid
                                            anchors.fill: parent
                                            anchors.margins: 20
                                            columns: 2
                                            rowSpacing: 15
                                            columnSpacing: 25

                                            Label { text: "Filename"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 120 }
                                            Label { text: root.currentData.rom_filename || "Unknown"; color: Theme.text; elide: Text.ElideMiddle; Layout.fillWidth: true }

                                            Label { text: "Location"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 12 }
                                            Label { 
                                                text: root.currentData.rom_path || "Unknown"
                                                color: Theme.text
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    TheophanyTooltip {
                                                        visible: parent.containsMouse
                                                        text: parent.parent.text
                                                    }
                                                }
                                            }

                                            Label { text: "File Size"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 12 }
                                            Label { text: root.formatBytes(root.currentData.rom_file_size || 0); color: Theme.text }
                                            
                                            Label { text: "Platform"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 12 }
                                            Label { text: root.platformName + " (" + root.platformType + ")"; color: Theme.text }
                                        }
                                    }
                                }

                                // Statistics Section
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 15
                                    Text { text: "PLAYER STATISTICS"; color: Theme.accent; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.5 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 20

                                        // Playtime Card
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 100
                                            color: Theme.secondaryBackground
                                            radius: 10
                                            border.color: Theme.border

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Label { text: "Total Playtime"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                                Label { text: root.formatPlaytime(root.currentData.total_play_time || 0); color: Theme.text; font.pixelSize: 20; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                            }
                                        }

                                        // Play Count Card
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 100
                                            color: Theme.secondaryBackground
                                            radius: 10
                                            border.color: Theme.border

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Label { text: "Play Count"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                                Label { text: (root.currentData.play_count || 0).toString(); color: Theme.text; font.pixelSize: 20; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 60
                                        color: Theme.secondaryBackground
                                        radius: 10
                                        border.color: Theme.border

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 20
                                            anchors.rightMargin: 20
                                            
                                            Label { text: "Last Played"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 12; Layout.fillWidth: true }
                                            Label { text: root.formatDate(root.currentData.last_played || 0); color: Theme.text; font.bold: true }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // METADATA TAB
                        Item {
                            implicitHeight: metadataGrid.height + 100
                            ColumnLayout {
                                id: metadataGrid
                                anchors.top: parent.top
                                anchors.topMargin: 20
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.9
                                spacing: 20

                                TheophanyTextField { 
                                    Layout.fillWidth: true
                                    id: titleField
                                    placeholderText: "Game Title"
                                    selectByMouse: true
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                                
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        
                                        Label { text: "Developer"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                        TheophanySuggestField { id: devField; Layout.fillWidth: true; fullModel: root.allDevelopers }
                                        
                                        Label { text: "Genre"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                        TheophanySuggestField { id: genreField; Layout.fillWidth: true; fullModel: root.allGenres; isCommaSeparated: true }
                                        
                                        Label { text: "Region"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                        TheophanySuggestField { id: regionField; Layout.fillWidth: true; fullModel: root.allRegions }
                                    }
                                    
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        
                                        Label { text: "Publisher"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                        TheophanySuggestField { id: pubField; Layout.fillWidth: true; fullModel: root.allPublishers }
                                        
                                        Label { text: "Release Year"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                        TheophanySuggestField { id: releaseField; Layout.fillWidth: true; fullModel: root.allYears }
                                        
                                        Label { text: "Community Rating (0-10)"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                        TheophanySpinBox { 
                                            id: ratingField 
                                            Layout.fillWidth: true
                                            from: 0; to: 100; stepSize: 1
                                            property real realValue: value / 10.0
                                            validator: DoubleValidator { bottom: 0; top: 10; decimals: 1 }
                                            textFromValue: function(value, locale) { return Number(value / 10.0).toLocaleString(locale, 'f', 1) }
                                            valueFromText: function(text, locale) { return Number.fromLocaleString(locale, text) * 10 }
                                        }
                                    }
                                }

                                Label { text: "Tags (comma separated)"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                TheophanySuggestField { id: tagsField; Layout.fillWidth: true; placeholderText: "Action, RPG, Classic..."; fullModel: root.allTags; isCommaSeparated: true }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Label { text: "Description"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    TheophanyButton {
                                        visible: root.aiEnabled && ((root.ollamaUrl !== "" && root.ollamaModel !== "") || root.geminiKey !== "" || root.openaiKey !== "")
                                        text: aiDescGen.isGenerating ? "Stop Generation" : "✨ AI Write/Rewrite"
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: 140
                                        font.pixelSize: 11
                                        onClicked: {
                                            if (aiDescGen.isGenerating) {
                                                aiDescGen.stopGeneration()
                                            } else {
                                                aiDescGen.generateDescription(
                                                    titleField.text, 
                                                    descField.text, 
                                                    root.ollamaUrl, 
                                                    root.ollamaModel, 
                                                    root.aiDescriptionPrompt,
                                                    root.geminiKey,
                                                    root.openaiKey,
                                                    root.llmProvider
                                                )
                                                aiDescPollTimer.start()
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 150
                                    color: "transparent" // Let component handle background, or use Theme.secondaryBackground
                                    
                                    ScrollView {
                                        anchors.fill: parent
                                        
                                        TheophanyTextArea { 
                                            id: descField 
                                            // The ScrollView manages the viewport
                                            // We remove anchors.fill: parent here because ScrollView content should size itself or fill width
                                            width: parent.width
                                            selectByMouse: true 
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }

                        // ASSETS TAB
                        Item {
                            implicitHeight: assetLayout.height + 100
                            ColumnLayout {
                                id: assetLayout
                                anchors.top: parent.top
                                anchors.topMargin: 20
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.9
                                spacing: 25

                                Repeater {
                                    model: [
                                        "Grid",
                                        "Box - Front",
                                        "Hero",
                                        "Logo",
                                        "Clear Logo",
                                        "Icon",
                                        "Background",
                                        "Banner",
                                        "Box - Back",
                                        "Box - 3D",
                                        "Box - Spine",
                                        "Disc",
                                        "Cartridge",
                                        "Title Screen",
                                        "Marquee",
                                        "Screenshot"
                                    ]
                                    
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 180
                                        color: Theme.secondaryBackground
                                        radius: 10
                                        border.color: Theme.border
                                        
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 15
                                            spacing: 20
                                            
                                            // Thumbnail List for this category
                                            Rectangle {
                                                id: categoryContainer
                                                property string category: modelData
                                                Layout.preferredWidth: 260
                                                Layout.fillHeight: true
                                                color: "#111"
                                                radius: 6
                                                clip: true
                                                
                                                ListView {
                                                    id: thumbList
                                                    anchors.fill: parent
                                                    anchors.margins: 5
                                                    orientation: ListView.Horizontal
                                                    spacing: 8
                                                    model: {
                                                        var list = []
                                                        if (currentData.assets && currentData.assets[modelData]) {
                                                            var assets = currentData.assets[modelData]
                                                            for (var i = 0; i < assets.length; i++) {
                                                                list.push({ "url": "file://" + assets[i], "path": assets[i] })
                                                            }
                                                        }
                                                        return list
                                                    }
                                                    
                                                    delegate: Item {
                                                        width: 120
                                                        height: thumbList.height - 10
                                                        
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            color: "#111"
                                                            border.color: "#222"
                                                            radius: 4
                                                            clip: true

                                                            Image {
                                                                anchors.fill: parent
                                                                source: modelData.url
                                                                fillMode: Image.PreserveAspectFit
                                                                asynchronous: true
                                                                cache: false
                                                                onStatusChanged: {
                                                                    if (status === Image.Error) {

                                                                    } else if (status === Image.Ready) {

                                                                    }
                                                                }
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                onClicked: (mouse) => { mouse.accepted = true; }
                                                                onDoubleClicked: (mouse) => { mouse.accepted = true; }
                                                            }
                                                        }
                                                        
                                                        Rectangle {
                                                            anchors.bottom: parent.bottom
                                                            anchors.right: parent.right
                                                            width: 20; height: 20; radius: 10
                                                            color: Theme.accent
                                                            visible: true
                                                            Text { anchors.centerIn: parent; text: "×"; color: "white"; font.bold: true; anchors.verticalCenterOffset: -1 }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    gameModel.deleteGameAsset(root.gameId, categoryContainer.category, modelData.path)
                                                                    root.load(root.gameId, root.activeTab)
                                                                }
                                                            }
                                                        }


                                                    }
                                                    
                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: "No Assets"
                                                        color: Theme.secondaryText
                                                        font.pixelSize: 12
                                                        visible: thumbList.count === 0
                                                    }

                                                    ScrollBar.horizontal: ScrollBar {
                                                        id: hbar
                                                        active: thumbList.moving || hbar.activeFocus || hbar.hovered || hbar.pressed
                                                        policy: ScrollBar.AsNeeded
                                                        z: 10
                                                    }

                                                    // onWheel/onClicked overlay removed to avoid blocking delete buttons. 
                                                    // Global trap at root handles background leakage.
                                                }
                                            }
                                            
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                
                                                Label { text: modelData; font.bold: true; font.pixelSize: 16; color: Theme.text }
                                                Label { 
                                                    text: "Recommended for high-quality library viewing."; 
                                                    color: Theme.secondaryText; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true 
                                                }
                                                
                                                Item { Layout.fillHeight: true }
                                                
                                                RowLayout {
                                                    spacing: 12
                                                    TheophanyButton {
                                                        text: "Choose File..."
                                                        Layout.fillWidth: true
                                                        onClicked: fileDialog.openFor(modelData)
                                                    }
                                                    TheophanyButton {
                                                        text: "Search Online..."
                                                        Layout.fillWidth: true
                                                        onClicked: {
                                                            imageSearchDialog.assetType = modelData
                                                            imageSearchDialog.initialQuery = titleField.text + " " + (modelData === "Box - Front" ? "boxart" : modelData)
                                                            imageSearchDialog.open()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // CONFIGURATION TAB
                        Item {
                            id: configTab
                            implicitHeight: configLayout.height + 100
                            
                            ColumnLayout {
                                id: configLayout
                                width: parent.width * 0.9
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 20
                                spacing: 30

                                // SECTION: EXECUTABLE & CORE
                                ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        Text { text: "CORE SETTINGS"; color: Theme.accent; font.pixelSize: 11; font.bold: true }

                                        GridLayout {
                                            columns: 2
                                            rowSpacing: 15
                                            columnSpacing: 20
                                            Layout.fillWidth: true

                                            Label { text: "Executable Path"; color: Theme.text; Layout.preferredWidth: 140 }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField { id: exePathField; Layout.fillWidth: true; placeholderText: "Path to game executable..." }
                                                TheophanyButton { 
                                                    text: "📁"
                                                    tooltipText: "Select Executable File"
                                                    Layout.preferredWidth: 42
                                                    onClicked: exePathFileDialog.open()
                                                }
                                            }

                                            Label { text: "Working Dir"; color: Theme.text; Layout.preferredWidth: 140 }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField { id: workingDirField; Layout.fillWidth: true; placeholderText: "EXE directory" }
                                                TheophanyButton {
                                                    text: "📁"
                                                    tooltipText: "Select Working Folder"
                                                    Layout.preferredWidth: 42
                                                    onClicked: workingFolderDialog.open()
                                                }
                                            }
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                                    // SECTION: PROTON / UMU (Windows Only)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        visible: root.isWindows

                                        Text { text: "PROTON / UMU SETTINGS (WINDOWS ONLY)"; color: Theme.accent; font.pixelSize: 11; font.bold: true }

                                        GridLayout {
                                            columns: 2
                                            rowSpacing: 15
                                            columnSpacing: 20
                                            Layout.fillWidth: true

                                            Label { text: "Proton Version"; color: Theme.text; Layout.preferredWidth: 140 }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyComboBox { 
                                                    id: protonCombo
                                                    Layout.fillWidth: true
                                                    model: protonVersionsModel
                                                    textRole: "name"
                                                    valueRole: "path"
                                                }
                                                TheophanyTextField { 
                                                    id: protonField
                                                    Layout.fillWidth: true
                                                    placeholderText: "Or enter manual path..."
                                                    visible: protonCombo.currentIndex === 0 && text !== ""
                                                }
                                                TheophanyButton {
                                                    text: "📁"
                                                    tooltipText: "Select Proton Folder"
                                                    Layout.preferredWidth: 42
                                                    onClicked: protonFolderDialog.open()
                                                }
                                            }

                                            Label { text: "Wine Prefix"; color: Theme.text; Layout.preferredWidth: 140 }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField { id: prefixField; Layout.fillWidth: true; placeholderText: "Default prefix" }
                                                TheophanyButton { 
                                                    text: "📁"
                                                    tooltipText: "Select Wine Prefix"
                                                    Layout.preferredWidth: 42
                                                    onClicked: prefixFolderDialog.open()
                                                }
                                            }
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; visible: root.isWindows }

                                    // SECTION: CLOUD SAVES (Epic/Legendary only)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        visible: root.gameId.toString().indexOf("legendary-") === 0 || root.platformId === "epic"

                                        Text { text: "CLOUD SAVES"; color: Theme.accent; font.pixelSize: 11; font.bold: true }

                                        TheophanyCheckBox {
                                            id: cloudSavesCheck
                                            text: "Enable Cloud Saves (via legendary)"
                                        }

                                        TheophanyCheckBox {
                                            id: cloudSaveAutoSyncCheck
                                            text: "Auto Sync on Launch / Close  (pull before launch, push on exit)"
                                            enabled: cloudSavesCheck.checked
                                            opacity: enabled ? 1.0 : 0.4
                                        }

                                        GridLayout {
                                            columns: 2
                                            rowSpacing: 12
                                            columnSpacing: 20
                                            Layout.fillWidth: true
                                            opacity: cloudSavesCheck.checked ? 1.0 : 0.4

                                            Label { text: "Save Path"; color: Theme.text; Layout.preferredWidth: 140 }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField {
                                                    id: cloudSavePathField
                                                    Layout.fillWidth: true
                                                    placeholderText: "Auto-resolved from legendary info  (or set override)"
                                                    enabled: cloudSavesCheck.checked
                                                }
                                                TheophanyButton {
                                                    text: "Auto Resolve"
                                                    tooltipText: "Query legendary info to resolve the save path template"
                                                    enabled: cloudSavesCheck.checked && prefixField.text !== ""
                                                    onClicked: {
                                                        var result = gameModel.resolveCloudSavePath(root.gameId, prefixField.text)
                                                        if (result.indexOf("error:") === 0) {
                                                            cloudSaveStatusLabel.text = "⚠️ " + result.substring(6)
                                                            cloudSaveStatusLabel.color = Theme.danger || "#ff4444"
                                                        } else {
                                                            cloudSavePathField.text = result
                                                            cloudSaveStatusLabel.text = "✅ Path resolved"
                                                            cloudSaveStatusLabel.color = Theme.accent
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Label {
                                            id: cloudSaveStatusLabel
                                            text: ""
                                            color: Theme.secondaryText
                                            font.pixelSize: 12
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                        }

                                        RowLayout {
                                            Layout.topMargin: 5
                                            spacing: 10
                                            enabled: cloudSavesCheck.checked
                                            opacity: enabled ? 1.0 : 0.4

                                            Label { text: "Manual Sync:"; color: Theme.secondaryText; font.pixelSize: 13 }

                                            TheophanyCheckBox {
                                                id: forceSyncCheck
                                                text: "Force"
                                                font.pixelSize: 12
                                            }

                                            TheophanyButton {
                                                text: "⬇ Pull from Cloud"
                                                enabled: cloudSavesCheck.checked
                                                tooltipText: "Download saves from Epic cloud"
                                                onClicked: {
                                                    cloudSaveStatusLabel.text = "⏳ Pulling from cloud…"
                                                    cloudSaveStatusLabel.color = Theme.secondaryText
                                                    // Save current path first so backend can find it
                                                    savePcConfig()
                                                    gameModel.syncCloudSaves(root.gameId, "pull", forceSyncCheck.checked)
                                                }
                                            }
                                            TheophanyButton {
                                                text: "⬆ Push to Cloud"
                                                enabled: cloudSavesCheck.checked
                                                tooltipText: "Upload saves to Epic cloud"
                                                onClicked: {
                                                    cloudSaveStatusLabel.text = "⏳ Pushing to cloud…"
                                                    cloudSaveStatusLabel.color = Theme.secondaryText
                                                    savePcConfig()
                                                    gameModel.syncCloudSaves(root.gameId, "push", forceSyncCheck.checked)
                                                }
                                            }
                                            TheophanyButton {
                                                text: "↕ Sync Both"
                                                enabled: cloudSavesCheck.checked
                                                tooltipText: "Bidirectional sync (pull + push)"
                                                onClicked: {
                                                    cloudSaveStatusLabel.text = "⏳ Syncing…"
                                                    cloudSaveStatusLabel.color = Theme.secondaryText
                                                    savePcConfig()
                                                    gameModel.syncCloudSaves(root.gameId, "both", forceSyncCheck.checked)
                                                }
                                            }
                                        }

                                        // Wire up the async signal for sync results
                                        Connections {
                                            target: gameModel
                                            function onCloudSaveSyncFinished(rom_id, success, message) {
                                                if (rom_id !== root.gameId) return
                                                if (success) {
                                                    cloudSaveStatusLabel.text = "✅ " + message
                                                    cloudSaveStatusLabel.color = Theme.accent
                                                } else {
                                                    cloudSaveStatusLabel.text = "❌ " + message
                                                    cloudSaveStatusLabel.color = Theme.danger || "#ff4444"
                                                }
                                            }
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; visible: root.gameId.toString().indexOf("legendary-") === 0 || root.platformId === "epic" }

                                    // SECTION: EOS OVERLAY (Epic/Legendary only)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        visible: root.gameId.toString().indexOf("legendary-") === 0 || root.platformId === "epic"

                                        Text { text: "EOS OVERLAY (EXPERIMENTAL)"; color: Theme.accent; font.pixelSize: 11; font.bold: true }

                                        TheophanyCheckBox {
                                            id: eosOverlayCheck
                                            text: "Enable EOS Overlay for this game"
                                            checked: root.eosOverlayEnabled
                                            onToggled: {
                                                if (checked) {
                                                    gameModel.enableEosOverlay(root.gameId)
                                                } else {
                                                    gameModel.disableEosOverlay(root.gameId)
                                                }
                                                root.eosOverlayEnabled = checked
                                                gameModel.checkEosOverlayEnabled(root.gameId)
                                            }
                                        }
                                        
                                        Label {
                                            text: "The EOS Overlay provides features like social integration and achievements. It can be accessed in-game with Shift+F3."
                                            color: Theme.secondaryText
                                            font.pixelSize: 12
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15

                                        Text { text: "ADVANCED LAUNCHER SETTINGS"; color: Theme.accent; font.pixelSize: 11; font.bold: true }

                                        GridLayout {
                                            columns: 2
                                            rowSpacing: 15
                                            columnSpacing: 20
                                            Layout.fillWidth: true

                                            Label { text: "Command Wrapper"; color: Theme.text; Layout.preferredWidth: 140 }
                                            TheophanyTextField { id: wrapperField; Layout.fillWidth: true; placeholderText: "e.g. firejail --net=none" }

                                            Label { text: "Extra Arguments"; color: Theme.text; Layout.preferredWidth: 140 }
                                            TheophanyTextField { id: extraArgsField; Layout.fillWidth: true; placeholderText: "e.g. -novid" }
                                        }

                                        TheophanyCheckBox {
                                            id: mangohudCheck
                                            text: "Enable MangoHud (Performance Overlay)"
                                            Layout.topMargin: 5
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                                    // SECTION: SCRIPTS
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        Text { text: "AUTOMATION SCRIPTS"; color: Theme.accent; font.pixelSize: 11; font.bold: true }

                                        GridLayout {
                                            columns: 2; Layout.fillWidth: true; rowSpacing: 15
                                            columnSpacing: 20
                                            Label { text: "Pre-launch"; color: Theme.text; Layout.preferredWidth: 140 }
                                            TheophanyTextField { id: preLaunchField; Layout.fillWidth: true; placeholderText: "e.g. disable-compositor.sh" }
                                            Label { text: "Post-launch"; color: Theme.text; Layout.preferredWidth: 140 }
                                            TheophanyTextField { id: postLaunchField; Layout.fillWidth: true; placeholderText: "e.g. enable-compositor.sh" }
                                        }
                                    }



                                    // Section: Gamescope
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        TheophanyCheckBox {
                                            id: gamescopeCheck
                                            text: "Enable Gamescope"
                                        }

                                        GridLayout {
                                            columns: 4
                                            rowSpacing: 15
                                            columnSpacing: 20
                                            visible: gamescopeCheck.checked
                                            Layout.leftMargin: 20
                                            Layout.fillWidth: true
                                            
                                            Label { text: "Width"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyTextField { id: gsWidthField; Layout.fillWidth: true; placeholderText: "1920" }
                                            Label { text: "Height"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyTextField { id: gsHeightField; Layout.fillWidth: true; placeholderText: "1080" }

                                            Label { text: "Output W"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyTextField { id: gsOutWidthField; Layout.fillWidth: true; placeholderText: "3840" }
                                            Label { text: "Output H"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyTextField { id: gsOutHeightField; Layout.fillWidth: true; placeholderText: "2160" }

                                            Label { text: "Refresh"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyTextField { id: gsRefreshField; Layout.fillWidth: true; placeholderText: "60" }
                                            
                                            Label { text: "Scaling"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyComboBox {
                                                id: gsScalingCombo
                                                Layout.fillWidth: true
                                                model: ["Auto", "Integer", "Fit", "Fill", "Stretch"]
                                            }
                                            
                                            Label { text: "Upscaler"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                            TheophanyComboBox {
                                                id: gsUpscalerCombo
                                                Layout.fillWidth: true
                                                model: ["None", "FSR", "NIS", "Pixel"]
                                            }

                                            TheophanyCheckBox {
                                                id: gsFullscreenCheck
                                                text: "Fullscreen"
                                                Layout.columnSpan: 2
                                            }
                                        }
                                    }

                                    // Section: Advanced / Environment
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 15
                                        
                                        // Environment Variables
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 15
                                            
                                            Text { text: "ENVIRONMENT VARIABLES"; color: Theme.accent; font.pixelSize: 11; font.bold: true }
                                            
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 10

                                                Repeater {
                                                    model: envModel
                                                    delegate: RowLayout {
                                                        Layout.fillWidth: true
                                                        TheophanyTextField { 
                                                            text: model.key
                                                            Layout.preferredWidth: 200
                                                            placeholderText: "KEY"
                                                            onTextChanged: { if (text !== model.key) model.key = text; }
                                                        }
                                                        Text { text: "="; color: Theme.secondaryText; font.bold: true }
                                                        TheophanyTextField { 
                                                            text: model.value
                                                            Layout.fillWidth: true
                                                            placeholderText: "VALUE"
                                                            onTextChanged: { if (text !== model.value) model.value = text; }
                                                        }
                                                        TheophanyButton { 
                                                            text: "✕"
                                                            Layout.preferredWidth: 36
                                                            onClicked: envModel.remove(index)
                                                        }
                                                    }
                                                }
                                                
                                                TheophanyButton {
                                                    text: "+ Add Variable"
                                                    Layout.preferredWidth: 180
                                                    Layout.topMargin: 5
                                                    onClicked: envModel.append({ "key": "", "value": "" })
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                                        
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 30
                                            color: "transparent"
                                            
                                            RowLayout {
                                                anchors.fill: parent
                                                Text { text: "ADVANCED SETTINGS"; color: Theme.secondaryText; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true }
                                                Text { 
                                                    text: advancedCollapsed ? "▶" : "▼"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 12
                                                }
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: advancedCollapsed = !advancedCollapsed
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            visible: !advancedCollapsed
                                            spacing: 20

                                            GridLayout {
                                                columns: 2
                                                rowSpacing: 15
                                                columnSpacing: 20
                                                Layout.fillWidth: true
                                                visible: root.isWindows

                                                Label { text: "Store"; color: Theme.text; Layout.preferredWidth: 140 }
                                                TheophanyTextField { id: storeField; Layout.fillWidth: true; placeholderText: "e.g. steam, gog" }

                                                Label { text: "Game ID"; color: Theme.text; Layout.preferredWidth: 140 }
                                                TheophanyTextField { id: umuIdField; Layout.fillWidth: true; placeholderText: "umu-database ID" }

                                                Label { text: "Proton Verb"; color: Theme.text; Layout.preferredWidth: 140 }
                                                TheophanyTextField { id: protonVerbField; Layout.fillWidth: true; placeholderText: "waitforexitandrun" }

                                                Label { text: "Log Level"; color: Theme.text; Layout.preferredWidth: 140 }
                                                TheophanyComboBox {
                                                    id: logLevelCombo
                                                    Layout.fillWidth: true
                                                    model: ["None", "Default (1)", "Debug"]
                                                }
                                            }

                                            RowLayout {
                                                spacing: 25
                                                visible: root.isWindows
                                                TheophanyCheckBox { 
                                                    id: disableFixesCheck; text: "No Fixes"
                                                }
                                                TheophanyCheckBox { 
                                                    id: noRuntimeCheck; text: "No Runtime"
                                                }
                                            }

                                        }
                                    }
                                }
                            }
                        } // End StackLayout
                } // End Main ScrollView

                // Footer Actions
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    color: Theme.background
                    
                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Theme.border
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 15
                        
                        TheophanyButton {
                            text: "Auto Fetch"
                            visible: root.activeTab < 2
                            onClicked: {

                                gameModel.autoScrape(root.gameId)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        TheophanyButton {
                            text: "Cancel"
                            onClicked: root.reject()
                        }
                        
                        TheophanyButton {
                            text: "Save Properties"
                            primary: true
                            Layout.preferredWidth: 160
                            onClicked: {
                                // Construct Metadata JSON
                                // Construct Metadata JSON
                                var meta = {
                                    title: titleField.text,
                                    description: descField.text,
                                    developer: devField.text.replace(/[,;\s]+$/, ""), // Sanitize trailing separators
                                    publisher: pubField.text.replace(/[,;\s]+$/, ""),
                                    genre: genreField.text.replace(/[,;\s]+$/, ""),
                                    tags: tagsField.text.replace(/[,;\s]+$/, ""),
                                    region: regionField.text,
                                    rating: ratingField.value / 10.0,
                                    release_date: releaseField.text.trim() === "" ? "" : (parseInt(releaseField.text) || 0)
                                }
                                
                                gameModel.updateGameMetadata(gameId, JSON.stringify(meta))
                                


                                // Save PC Config if applicable
                                if (root.isPc) {
                                    savePcConfig()
                                }

                                root.accept()
                            }
                        }
                    }
                }
            } // End Main Content ColumnLayout
        }
    }

    function savePcConfig() {
        var envs = {}
        for (var i = 0; i < envModel.count; i++) {
            var item = envModel.get(i)
            if (item.key.trim() !== "") {
                envs[item.key.trim()] = item.value
            }
        }

        var config = {
            "rom_id": gameId,
            "working_dir": workingDirField.text,
            "wrapper": wrapperField.text,
            "use_mangohud": mangohudCheck.checked,
            "pre_launch_script": preLaunchField.text,
            "post_launch_script": postLaunchField.text,
            "use_gamescope": gamescopeCheck.checked,
            "gamescope_args": getGamescopeArgs(),
            "gs_state": {
                "w": gsWidthField.text,
                "h": gsHeightField.text,
                "W": gsOutWidthField.text,
                "H": gsOutHeightField.text,
                "r": gsRefreshField.text,
                "S": gsScalingCombo.currentIndex,
                "U": gsUpscalerCombo.currentIndex,
                "f": gsFullscreenCheck.checked
            },
            "env_vars": JSON.stringify(envs),
            "extra_args": extraArgsField.text
        }

        if (root.isWindows) {
            config["umu_proton_version"] = protonCombo.currentIndex > 0 ? protonCombo.currentValue : (protonField.text || "")
            config["umu_store"] = storeField.text
            config["wine_prefix"] = prefixField.text
            config["umu_id"] = umuIdField.text
            config["proton_verb"] = protonVerbField.text
            config["disable_fixes"] = disableFixesCheck.checked
            config["no_runtime"] = noRuntimeCheck.checked
            config["log_level"] = logLevelCombo.currentText
        }

        // Cloud Saves
        config["cloud_saves_enabled"] = cloudSavesCheck.checked
        config["cloud_save_path"] = cloudSavePathField.text
        config["cloud_save_auto_sync"] = cloudSaveAutoSyncCheck.checked

        gameModel.savePcConfig(JSON.stringify(config))
        gameModel.updateRomPath(gameId, exePathField.text)
    }
    
    Platform.FileDialog {
        id: fileDialog
        property string targetType: ""
        onAccepted: {
            var path = file.toString().replace("file://", "")
            gameModel.updateGameAsset(root.gameId, targetType, path)
            // Note: updateGameAsset calls update_row_by_id on backend, but we might need a refresh here if UI doesn't auto-update currentData
            // Actually root.load is better for full metadata sync
            root.load(root.gameId, root.activeTab)
        }
        function openFor(type) {
            targetType = type
            open()
        }
    }

    Platform.FileDialog {
        id: exePathFileDialog
        title: "Select Game Executable"
        onAccepted: exePathField.text = file.toString().replace("file://", "")
    }

    Platform.FolderDialog {
        id: protonFolderDialog
        onAccepted: {
            protonCombo.currentIndex = 0
            protonField.text = folder.toString().replace("file://", "")
        }
    }

    Platform.FolderDialog {
        id: prefixFolderDialog
        onAccepted: prefixField.text = folder.toString().replace("file://", "")
    }

    Platform.FolderDialog {
        id: workingFolderDialog
        onAccepted: workingDirField.text = folder.toString().replace("file://", "")
    }

    Platform.MessageDialog {
        id: autoScrapeErrorDialog
        title: "Auto Fetch Failed"
        buttons: Platform.MessageDialog.Ok
        onAccepted: {
            scrapeDialog.query = titleField.text
            scrapeDialog.open()
        }
    }

    ScrapeSearchDialog {
        id: scrapeDialog
        query: titleField.text
        ollamaUrl: root.ollamaUrl
        ollamaModel: root.ollamaModel
        geminiKey: root.geminiKey
        openaiKey: root.openaiKey
        llmProvider: root.llmProvider
        platform: root.platformType !== "" ? root.platformType : root.platformName
        onResultSelected: (sourceId, provider) => {
            gameModel.fetchOnlineMetadata(sourceId, provider, root.ollamaUrl, root.ollamaModel, root.geminiKey, root.openaiKey, root.llmProvider)
        }
        // onImageSelected removed as it is now handled by ImageSearchDialog
    }

    ImageSearchDialog {
        id: imageSearchDialog
        gameId: root.gameId
    }

    MetadataCompareDialog {
        id: compareDialog
    }

    Connections {
        target: compareDialog
        function onMetadataApplied(data) {

            
            // 1. Process Assets
            if (data.assets) {

                processScrapedAssets(data.assets)
            } else {

            }

            // 2. Process Text Fields
            if (data.title !== undefined) titleField.text = data.title
            if (data.description !== undefined) descField.text = data.description
            if (data.developer !== undefined) devField.text = data.developer
            if (data.publisher !== undefined) pubField.text = data.publisher
            if (data.genre !== undefined) genreField.text = data.genre
            if (data.region !== undefined) regionField.text = data.region
            if (data.tags !== undefined) tagsField.text = data.tags
            if (data.release_date !== undefined) releaseField.text = data.release_date.toString()
            if (data.rating !== undefined) ratingField.value = Math.round((data.rating || 0) * 10)
            
            // 3. Process Resources
            if (data.resources && Array.isArray(data.resources)) {
                 for (var i = 0; i < data.resources.length; i++) {
                     var r = data.resources[i]
                     if (r.url && r.url !== "") {
                          gameModel.addGameResource(root.gameId, r.type || "Link", r.url, r.label || "")
                     }
                 }
                 gameModel.fetchGameMetadata(root.gameId)
            }
        }
    }

    function processScrapedAssets(assets) {
        try {
            var keys = Object.keys(assets)

            
            for (var i = 0; i < keys.length; i++) {
                var category = keys[i]
                var urls = assets[category]
                
                if (Array.isArray(urls)) {
                    for (var j = 0; j < urls.length; j++) {
                        var url = urls[j]

                        // Using root.gameId which is validated property
                        gameModel.downloadAsset(root.gameId, category, url)
                    }
                }
            }
        } catch (e) {

        }
    }



    ListModel {
        id: envModel
    }


    Connections {
        target: gameModel

        function onEosOverlayEnabledResult(romId, enabled) {
            if (String(root.gameId) === String(romId)) {
                root.eosOverlayEnabled = enabled
            }
        }

        function onAutoScrapeFinished(rom_id, json) {
            if (!root.visible || String(rom_id) !== String(root.gameId)) return;

            try {
                var data = JSON.parse(json)
                if (data.description) descField.text = data.description
                if (data.developer) devField.text = data.developer
                if (data.publisher) pubField.text = data.publisher
                if (data.genre) genreField.text = data.genre
                if (data.tags) tagsField.text = data.tags
                if (data.region) regionField.text = data.region
                
                // For numeric values, we treat 0 as "empty/unset"
                if (data.rating !== undefined) ratingField.value = Math.round((data.rating || 0) * 10)
                if (data.release_year) releaseField.text = data.release_year.toString()
                
                // Add Resources (Links)
                if (data.resources && Array.isArray(data.resources)) {
                     for (var i = 0; i < data.resources.length; i++) {
                         var r = data.resources[i]
                         if (r.url && r.url !== "") {
                               gameModel.addGameResource(rom_id, r.type || "Link", r.url, r.label || "")
                         }
                     }
                     // Refresh the resource list 
                     // We invoke the fetch method again to reload the full metadata including new resources
                     if (String(root.gameId) === String(rom_id)) {
                          gameModel.fetchGameMetadata(rom_id)
                     }
                }

                if (data.assets && root.visible && String(rom_id) === String(root.gameId)) {
                    for (var category in data.assets) {
                        var urls = data.assets[category]
                        if (Array.isArray(urls)) {
                            for (var i = 0; i < urls.length; i++) {
                                 gameModel.downloadAsset(rom_id, category, urls[i])
                            }
                        }
                    }
                }
            } catch (e) {

            }
        }

        function onAssetDownloadFinished(category, path) {
            // No-op to prevent UI resets/freezing while editing metadata.
            // Ticker notifications provide background progress feedback.
        }

        function onAutoScrapeFailed(rom_id, message) {
            if (!root.visible || String(rom_id) !== String(root.gameId)) return;

            autoScrapeErrorDialog.text = message
            autoScrapeErrorDialog.open()
        }

        function onFetchFinished(json) {
            try {
                var meta = JSON.parse(json)
                if (scrapeDialog.visible) {
                    var current = {
                        title: titleField.text,
                        description: descField.text,
                        developer: devField.text,
                        publisher: pubField.text,
                        genre: genreField.text,
                        tags: tagsField.text,
                        region: regionField.text,
                        rating: ratingField.value / 10.0,
                        release_year: parseInt(releaseField.text) || 0
                    }
                    if (scrapeDialog.visible) scrapeDialog.close()
                    compareDialog.init(current, meta)
                    compareDialog.open()
                }
            } catch (e) {

            }
        }
    }

    AiAssistant {
        id: aiDescGen
        onResponseChanged: {
            descField.text = currentResponse
        }
        onGeneratingChanged: {
            if (!isGenerating) {
                aiDescPollTimer.stop()
            }
        }
    }

    Timer {
        id: aiDescPollTimer
        interval: 50
        repeat: true
        onTriggered: aiDescGen.pollResponse()
    }

    ListModel { id: protonVersionsModel }

    function refreshProtonVersions() {
        protonVersionsModel.clear()
        protonVersionsModel.append({ "name": "Default (umu-run choice)", "path": "" })
        protonVersionsModel.append({ "name": "Auto (GE-Proton)", "path": "GE-Proton" })
        if (platformModel) {
            try {
                var versions = JSON.parse(platformModel.getProtonVersions())
                for (var i = 0; i < versions.length; i++) {
                    protonVersionsModel.append(versions[i])
                }
            } catch(e) {}
        }
    }

    Component.onCompleted: refreshProtonVersions()
}
