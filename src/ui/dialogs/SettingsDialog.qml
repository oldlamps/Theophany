import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"
import Theophany.Bridge 1.0

Dialog {
    id: root
    width: Math.max(800, window.width * 0.85)
    height: Math.max(600, window.height * 0.85)
    title: "Settings"
    modal: true

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12

        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }

    signal settingsApplied(int viewMode, bool showFilter, string defRegion, string themeName, string raUser, string raToken, bool raEnabled, bool showTray, bool closeToTray, bool aiEnabled, string ollamaUrl, string ollamaModel, bool detailsPreferVideo, bool ignoreTheInSort, string aiDescriptionPrompt, bool defaultIgnoreOnDelete, string activeMeta, string activeImage, string geminiKey, string openaiKey, string llmProvider, bool saveHeroicLocally, bool autoRescan, bool confirmQuit, real gridScale, bool useCustomYtdlp, string customYtdlpPath, string defaultProtonRunner, string defaultProtonPrefix, string defaultProtonWrapper, bool defaultProtonUseGamescope, bool defaultProtonUseMangohud, string defaultProtonGamescopeArgs, string defaultProtonGamescopeW, string defaultProtonGamescopeH, string defaultProtonGamescopeOutW, string defaultProtonGamescopeOutH, string defaultProtonGamescopeRefresh, int defaultProtonGamescopeScaling, int defaultProtonGamescopeUpscaler, bool defaultProtonGamescopeFullscreen, bool hidePlatformsSidebar, bool checkUpdates, bool useCustomLegendary, string customLegendaryPath, string defaultInstallLocation)

    property int currentViewMode: 0
    property bool currentShowFilterBar: false
    property string currentDefaultRegion: ""
    property string currentTheme: "System"
    property string currentRaUser: ""
    property string currentRaToken: ""
    property bool currentRaEnabled: false
    property bool currentShowTrayIcon: true
    property bool currentCloseToTray: false

    property bool currentAiEnabled: false
    property string currentOllamaUrl: "http://localhost:11434"
    property string currentOllamaModel: "llama3"
    property string currentAiDescriptionPrompt: ""

    property bool currentDetailsPreferVideo: false
    property bool currentIgnoreTheInSort: true
    property bool currentDefaultIgnoreOnDelete: true
    property string currentActiveMeta: "IGDB"
    property string currentActiveImage: "Web Search"

    property string currentGeminiKey: ""
    property string currentOpenaiKey: ""
    property string currentLlmProvider: "Gemini"
    property bool currentSaveHeroicAssetsLocally: false
    property bool currentAutoRescanOnStartup: false
    property bool currentConfirmOnQuit: true
    property real currentGridScale: 1.0
    property bool currentUseCustomYtdlp: false
    property string currentCustomYtdlpPath: ""
    property string currentDefaultProtonRunner: ""
    property string currentDefaultProtonPrefix: ""
    property string currentDefaultProtonWrapper: ""
    property bool currentDefaultProtonUseGamescope: false
    property bool currentDefaultProtonUseMangohud: false
    property string currentDefaultProtonGamescopeArgs: ""
    property string currentDefaultProtonGamescopeW: ""
    property string currentDefaultProtonGamescopeH: ""
    property string currentDefaultProtonGamescopeOutW: ""
    property string currentDefaultProtonGamescopeOutH: ""
    property string currentDefaultProtonGamescopeRefresh: ""
    property int currentDefaultProtonGamescopeScaling: 0
    property int currentDefaultProtonGamescopeUpscaler: 0
    property bool currentDefaultProtonGamescopeFullscreen: false
    property bool currentHidePlatformsSidebar: false
    property bool currentCheckForUpdatesOnStartup: true
    property bool currentUseCustomLegendary: false
    property string currentCustomLegendaryPath: ""
    property string currentDefaultInstallLocation: ""

    property string ytdlpStatus: ""
    property bool ytdlpFound: false
    property string legendaryStatus: ""
    property bool legendaryFound: false
    property string eosOverlayInfo: ""
    property string eosOverlayStatus: ""

    function checkEosOverlay() {
        eosOverlayInfo = "Checking..."
        appInfoPollTimer.start()
        appInfo.triggerEosOverlayCheck()
    }

    function checkYtdlp() {
        var customPath = customYtdlpSwitch.checked ? ytdlpPathField.text : ""
        var result = JSON.parse(appInfo.checkYtdlp(customPath))
        ytdlpFound = result.found
        if (ytdlpFound) {
            ytdlpStatus = "Detected (Version: " + result.version + ")"
        } else {
            ytdlpStatus = "Not Found"
        }
    }

    function checkLegendary() {
        var customPath = customLegendarySwitch.checked ? legendaryPathField.text : ""
        var result = JSON.parse(appInfo.checkLegendary(customPath))
        legendaryFound = result.found
        if (legendaryFound) {
            legendaryStatus = "Detected (Version: " + result.version + ")"
        } else {
            legendaryStatus = "Not Found"
        }
    }

    property var platformModel: null

    property var availableRegions: []
    property var availableScrapers: []

    property string tempRaUser: ""
    property string tempRaToken: ""
    property bool tempRaEnabled: false
    property string raErrorMessage: ""

    property int activeTab: 0
    
    function openTab(tabName) {
        var tabs = ["Interface", "Library", "Accounts", "Input", "System", "About"]
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].toLowerCase() === tabName.toLowerCase()) {
                activeTab = i
                break
            }
        }
    }

    RetroAchievements {
        id: raBridge
        onLoginSuccess: (user) => {
            root.tempRaUser = user
            root.tempRaEnabled = true
            root.raErrorMessage = ""
        }
        onLoginError: (msg) => {
            root.raErrorMessage = "Error: " + msg
            root.tempRaEnabled = false
        }
        onErrorOccurred: (msg) => {
             root.raErrorMessage = msg
        }
    }

    AppInfo { 
        id: appInfo 
        onLegendaryDownloadStatus: (success, message) => {
            appInfoPollTimer.stop()
            root.legendaryStatus = message
            root.legendaryFound = success
            if (success) {
                checkLegendary()
            }
        }
        onYtdlpDownloadStatus: (success, message) => {
            root.ytdlpStatus = String(message)
            if (success || root.ytdlpStatus.indexOf("failed") !== -1 || root.ytdlpStatus.indexOf("Error") !== -1) {
                appInfoPollTimer.stop()
                root.checkYtdlp()
            }
        }
        onEosOverlayStatus: (success, message) => {
            root.eosOverlayStatus = message
            checkEosOverlay()
        }
        onEosOverlayInfoReceived: (info) => {
            eosOverlayInfo = info
            // Clear status message if it was a technical status like "Installing..." or "Checking..."
            // Leave it if it's "Installation complete" etc? 
            // Actually, checkEosOverlay sets eosOverlayInfo to "Checking...", let's just clear status.
            if (root.eosOverlayStatus.indexOf("...") !== -1) {
                root.eosOverlayStatus = ""
            }
        }
    }

    Timer {
        id: appInfoPollTimer
        interval: 100
        repeat: true
        running: false
        onTriggered: appInfo.checkAsyncResponses()
    }
    StoreBridge { id: storeBridge }

    ListModel {
        id: llmModelList
    }

    Timer {
        id: aiPollTimer
        interval: 100
        running: root.opened && aiOnBtn.checked
        repeat: true
        onTriggered: aiBridge.pollResponse()
    }

    AiAssistant {
        id: aiBridge
        onModelsLoaded: (json) => {
            try {
                var models = JSON.parse(json)
                llmModelList.clear()
                if (models && models.length > 0) {
                    for (var i = 0; i < models.length; i++) {
                        llmModelList.append({ "modelName": models[i] })
                    }

                    // Use Qt.callLater to safely update selection after model is applied
                    Qt.callLater(() => {
                        var modelName = root.currentOllamaModel
                        var idx = -1
                        for (var j = 0; j < llmModelList.count; j++) {
                            if (llmModelList.get(j).modelName === modelName) {
                                idx = j
                                break
                            }
                        }
                        if (idx >= 0) {
                            ollamaModelBox.currentIndex = idx
                            ollamaModelBox.displayText = modelName
                        } else if (llmModelList.count > 0) {
                            ollamaModelBox.currentIndex = 0
                            ollamaModelBox.displayText = llmModelList.get(0).modelName
                        }
                    })

                    aiStatusLabel.text = "Models refreshed (" + models.length + " found)"
                    aiStatusLabel.color = Theme.accent
                } else {
                    aiStatusLabel.text = "No models found"
                    aiStatusLabel.color = "#ffaa00"
                }
            } catch(e) { }
        }
        onConnectionTested: (success, message) => {
            aiStatusLabel.text = message
            // Use a brighter green for visibility, or standard red
            aiStatusLabel.color = success ? "#00FF00" : "#ff5555"
        }
    }

    Timer {
        interval: 100
        running: root.visible
        repeat: true
        onTriggered: raBridge.poll()
    }

    ListModel {
        id: hotkeyModel
    }

    Popup {
        id: keyCapturePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 400
        height: 250
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property string targetAction: ""
        property string currentSequence: ""

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.accent
            border.width: 2
            radius: 12
            layer.enabled: true
            layer.effect: DropShadow { color: "#80000000"; radius: 20 }
        }

        contentItem: ColumnLayout {
            spacing: 20
            Label {
                text: "Remap '" + keyCapturePopup.targetAction + "'"
                font.bold: true
                font.pixelSize: 20
                color: Theme.text
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: "Press the new key combination..."
                color: Theme.secondaryText
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                color: Theme.background
                radius: 8
                border.color: Theme.border

                Label {
                    anchors.centerIn: parent
                    text: keyCapturePopup.currentSequence === "" ? "..." : keyCapturePopup.currentSequence
                    font.pixelSize: 24
                    font.bold: true
                    color: Theme.accent
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20
                TheophanyButton {
                    text: "Cancel"
                    onClicked: keyCapturePopup.close()
                }
                TheophanyButton {
                    text: "Save"
                    enabled: keyCapturePopup.currentSequence !== ""
                    onClicked: {
                        appSettings.setHotkey(keyCapturePopup.targetAction, keyCapturePopup.currentSequence)
                        root.refreshHotkeys()
                        keyCapturePopup.close()
                    }
                }
            }
        }

        onOpened: {
            currentSequence = ""
            keyCaptureItem.forceActiveFocus()
        }

        Item {
            id: keyCaptureItem
            focus: true
            Keys.onPressed: (event) => {
                var seq = root.formatKeySequence(event)
                if (seq !== "") {
                    keyCapturePopup.currentSequence = seq
                    event.accepted = true
                }
            }
        }
    }

    function formatKeySequence(event) {
        var s = []
        if (event.modifiers & Qt.ControlModifier) s.push("Ctrl")
        if (event.modifiers & Qt.ShiftModifier) s.push("Shift")
        if (event.modifiers & Qt.AltModifier) s.push("Alt")
        if (event.modifiers & Qt.MetaModifier) s.push("Meta")

        var key = event.key
        if (key === Qt.Key_Control || key === Qt.Key_Shift || key === Qt.Key_Alt || key === Qt.Key_Meta) return ""

        var text = ""
        var special = {
            [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return",
            [Qt.Key_Escape]: "Esc", [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab",
            [Qt.Key_Backspace]: "Backspace", [Qt.Key_Delete]: "Del",
            [Qt.Key_Insert]: "Ins", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
            [Qt.Key_PageUp]: "PgUp", [Qt.Key_PageDown]: "PgDown",
            [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right",
            [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
            [Qt.Key_Space]: "Space",
            [Qt.Key_F1]: "F1", [Qt.Key_F2]: "F2", [Qt.Key_F3]: "F3", [Qt.Key_F4]: "F4",
            [Qt.Key_F5]: "F5", [Qt.Key_F6]: "F6", [Qt.Key_F7]: "F7", [Qt.Key_F8]: "F8",
            [Qt.Key_F9]: "F9", [Qt.Key_F10]: "F10", [Qt.Key_F11]: "F11", [Qt.Key_F12]: "F12"
        }

        if (special[key]) text = special[key]
        else if (key >= Qt.Key_A && key <= Qt.Key_Z) text = String.fromCharCode(key).toUpperCase()
        else if (key >= Qt.Key_0 && key <= Qt.Key_9) text = String.fromCharCode(key)
        else if (event.text && event.text.length > 0) text = event.text.toUpperCase()
        else if (key == 44) text = ","
        else text = String.fromCharCode(key)

        if (text !== "") s.push(text)
        else return ""

        return s.join("+")
    }

    function refreshHotkeys() {
        hotkeyModel.clear()
        if (appSettings.hotkeysJson && appSettings.hotkeysJson !== "") {
            try {
                var map = JSON.parse(appSettings.hotkeysJson)
                var order = ["Search", "GlobalSearch", "Settings", "Quit", "Refresh", "Launch", "Edit", "CycleNext", "CyclePrev", "Back", "Forward", "NextLetter", "PrevLetter", "PageUp", "PageDown", "Home", "End", "ScrapeManual", "ScrapeAuto", "Achievements", "ImageViewer", "VideoExplorer", "FilterBar", "ToggleSidebar", "Escape"]
                var names = {
                    "Search": "Search", "GlobalSearch": "Global Search (Island)", "Settings": "Settings", "Quit": "Quit App", "Refresh": "Refresh Library",
                    "Launch": "Launch Game", "Edit": "Edit Metadata", "CycleNext": "Next Platform", "CyclePrev": "Prev Platform",
                    "Back": "Back", "Forward": "Forward", "NextLetter": "Next Letter (Nav)", "PrevLetter": "Prev Letter (Nav)",
                    "PageUp": "Page Up", "PageDown": "Page Down", "Home": "Jump to Start", "End": "Jump to End",
                    "ScrapeManual": "Scrape (Manual)", "ScrapeAuto": "Scrape (Auto)", "Achievements": "Update Achievements",
                    "ImageViewer": "Image Viewer", "VideoExplorer": "Video Explorer", "FilterBar": "Toggle Filter Bar",
                    "ToggleSidebar": "Toggle Sidebar", "Escape": "Close Overlays / Escape"
                }

                for (var i = 0; i < order.length; i++) {
                    var key = order[i]
                    if (map[key]) {
                        hotkeyModel.append({ "action": names[key] || key, "actionKey": key, "shortcut": map[key] })
                    }
                }
            } catch (e) { }
        }
    }

    ListModel {
        id: ignoreListModel
    }

    function refreshIgnoreList() {
        ignoreListModel.clear()
        var json = gameModel.getIgnoreList()
        var list = JSON.parse(json)
        for (var i = 0; i < list.length; i++) {
            ignoreListModel.append(list[i])
        }
    }

    onOpened: {
        refreshProtonVersions()

        gridBtn.checked = (currentViewMode === 0)
        listBtn.checked = (currentViewMode === 1)
        filterSwitch.checked = currentShowFilterBar
        traySwitch.checked = currentShowTrayIcon
        closeToTraySwitch.checked = currentCloseToTray
        hidePlatformsSidebarSwitch.checked = currentHidePlatformsSidebar
        checkUpdatesSwitch.checked = currentCheckForUpdatesOnStartup

        preferVideoSwitch.checked = currentDetailsPreferVideo
        ignoreTheInSortSwitch.checked = currentIgnoreTheInSort
        defaultIgnoreOnDeleteSwitch.checked = currentDefaultIgnoreOnDelete
        gridScaleSlider.value = currentGridScale

        aiOnBtn.checked = currentAiEnabled
        ollamaUrlField.text = currentOllamaUrl !== "" ? currentOllamaUrl : "http://localhost:11434"

        if (aiOnBtn.checked) {
            aiBridge.fetchLocalModels(ollamaUrlField.text)
        }

        if (currentAiDescriptionPrompt !== "") {
            descPromptArea.text = currentAiDescriptionPrompt
        } else {
            descPromptArea.text = "Write a concise, engaging description for the video game '{title}'. Use the following existing description as context if available: '{description}'. Focus on key gameplay mechanics and plot. Keep it under 150 words. Do not include conversational filler like 'Here is a description', just return the description text."
        }

        geminiKeyField.text = currentGeminiKey
        openaiKeyField.text = currentOpenaiKey
        var pIdx = llmProviderBox.model.indexOf(currentLlmProvider)
        if (pIdx >= 0) llmProviderBox.currentIndex = pIdx
        else llmProviderBox.currentIndex = 0

        var idx = availableRegions.indexOf(currentDefaultRegion)
        if (idx >= 0) regionBox.currentIndex = idx
        else regionBox.currentIndex = 0

        var tIdx = themeBox.model.indexOf(currentTheme)
        if (tIdx >= 0) themeBox.currentIndex = tIdx

        // Match metaScraperBox to the current setting
        var metaIdx = metaScraperBox.find(root.currentActiveMeta)
        if (metaIdx >= 0) metaScraperBox.currentIndex = metaIdx
        else if (availableScrapers.length > 0) {
            var igdbIdx = metaScraperBox.find("IGDB")
            metaScraperBox.currentIndex = igdbIdx >= 0 ? igdbIdx : 0
        }

        // Match imgScraperBox to the current setting
        var imgIdx = imgScraperBox.find(root.currentActiveImage)
        if (imgIdx >= 0) imgScraperBox.currentIndex = imgIdx
        else if (availableScrapers.length > 0) {
            var webIdx = imgScraperBox.find("Web Search")
            imgScraperBox.currentIndex = webIdx >= 0 ? webIdx : 0
        }

        saveHeroicLocallySwitch.checked = currentSaveHeroicAssetsLocally
        autoRescanSwitch.checked = currentAutoRescanOnStartup
        confirmQuitSwitch.checked = currentConfirmOnQuit
        customYtdlpSwitch.checked = currentUseCustomYtdlp
        ytdlpPathField.text = currentCustomYtdlpPath
        checkYtdlp()

        customLegendarySwitch.checked = currentUseCustomLegendary
        legendaryPathField.text = currentCustomLegendaryPath
        checkLegendary()
        checkEosOverlay()

        // Proton Defaults
        var runnerIdx = 0
        for (var p = 0; p < protonVersionsModel.count; p++) {
            if (protonVersionsModel.get(p).path === currentDefaultProtonRunner) {
                runnerIdx = p
                break
            }
        }
        protonDefaultCombo.currentIndex = runnerIdx
        protonPrefixField.text = currentDefaultProtonPrefix
        protonWrapperField.text = currentDefaultProtonWrapper
        protonUseGamescopeSwitch.checked = currentDefaultProtonUseGamescope
        protonGamescopeArgsField.text = currentDefaultProtonGamescopeArgs

        tempRaUser = currentRaUser
        tempRaToken = currentRaToken
        tempRaEnabled = currentRaEnabled

        raUserField.text = tempRaUser
        raKeyField.text = tempRaToken
        defaultInstallLocationField.text = currentDefaultInstallLocation

        refreshIgnoreList()
        refreshHotkeys()
    }

    header: Item { height: 0 }

    contentItem: Item {
        id: settingsContainer
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 220
                color: Theme.background

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Theme.border
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        Label {
                            anchors.centerIn: parent
                            text: "THEOPHANY"
                            font.bold: true
                            font.pixelSize: 20
                            font.letterSpacing: 4
                            color: Theme.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 4

                        Repeater {
                            model: ["Interface", "Library", "Accounts", "Input", "System", "About"]
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

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 20
                        text: "v" + rootAppInfo.getVersion() + " Beta"
                        color: Theme.secondaryText
                        font.pixelSize: 10
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    color: "transparent"
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: ["Interface Settings", "Library & Data", "Linked Accounts", "Input & Hotkeys", "System Behavior", "About Theophany"][root.activeTab]
                        font.pixelSize: 24
                        font.bold: true
                        color: Theme.text
                    }
                }

                ScrollView {
                    id: scrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: -1
                    clip: true

                    Connections {
                        target: root
                        function onActiveTabChanged() {
                            scrollView.ScrollBar.vertical.position = 0
                        }
                    }

                    StackLayout {
                        width: parent.width
                        currentIndex: root.activeTab

                        // INTERFACE TAB
                        Item {
                            implicitHeight: interfaceGrid.height + 100
                            GridLayout {
                                id: interfaceGrid
                                anchors.top: parent.top
                                anchors.topMargin: 20
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8
                                columns: 2
                                rowSpacing: 25
                                columnSpacing: 30

                                Label { text: "Visual Theme"; color: Theme.secondaryText; font.bold: true }
                                TheophanyComboBox {
                                    id: themeBox
                                    model: ["System", "Theophany Midnight", "Nord", "Dracula", "Catppuccin", "Tokyo Night", "Gruvbox Dark", "One Dark Pro", "Latte", "Frost", "Pearl", "That 70's Theme", "That 70's Theme Light", "That 80's Theme", "That 80's Theme Light", "That 90's Theme", "That 90's Theme Light"]
                                    Layout.fillWidth: true
                                    onActivated: {
                                        // Apply theme immediately for live preview
                                        Theme.setTheme(themeBox.currentText)
                                        appSettings.themeName = themeBox.currentText
                                        appSettings.save()
                                    }
                                }

                                Label { text: "Grid Scale"; color: Theme.secondaryText; font.bold: true }
                                RowLayout {
                                    spacing: 15
                                    Slider {
                                        id: gridScaleSlider
                                        from: 0.5; to: 1.5; stepSize: 0.1
                                        Layout.fillWidth: true
                                        onMoved: window.gridScale = value
                                    }
                                    Label {
                                        text: gridScaleSlider.value.toFixed(1) + "x"
                                        color: Theme.text
                                        font.bold: true
                                        Layout.preferredWidth: 40
                                    }
                                }

                                Label { text: "Default View Mode"; color: Theme.secondaryText; font.bold: true }
                                RowLayout {
                                    spacing: 20
                                    ButtonGroup { id: viewGroup }
                                    TheophanyButton {
                                        id: gridBtn
                                        text: "Grid View"
                                        checkable: true
                                        checked: root.currentViewMode === 0
                                        ButtonGroup.group: viewGroup
                                        Layout.preferredWidth: 120
                                    }
                                    TheophanyButton {
                                        id: listBtn
                                        text: "List View"
                                        checkable: true
                                        checked: root.currentViewMode === 1
                                        ButtonGroup.group: viewGroup
                                        Layout.preferredWidth: 120
                                    }
                                }

                                Label { text: "Search & Filtering"; color: Theme.secondaryText; font.bold: true }
                                RowLayout {
                                    spacing: 15
                                    TheophanySwitch { id: filterSwitch; checked: root.currentShowFilterBar }
                                    Label { text: "Always show filter bar on startup"; color: Theme.text }
                                }

                                Label { text: "Sidebar Layout"; color: Theme.secondaryText; font.bold: true }
                                RowLayout {
                                    spacing: 15
                                    TheophanySwitch { id: hidePlatformsSidebarSwitch; checked: root.currentHidePlatformsSidebar }
                                    Label { text: "Hide Platforms section from sidebar"; color: Theme.text }
                                }
                            }
                        }

                        // LIBRARY TAB
                        Item {
                             implicitHeight: libraryLayout.height + 100
                             ColumnLayout {
                                 id: libraryLayout
                                 anchors.top: parent.top
                                 anchors.topMargin: 20
                                 anchors.horizontalCenter: parent.horizontalCenter
                                 width: parent.width * 0.8
                                 spacing: 30

                                 GridLayout {
                                     columns: 2
                                     rowSpacing: 25
                                     columnSpacing: 30
                                     Layout.fillWidth: true

                                     Label { text: "Preferred Metadata Source"; color: Theme.secondaryText; font.bold: true }
                                     TheophanyComboBox { id: metaScraperBox; model: root.availableScrapers; Layout.fillWidth: true }

                                     Label { text: "Preferred Image Source"; color: Theme.secondaryText; font.bold: true }
                                     TheophanyComboBox { id: imgScraperBox; model: ["Web Search"]; Layout.fillWidth: true }

                                     Label { text: "Default Region"; color: Theme.secondaryText; font.bold: true }
                                     TheophanyComboBox { id: regionBox; model: root.availableRegions; Layout.fillWidth: true }
                                 }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 ColumnLayout {
                                     spacing: 15
                                     Layout.fillWidth: true
                                     Label { text: "Game Detail View Preferences"; color: Theme.secondaryText; font.bold: true }
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: preferVideoSwitch; checked: root.currentDetailsPreferVideo }
                                         Label { text: "Prioritize video content over box art if available"; color: Theme.text }
                                     }
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: ignoreTheInSortSwitch; checked: root.currentIgnoreTheInSort }
                                         Label { text: "Ignore 'The' in alphabetical sorting"; color: Theme.text }
                                     }
                                 }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 ColumnLayout {
                                     spacing: 15
                                     Layout.fillWidth: true
                                     Label { text: "Platform Specific"; color: Theme.secondaryText; font.bold: true }
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: saveHeroicLocallySwitch; checked: root.currentSaveHeroicAssetsLocally }
                                         Label { text: "Save Heroic art assets locally (instead of symlinks)"; color: Theme.text }
                                     }
                                 }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 ColumnLayout {
                                     spacing: 15
                                     Layout.fillWidth: true
                                     Layout.fillHeight: true
                                     Label { text: "Ignored ROMs"; color: Theme.secondaryText; font.bold: true }
                                     ListView {
                                         id: ignoreListView
                                         Layout.fillWidth: true
                                         Layout.preferredHeight: 150
                                         model: ignoreListModel
                                         clip: true
                                         spacing: 8
                                         delegate: Rectangle {
                                             width: ListView.view.width
                                             height: 40
                                             color: Theme.sidebar
                                             radius: 6
                                             RowLayout {
                                                 anchors.fill: parent
                                                 anchors.margins: 10
                                                 Label {
                                                     text: path.split('/').pop()
                                                     Layout.fillWidth: true
                                                     elide: Text.ElideRight
                                                     color: Theme.text
                                                 }
                                                 TheophanyButton {
                                                     text: "Remove"
                                                     Layout.preferredHeight: 24
                                                     onClicked: {
                                                         gameModel.removeFromIgnoreList(platform_id, path)
                                                         root.refreshIgnoreList()
                                                     }
                                                 }
                                             }
                                         }
                                     }
                                 }
                             }
                        }

                        // ACCOUNTS TAB
                        Item {
                            implicitHeight: accountsContent.height + 100
                            ColumnLayout {
                                id: accountsContent
                                anchors.top: parent.top
                                anchors.topMargin: 20
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8
                                spacing: 40

                                // RETROACHIEVEMENTS SECTION
                                ColumnLayout {
                                    id: raContent
                                    Layout.fillWidth: true
                                    spacing: 30

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 100
                                        color: Theme.sidebar
                                        radius: 10
                                        border.color: Theme.border
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 20
                                            spacing: 20
                                            Image {
                                                source: "file://" + appInfo.getAssetsDir() + "/RA.png"
                                                Layout.preferredWidth: 50
                                                Layout.preferredHeight: 50
                                                fillMode: Image.PreserveAspectFit
                                            }
                                            ColumnLayout {
                                                Label { text: "RetroAchievements"; font.bold: true; font.pixelSize: 18; color: Theme.text }
                                                Label { text: "Compete and track your legacy across systems."; color: Theme.secondaryText; font.pixelSize: 12 }
                                            }
                                        }
                                    }

                                    GridLayout {
                                        columns: 2
                                        rowSpacing: 20
                                        columnSpacing: 20
                                        Layout.fillWidth: true
                                        Label { text: "Username"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyTextField {
                                            id: raUserField
                                            Layout.fillWidth: true
                                            onTextChanged: root.tempRaUser = text
                                        }
                                        Label { text: "API Key"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyTextField {
                                            id: raKeyField
                                            Layout.fillWidth: true
                                            echoMode: TextInput.Password
                                            onTextChanged: root.tempRaToken = text
                                        }
                                        
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "<a href='https://retroachievements.org/settings'>Get API Key from RetroAchievements</a>"
                                            color: Theme.accent
                                            linkColor: Theme.accent
                                            font.pixelSize: 11
                                            onLinkActivated: (link) => Qt.openUrlExternally(link)
                                        }
                                    }

                                    RowLayout {
                                         Layout.fillWidth: true
                                         Label {
                                             id: loginStatusLabel
                                             text: root.raErrorMessage !== "" ? root.raErrorMessage : (root.tempRaEnabled ? "Status: Logged in as " + root.tempRaUser : "Status: Not authenticated")
                                             color: root.raErrorMessage !== "" ? "red" : (root.tempRaEnabled ? Theme.accent : Theme.secondaryText)
                                             font.bold: true
                                         }
                                         Item { Layout.fillWidth: true }
                                         TheophanyButton {
                                             text: root.tempRaEnabled ? "Logout" : "Login"
                                             onClicked: {
                                                 if (root.tempRaEnabled) {
                                                     root.tempRaEnabled = false
                                                     root.raErrorMessage = ""
                                                 } else {
                                                     root.raErrorMessage = "" 
                                                     raBridge.login(raUserField.text, raKeyField.text)
                                                 }
                                             }
                                         }
                                     }
                                }

                                Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                // STEAM ACCOUNT SECTION
                                ColumnLayout {
                                    id: steamContent
                                    Layout.fillWidth: true
                                    spacing: 30

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 100
                                        color: Theme.sidebar
                                        radius: 10
                                        border.color: Theme.border
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 20
                                            spacing: 20
                                            Image {
                                                source: "file://" + appInfo.getAssetsDir() + "/systems/steam.png"
                                                Layout.preferredWidth: 50
                                                Layout.preferredHeight: 50
                                                fillMode: Image.PreserveAspectFit
                                            }
                                            ColumnLayout {
                                                Label { text: "Steam Account"; font.bold: true; font.pixelSize: 18; color: Theme.text }
                                                Label { text: "Fetch uninstalled games from your public Steam library."; color: Theme.secondaryText; font.pixelSize: 12 }
                                            }
                                        }
                                    }

                                    GridLayout {
                                        columns: 2
                                        rowSpacing: 20
                                        columnSpacing: 20
                                        Layout.fillWidth: true

                                        Label { text: "Steam ID (64-bit)"; color: Theme.secondaryText; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10
                                            TheophanyTextField {
                                                id: steamIdField
                                                Layout.fillWidth: true
                                                text: appSettings.steamId
                                                onEditingFinished: appSettings.steamId = text
                                            }
                                            TheophanyButton {
                                                text: "Auto-detect"
                                                onClicked: {
                                                    var detected = storeBridge.auto_detect_steam_id()
                                                    if (detected !== "") {
                                                        steamIdField.text = detected
                                                        appSettings.steamId = detected
                                                    }
                                                }
                                            }
                                        }

                                        Label { text: "Web API Key"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyTextField {
                                            id: steamKeyField
                                            Layout.fillWidth: true
                                            echoMode: TextInput.Password
                                            text: appSettings.steamApiKey
                                            onEditingFinished: appSettings.steamApiKey = text
                                        }
                                        
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "<a href='https://steamcommunity.com/dev/apikey'>Get API Key from Steam</a>"
                                            color: Theme.accent
                                            linkColor: Theme.accent
                                            font.pixelSize: 11
                                            onLinkActivated: (link) => Qt.openUrlExternally(link)
                                        }
                                    }
                                }

                                Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                // AI CAPABILITIES SECTION
                                ColumnLayout {
                                    id: aiContent
                                    Layout.fillWidth: true
                                    spacing: 30

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 100
                                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                                        radius: 10
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 20
                                            spacing: 20
                                            Label { text: "✨"; font.pixelSize: 32 }
                                            ColumnLayout {
                                                Label { text: "AI Capabilities"; font.bold: true; font.pixelSize: 18; color: Theme.text }
                                                Label { text: "Use local or cloud based LLMs for metadata (experimental)"; color: Theme.secondaryText; font.pixelSize: 12 }
                                            }
                                            Item { Layout.fillWidth: true }
                                            TheophanySwitch { id: aiOnBtn; checked: root.currentAiEnabled }
                                        }
                                    }

                                    GridLayout {
                                        columns: 2
                                        rowSpacing: 20
                                        columnSpacing: 30
                                        Layout.fillWidth: true
                                        enabled: aiOnBtn.checked
                                        opacity: aiOnBtn.checked ? 1.0 : 0.4

                                        Label { text: "Preferred Metadata LLM"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyComboBox { id: llmProviderBox; model: ["Ollama", "Gemini", "OpenAI"]; Layout.fillWidth: true }

                                        Label { text: "Gemini Key"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyTextField { id: geminiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password }

                                        Label { text: "OpenAI Key"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyTextField { id: openaiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password }

                                        Label { text: "Ollama URL"; color: Theme.secondaryText; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10
                                            TheophanyTextField { id: ollamaUrlField; Layout.fillWidth: true; enabled: aiOnBtn.checked }
                                            TheophanyButton {
                                                text: "Test"
                                                enabled: aiOnBtn.checked
                                                onClicked: aiBridge.testConnection(ollamaUrlField.text)
                                            }
                                        }

                                        Label { text: "Ollama Model"; color: Theme.secondaryText; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10
                                            TheophanyComboBox {
                                                id: ollamaModelBox
                                                Layout.fillWidth: true
                                                enabled: aiOnBtn.checked
                                                model: llmModelList
                                                textRole: "modelName"
                                            }
                                            TheophanyButton {
                                                text: "🔄"
                                                enabled: aiOnBtn.checked
                                                onClicked: aiBridge.fetchLocalModels(ollamaUrlField.text)
                                            }
                                        }
                                    }

                                    Label {
                                        id: aiStatusLabel
                                        text: "Ollama Status: Ready"
                                        color: Theme.secondaryText
                                        font.pixelSize: 11
                                        font.italic: true
                                        visible: aiOnBtn.checked
                                    }

                                    ColumnLayout {
                                        spacing: 10
                                        Layout.fillWidth: true
                                        enabled: aiOnBtn.checked
                                        opacity: aiOnBtn.checked ? 1.0 : 0.4
                                        Label { text: "Metadata Prompt Template"; color: Theme.secondaryText; font.bold: true }
                                        TheophanyTextArea { id: descPromptArea; Layout.fillWidth: true; Layout.preferredHeight: 120; enabled: aiOnBtn.checked }
                                    }
                                }
                            }
                        }

                        // INPUT TAB
                        Item {
                             ColumnLayout {
                                 anchors.fill: parent
                                 anchors.margins: 30
                                 spacing: 20
                                 ListView {
                                     Layout.fillWidth: true
                                     Layout.fillHeight: true
                                     model: hotkeyModel
                                     clip: true
                                     spacing: 10
                                     delegate: Rectangle {
                                         width: ListView.view.width
                                         height: 50
                                         color: Theme.secondaryBackground
                                         border.color: Theme.border
                                         radius: 6
                                         RowLayout {
                                             anchors.fill: parent
                                             anchors.margins: 15
                                             Label { text: action; Layout.fillWidth: true; font.bold: true; color: Theme.text }
                                             Label { text: shortcut; font.family: "Monospace"; color: Theme.accent }
                                             TheophanyButton {
                                                 text: "Remap"
                                                 Layout.preferredHeight: 28
                                                 onClicked: {
                                                     keyCapturePopup.targetAction = actionKey
                                                     keyCapturePopup.open()
                                                 }
                                             }
                                         }
                                     }
                                 }
                             }
                        }

                        // SYSTEM TAB
                        Item {
                             implicitHeight: systemLayout.height + 200
                             ColumnLayout {
                                 id: systemLayout
                                 anchors.top: parent.top
                                 anchors.topMargin: 20
                                 anchors.horizontalCenter: parent.horizontalCenter
                                 width: parent.width * 0.8
                                 spacing: 30

                                 Label { text: "General Behavior"; color: Theme.secondaryText; font.bold: true }
                                 ColumnLayout {
                                     spacing: 15
                                     Layout.fillWidth: true
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: autoRescanSwitch; checked: root.currentAutoRescanOnStartup }
                                         Label { text: "Rescan library on startup"; color: Theme.text }
                                     }
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: confirmQuitSwitch; checked: root.currentConfirmOnQuit }
                                         Label { text: "Confirm exit"; color: Theme.text }
                                     }
                                      RowLayout {
                                          spacing: 15
                                          TheophanySwitch { id: checkUpdatesSwitch; checked: root.currentCheckForUpdatesOnStartup }
                                          Label { text: "Check for updates on startup"; color: Theme.text }
                                      }
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: defaultIgnoreOnDeleteSwitch; checked: root.currentDefaultIgnoreOnDelete }
                                         Label { text: "Default to ignore on delete"; color: Theme.text }
                                     }
                                 }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 Label { text: "Tray Integration"; color: Theme.secondaryText; font.bold: true }
                                 ColumnLayout {
                                     spacing: 15
                                     Layout.fillWidth: true
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: traySwitch; checked: root.currentShowTrayIcon }
                                         Label { text: "Show tray icon"; color: Theme.text }
                                     }
                                 RowLayout {
                                         spacing: 15
                                         enabled: traySwitch.checked
                                         opacity: traySwitch.checked ? 1.0 : 0.4
                                         TheophanySwitch { id: closeToTraySwitch; checked: root.currentCloseToTray }
                                         Label { text: "Close to tray"; color: Theme.text }
                                     }
                                 }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 Label { text: "External Tools"; color: Theme.secondaryText; font.bold: true }
                                 ColumnLayout {
                                     spacing: 15
                                     Layout.fillWidth: true
                                     RowLayout {
                                         spacing: 15
                                         TheophanySwitch { id: customYtdlpSwitch; checked: root.currentUseCustomYtdlp }
                                         Label { text: "Use custom yt-dlp binary"; color: Theme.text }
                                     }
                                     RowLayout {
                                         spacing: 10
                                         Layout.fillWidth: true
                                         enabled: customYtdlpSwitch.checked
                                         opacity: customYtdlpSwitch.checked ? 1.0 : 0.4
                                         Label { text: "Path:"; color: Theme.text }
                                         TheophanyTextField {
                                             id: ytdlpPathField
                                             Layout.fillWidth: true
                                             text: root.currentCustomYtdlpPath
                                             placeholderText: "/usr/bin/yt-dlp"
                                             onTextChanged: root.checkYtdlp()
                                         }
                                          TheophanyButton {
                                              text: "Check"
                                              Layout.preferredHeight: 36
                                              onClicked: root.checkYtdlp()
                                          }
                                      }

                                      RowLayout {
                                          spacing: 10
                                          Layout.leftMargin: 55
                                          Label {
                                              text: "Status: " + root.ytdlpStatus
                                              color: root.ytdlpFound ? Theme.accent : "#ff5555"
                                              font.bold: true
                                              font.pixelSize: 12
                                              Layout.fillWidth: true
                                          }
                                          TheophanyButton {
                                              text: "Install yt-dlp & ejs"
                                              visible: !customYtdlpSwitch.checked
                                              Layout.preferredHeight: 32
                                              onClicked: {
                                                  root.ytdlpStatus = "Starting download..."
                                                  appInfoPollTimer.start()
                                                  appInfo.downloadYtdlp()
                                              }
                                          }
                                      }

                                      Item { Layout.preferredHeight: 10 }

                                      RowLayout {
                                          spacing: 15
                                          TheophanySwitch { id: customLegendarySwitch; checked: root.currentUseCustomLegendary }
                                          Label { text: "Use custom Legendary binary"; color: Theme.text }
                                      }
                                      RowLayout {
                                          spacing: 10
                                          Layout.fillWidth: true
                                          enabled: customLegendarySwitch.checked
                                          opacity: customLegendarySwitch.checked ? 1.0 : 0.4
                                          Label { text: "Path:"; color: Theme.text }
                                          TheophanyTextField {
                                              id: legendaryPathField
                                              Layout.fillWidth: true
                                              text: root.currentCustomLegendaryPath
                                              placeholderText: "/usr/bin/legendary"
                                              onTextChanged: root.checkLegendary()
                                          }
                                          TheophanyButton {
                                              text: "Check"
                                              Layout.preferredHeight: 36
                                              onClicked: root.checkLegendary()
                                          }
                                      }
                                      RowLayout {
                                          spacing: 10
                                          Layout.leftMargin: 55
                                          Label {
                                              text: "Status: " + root.legendaryStatus
                                              color: root.legendaryFound ? Theme.accent : "#ff5555"
                                              font.bold: true
                                              font.pixelSize: 12
                                              Layout.fillWidth: true
                                          }
                                          TheophanyButton {
                                              text: "Download Latest"
                                              visible: !customLegendarySwitch.checked
                                              Layout.preferredHeight: 32
                                              onClicked: {
                                                  root.legendaryStatus = "Downloading..."
                                                  appInfoPollTimer.start()
                                                  appInfo.downloadLegendary()
                                              }
                                          }
                                      }

                                      Item { Layout.preferredHeight: 15 }

                                      Label { text: "EOS Overlay (Experimental)"; color: Theme.secondaryText; font.bold: true; font.pixelSize: 13 }
                                      Label {
                                          text: "Epic Online Services overlay provides friends lists, achievements, and cross-play features."
                                          color: Theme.secondaryText
                                          font.pixelSize: 12
                                          wrapMode: Text.WordWrap
                                          Layout.fillWidth: true
                                      }
                                      ColumnLayout {
                                          spacing: 10
                                          Layout.leftMargin: 20
                                          Layout.fillWidth: true

                                          Label {
                                              text: root.eosOverlayInfo
                                              color: Theme.text
                                              font.family: "Monospace"
                                              font.pixelSize: 11
                                              wrapMode: Text.WordWrap
                                              Layout.fillWidth: true
                                          }

                                          RowLayout {
                                              spacing: 10
                                              TheophanyButton {
                                                  text: "Install Overlay"
                                                  enabled: root.legendaryFound && root.eosOverlayInfo.indexOf("Installed version:") === -1 && root.eosOverlayInfo !== "Checking..."
                                                  onClicked: {
                                                      root.eosOverlayStatus = "Installing..."
                                                      appInfoPollTimer.start()
                                                      appInfo.installEosOverlay()
                                                  }
                                              }
                                              TheophanyButton {
                                                  text: "Update"
                                                  enabled: root.legendaryFound && root.eosOverlayInfo.indexOf("Installed version:") !== -1 && root.eosOverlayInfo !== "Checking..."
                                                  onClicked: {
                                                      root.eosOverlayStatus = "Updating..."
                                                      appInfoPollTimer.start()
                                                      appInfo.updateEosOverlay()
                                                  }
                                              }
                                              TheophanyButton {
                                                  text: "Remove"
                                                  enabled: root.legendaryFound && root.eosOverlayInfo.indexOf("Installed version:") !== -1 && root.eosOverlayInfo !== "Checking..."
                                                  onClicked: {
                                                      appInfoPollTimer.start()
                                                      if (appInfo.removeEosOverlay()) {
                                                          root.checkEosOverlay()
                                                      }
                                                  }
                                              }
                                          }
                                          Label {
                                              text: root.eosOverlayStatus
                                              visible: text !== ""
                                              color: Theme.accent
                                              font.bold: true
                                              font.pixelSize: 12
                                          }
                                      }
                                  }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 Label { text: "Epic Games Defaults"; color: Theme.secondaryText; font.bold: true }
                                 RowLayout {
                                     spacing: 12
                                     Layout.fillWidth: true
                                     Label { text: "Default Install Location:"; color: Theme.text; Layout.preferredWidth: 160 }
                                     TheophanyTextField {
                                         id: defaultInstallLocationField
                                         Layout.fillWidth: true
                                         text: root.currentDefaultInstallLocation
                                         placeholderText: "~/Games"
                                     }
                                     TheophanyButton {
                                         text: "📁"
                                         Layout.preferredWidth: 36
                                         onClicked: defaultInstallLocationDialog.open()
                                     }
                                 }

                                 Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                                 Label { text: "Proton Defaults (New PC Collections)"; color: Theme.secondaryText; font.bold: true }
                                 ColumnLayout {
                                     spacing: 20
                                     Layout.fillWidth: true
                                     RowLayout {
                                         spacing: 10
                                         Layout.fillWidth: true
                                         Label { text: "Default Runner:"; color: Theme.text; Layout.preferredWidth: 120 }
                                         TheophanyComboBox {
                                             id: protonDefaultCombo
                                             Layout.fillWidth: true
                                             model: protonVersionsModel
                                             textRole: "name"
                                             valueRole: "path"
                                         }
                                     }
                                     RowLayout {
                                         spacing: 10
                                         Layout.fillWidth: true
                                         Label { text: "Default Prefix:"; color: Theme.text; Layout.preferredWidth: 120 }
                                         TheophanyTextField {
                                             id: protonPrefixField
                                             Layout.fillWidth: true
                                             text: root.currentDefaultProtonPrefix
                                             placeholderText: "/path/to/prefix (optional)"
                                         }
                                         TheophanyButton {
                                             text: "📁"
                                             Layout.preferredWidth: 36
                                             onClicked: protonPrefixDialog.open()
                                         }
                                     }
                                     RowLayout {
                                         spacing: 10
                                         Layout.fillWidth: true
                                         Label { text: "Default Wrapper:"; color: Theme.text; Layout.preferredWidth: 120 }
                                         TheophanyTextField {
                                             id: protonWrapperField
                                             Layout.fillWidth: true
                                             text: root.currentDefaultProtonWrapper
                                             placeholderText: "e.g. firejail"
                                         }
                                     }
                                      RowLayout { // Gamescope Toggle
                                          spacing: 12
                                          Layout.fillWidth: true
                                          Label { text: "Use Gamescope:"; color: Theme.text; Layout.preferredWidth: 120 }
                                          TheophanySwitch {
                                              id: protonUseGamescopeSwitch
                                              checked: root.currentDefaultProtonUseGamescope
                                          }
                                      }

                                      GridLayout {
                                          columns: 4
                                          rowSpacing: 15
                                          columnSpacing: 20
                                          visible: protonUseGamescopeSwitch.checked
                                          Layout.leftMargin: 20
                                          Layout.topMargin: 5
                                          Layout.bottomMargin: 5
                                          Layout.fillWidth: true

                                          Label { text: "Width"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyTextField { id: gsWidthField; text: root.currentDefaultProtonGamescopeW; Layout.fillWidth: true; placeholderText: "1920" }
                                          Label { text: "Height"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyTextField { id: gsHeightField; text: root.currentDefaultProtonGamescopeH; Layout.fillWidth: true; placeholderText: "1080" }

                                          Label { text: "Output W"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyTextField { id: gsOutWidthField; text: root.currentDefaultProtonGamescopeOutW; Layout.fillWidth: true; placeholderText: "3840" }
                                          Label { text: "Output H"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyTextField { id: gsOutHeightField; text: root.currentDefaultProtonGamescopeOutH; Layout.fillWidth: true; placeholderText: "2160" }

                                          Label { text: "Refresh"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyTextField { id: gsRefreshField; text: root.currentDefaultProtonGamescopeRefresh; Layout.fillWidth: true; placeholderText: "60" }

                                          Label { text: "Scaling"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyComboBox {
                                              id: gsScalingCombo
                                              Layout.fillWidth: true
                                              model: ["Auto", "Integer", "Fit", "Fill", "Stretch"]
                                              currentIndex: root.currentDefaultProtonGamescopeScaling
                                          }

                                          Label { text: "Upscaler"; color: Theme.secondaryText; font.pixelSize: 11; Layout.fillWidth: true }
                                          TheophanyComboBox {
                                              id: gsUpscalerCombo
                                              Layout.fillWidth: true
                                              model: ["None", "FSR", "NIS", "Pixel"]
                                              currentIndex: root.currentDefaultProtonGamescopeUpscaler
                                          }

                                          RowLayout {
                                              Layout.columnSpan: 2
                                              spacing: 10
                                              TheophanyCheckBox {
                                                  id: gsFullscreenCheck
                                                  text: "Fullscreen"
                                                  checked: root.currentDefaultProtonGamescopeFullscreen
                                              }
                                          }
                                      }

                                      RowLayout { // MangoHud Toggle
                                          spacing: 12
                                          Layout.fillWidth: true
                                          Label { text: "Use MangoHud:"; color: Theme.text; Layout.preferredWidth: 120 }
                                          TheophanySwitch {
                                              id: protonUseMangohudSwitch
                                              checked: root.currentDefaultProtonUseMangohud
                                          }
                                      }

                                      RowLayout { // Extra Args
                                          spacing: 12
                                          Layout.fillWidth: true
                                          visible: protonUseGamescopeSwitch.checked
                                          Label { text: "Extra Args:"; color: Theme.text; Layout.preferredWidth: 120 }
                                          TheophanyTextField {
                                              id: protonGamescopeArgsField
                                              Layout.fillWidth: true
                                              text: root.currentDefaultProtonGamescopeArgs
                                              placeholderText: "e.g. --adaptive-sync"
                                          }
                                      }
                                  }
                              }
                         }

                         // ABOUT TAB
                        Item {
                             implicitHeight: aboutLayout.height + 100
                             ColumnLayout {
                                 id: aboutLayout
                                 anchors.top: parent.top
                                 anchors.topMargin: 20
                                 anchors.horizontalCenter: parent.horizontalCenter
                                 width: parent.width * 0.9
                                 spacing: 40

                                 // Header: Logo, Title, Version
                                 ColumnLayout {
                                     Layout.fillWidth: true
                                     Layout.alignment: Qt.AlignHCenter
                                     spacing: 20

                                     Image {
                                         source: "qrc:/ui/assets/logo.png"
                                         Layout.preferredWidth: 100
                                         Layout.preferredHeight: 100
                                         Layout.alignment: Qt.AlignHCenter
                                         fillMode: Image.PreserveAspectFit
                                     }

                                     ColumnLayout {
                                         spacing: 4
                                         Layout.alignment: Qt.AlignHCenter

                                         Label {
                                             text: "Theophany"
                                             color: Theme.text
                                             font.pixelSize: 32
                                             font.bold: true
                                             Layout.alignment: Qt.AlignHCenter
                                         }

                                          Label {
                                              text: "v" + rootAppInfo.getVersion() + "-beta"
                                              color: Theme.secondaryText
                                              font.pixelSize: 14
                                              Layout.alignment: Qt.AlignHCenter
                                          }
                                     }
                                 }

                                 // Description
                                 Label {
                                     text: "A modern, high-performance game library manager and launcher built with Rust and QML."
                                     color: Theme.text
                                     font.pixelSize: 16
                                     horizontalAlignment: Text.AlignHCenter
                                     wrapMode: Text.WordWrap
                                     Layout.fillWidth: true
                                     Layout.alignment: Qt.AlignHCenter
                                     Layout.maximumWidth: 450
                                     lineHeight: 1.2
                                 }

                                 // Links Section
                                 RowLayout {
                                     Layout.fillWidth: true
                                     Layout.alignment: Qt.AlignHCenter
                                     spacing: 25

                                     TheophanyButton {
                                         text: "🌐 theophany.gg"
                                         onClicked: Qt.openUrlExternally("https://theophany.gg")
                                     }

                                     TheophanyButton {
                                         text: "🐙 GitHub"
                                         onClicked: Qt.openUrlExternally("https://github.com/oldlamps/theophany")
                                     }
                                 }

                                 Rectangle {
                                     height: 1
                                     Layout.fillWidth: true
                                     color: Theme.border
                                     opacity: 0.2
                                     Layout.preferredWidth: 400
                                     Layout.alignment: Qt.AlignHCenter
                                 }

                                 // Author Section
                                 ColumnLayout {
                                     Layout.fillWidth: true
                                     Layout.alignment: Qt.AlignHCenter
                                     spacing: 8

                                     Label {
                                         text: "Author"
                                         color: Theme.secondaryText
                                         font.pixelSize: 12
                                         font.bold: true
                                         Layout.alignment: Qt.AlignHCenter
                                     }

                                     Label {
                                         text: "Oldlamps"
                                         color: Theme.accent
                                         font.pixelSize: 22
                                         font.bold: true
                                         Layout.alignment: Qt.AlignHCenter
                                     }
                                 }

                                 // Support Section
                                 ColumnLayout {
                                     Layout.fillWidth: true
                                     Layout.alignment: Qt.AlignHCenter
                                     spacing: 15

                                     Label {
                                         text: "Help Support Development"
                                         color: Theme.secondaryText
                                         font.pixelSize: 13
                                         font.bold: true
                                         Layout.alignment: Qt.AlignHCenter
                                     }

                                     RowLayout {
                                         Layout.alignment: Qt.AlignHCenter
                                         spacing: 15

                                         TheophanyButton {
                                             text: "❤️ Ko-fi"
                                             onClicked: Qt.openUrlExternally("https://ko-fi.com/oldlamps")
                                         }
                                     }
                                 }

                                 Item { Layout.fillHeight: true }
                             }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    color: Theme.background
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 15
                        Item { Layout.fillWidth: true }
                        TheophanyButton { text: "Cancel"; onClicked: root.reject() }
                        TheophanyButton {
                            text: "Save Changes"
                            primary: true
                            Layout.preferredWidth: 150
                            onClicked: {
                                var mode = gridBtn.checked ? 0 : 1
                                settingsApplied(
                                    mode,
                                    filterSwitch.checked,
                                    regionBox.currentText,
                                    themeBox.currentText,
                                    raUserField.text,
                                    raKeyField.text,
                                    root.tempRaEnabled,
                                    traySwitch.checked,
                                    closeToTraySwitch.checked,
                                    aiOnBtn.checked,
                                    ollamaUrlField.text,
                                    ollamaModelBox.currentText,
                                    preferVideoSwitch.checked,
                                    ignoreTheInSortSwitch.checked,
                                    descPromptArea.text,
                                    defaultIgnoreOnDeleteSwitch.checked,
                                    metaScraperBox.currentText,
                                    imgScraperBox.currentText,
                                    geminiKeyField.text,
                                    openaiKeyField.text,
                                    llmProviderBox.currentText,
                                    saveHeroicLocallySwitch.checked,
                                    autoRescanSwitch.checked,
                                    confirmQuitSwitch.checked,
                                    gridScaleSlider.value,
                                    customYtdlpSwitch.checked,
                                    ytdlpPathField.text,
                                    protonDefaultCombo.currentValue,
                                    protonPrefixField.text,
                                    protonWrapperField.text,
                                    protonUseGamescopeSwitch.checked,
                                    protonUseMangohudSwitch.checked,
                                    protonGamescopeArgsField.text,
                                    gsWidthField.text,
                                    gsHeightField.text,
                                    gsOutWidthField.text,
                                    gsOutHeightField.text,
                                    gsRefreshField.text,
                                    gsScalingCombo.currentIndex,
                                    gsUpscalerCombo.currentIndex,
                                    gsFullscreenCheck.checked,
                                    hidePlatformsSidebarSwitch.checked,
                                    checkUpdatesSwitch.checked,
                                    customLegendarySwitch.checked,
                                    legendaryPathField.text,
                                    defaultInstallLocationField.text
                                )
                                root.accept()
                            }
                        }
                    }
                }
            }
        }
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
            } catch(e) { /* empty */ }
        }
    }

    FolderDialog {
        id: protonPrefixDialog
        title: "Select Wine Prefix Folder"
        onAccepted: protonPrefixField.text = selectedFolder.toString().replace("file://", "")
    }

    FolderDialog {
        id: defaultInstallLocationDialog
        title: "Select Default Install Location"
        onAccepted: defaultInstallLocationField.text = selectedFolder.toString().replace("file://", "")
    }
}

