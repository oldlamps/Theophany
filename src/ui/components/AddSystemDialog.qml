import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Theophany.Bridge 1.0
import "../style"
import "../dialogs"

Dialog {
    id: root
    title: "Configure Collections"
    modal: true
    width: Overlay.overlay ? Overlay.overlay.width * 0.75 : 1100
    height: Overlay.overlay ? Overlay.overlay.height * 0.75 : 800
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null
    
    property var platformModel: null
    property var appSettings: null
    
    // Properties
    property alias platformName: nameField.text
    property string extensions: ""
    property alias command: cmdField.text
    property int selectedIndex: -1
    property bool editMode: selectedIndex !== -1
    property string platformId: ""
    property string platformIcon: ""
    property bool creatingNewCollection: false
    

    property string pcConfig: ""

    signal systemConfigured(string name, string extensions, string romPath, string command, string emulatorId, string emulatorName, string platformType, string icon, string pcConfig)
    signal manageEmulatorsRequested()
    signal openImportRequested(string name, string platformId)
    signal platformAdded(string platformId)
    signal platformDeleted(string platformId)
    signal deleteCollectionRequested(string platformId, string platformName)

    AppInfo { id: appInfo }
    property string dbPath: appInfo.getDataPath() + "/games.db"
    property bool advancedCollapsed: true

    property int currentCategory: 0 // 0: Emulation, 1: PC (Linux), 2: PC (Windows)

    Connections {
        target: root.platformModel
        
        function onIconDownloadFinished(path) {
            // Force string conversion to avoid TypeError if path is a URL object
            var pathStr = String(path);
            
            // If we are currently editing/creating and the icon field is empty or pending
            // Check if the downloaded icon matches our selected platform
            if (root.visible && (root.platformIcon === "" || root.platformIcon.startsWith("assets/systems/"))) {
                 // Simple heuristic: if the path contains our current platform slug
                 var currentSlug = platformCombo.currentValue;
                 if (currentSlug && pathStr.toLowerCase().includes(String(currentSlug).toLowerCase())) {
                     root.platformIcon = pathStr;
                 }
            }
        }
    }

    EmulatorListModel {
        id: emulatorModel
        Component.onCompleted: if (dbPath !== "") init(dbPath)
    }

    onDbPathChanged: if (dbPath !== "") {
        emulatorModel.init(dbPath)
    }

    function openAdd() {
        selectedIndex = -1
        creatingNewCollection = true // Open to name prompt by default
        resetForm()
        platformModel.refresh()
        emulatorModel.refresh()
        open()
    }

    function refreshEmulators() {
        if (emulatorModel) emulatorModel.refresh()
    }

    function openAddWithType(pType, name) {
        selectedIndex = -1
        creatingNewCollection = false // Skip name prompt, go to form
        resetForm()
        
        if (name) platformName = name
        
        // Find platform index
        var typeLower = (pType || "").toLowerCase()
        if (typeLower === "steam" || typeLower === "heroic" || typeLower === "lutris" || typeLower === "linux" || typeLower === "pc (linux)") {
            currentCategory = 1 // Native
        } else if (typeLower === "windows" || typeLower === "pc (windows)" || typeLower === "epic") {
            currentCategory = 2 // Windows/Proton
        } else {
            currentCategory = 0
        }
        
        // Refresh model to ensure full list is available
        platformCombo.model = root.getPlatformModel(0)
        
        var targetModel = platformCombo.model
        var typeIndex = -1
        for (var k = 0; k < targetModel.length; k++) {
             var val = (targetModel[k].value || "").toLowerCase()
             if (val === typeLower) {
                 typeIndex = k
                 break
             }
        }
        if (typeIndex !== -1) {
            platformCombo.currentIndex = typeIndex
            // Force apply icon/etc
            platformCombo.activated(typeIndex)
        }
        
        platformModel.refresh()
        emulatorModel.refresh()
        open()
    }

    function resetForm() {
        platformId = ""
        platformName = ""
        extensions = "" // Use placeholder
        command = ""
        platformCombo.currentIndex = 0
        emulatorCombo.currentIndex = -1
        customCmdCheck.checked = false
        platformIcon = ""
        currentCategory = 0
        pcConfig = ""
        pcStoreField.text = ""
        pcExtraField.text = ""
        pcWrapperField.text = ""
        pcGameIdField.text = ""
        pcProtonVerbField.text = ""
        pcDisableFixesCheck.checked = false
        pcNoRuntimeCheck.checked = false
        pcLogLevelCombo.currentIndex = 1 // Default (1)
        pcMangohudCheck.checked = false
        pcGamescopeCheck.checked = false
        gsWidthField.text = ""
        gsHeightField.text = ""
        gsOutWidthField.text = ""
        gsOutHeightField.text = ""
        gsRefreshField.text = ""
        gsScalingCombo.currentIndex = 0
        gsUpscalerCombo.currentIndex = 0
        gsFullscreenCheck.checked = false
        
        applyGlobalDefaults()
        nativeArgsField.text = ""
        nativeWorkDirField.text = ""
        creatingNewCollection = false
    }

    function getGamescopeArgs() {
        if (!pcGamescopeCheck.checked) return ""
        var args = []
        if (gsWidthField.text) args.push("-w", gsWidthField.text)
        if (gsHeightField.text) args.push("-h", gsHeightField.text)
        if (gsOutWidthField.text) args.push("-W", gsOutWidthField.text)
        if (gsOutHeightField.text) args.push("-H", gsOutHeightField.text)
        if (gsRefreshField.text) args.push("-r", gsRefreshField.text)
        
        if (gsScalingCombo.currentText !== "Auto") {
            args.push("-S", gsScalingCombo.currentText.toLowerCase())
        }
        if (gsUpscalerCombo.currentText !== "None") {
            args.push("-U", gsUpscalerCombo.currentText.toLowerCase())
        }
        if (gsFullscreenCheck.checked) args.push("-f")
        
        return args.join(" ")
    }

    function openEdit(id, name, ext, cmd, emuId, pType, icon, pcConf) {
        // Find in platformModel to select the right sidebar item
        for (var i = 0; i < platformModel.rowCount(); i++) {
            if (platformModel.data(platformModel.index(i, 0), 256) === id) {
                selectedIndex = i
                break
            }
        }
        
        loadSystemData(id, name, ext, cmd, emuId, pType, icon, pcConf)
        platformModel.refresh()
        emulatorModel.refresh()
        open()
    }

    function loadSystemData(id, name, ext, cmd, emuId, pType, icon, pcConf) {
        platformId = id
        platformName = name
        extensions = ext
        command = cmd
        pcConfig = pcConf || ""

        // Determine category from type
        var typeLower = (pType || "").toLowerCase()
        if (typeLower === "pc (linux)" || typeLower === "linux") {
            currentCategory = 1
        } else if (typeLower === "pc (windows)" || typeLower === "windows" || typeLower === "epic") {
            currentCategory = 2
        } else {
            currentCategory = 0
        }

        // Initialize model for search (always use full list)
        var targetModel = root.getPlatformModel(0)
        var typeIndex = -1
        for (var k = 0; k < targetModel.length; k++) {
             if (String(targetModel[k].value).toLowerCase() === typeLower) {
                 typeIndex = k
                 break
             }
        }

        if (typeIndex !== -1) {
            platformCombo.currentIndex = typeIndex
        } else {
            // Fallback for older types or slight mismatches
            if (typeLower === "windows" || typeLower === "pc (windows)") {
                platformCombo.currentIndex = 0 // PC (Windows) is first in Cat 2
            } else if (typeLower === "linux" || typeLower === "pc (linux)") {
                platformCombo.currentIndex = 0 // PC (Linux) is first in Cat 1
            } else {
                platformCombo.currentIndex = Math.max(0, platformCombo.count - 1)
            }
        }

        if (emuId && emuId !== "") {
            customCmdCheck.checked = false
            for (var i = 0; i < emulatorModel.rowCount(); i++) {
                if (emulatorModel.data(emulatorModel.index(i, 0), 256) === emuId) {
                    emulatorCombo.currentIndex = i
                    break
                }
            }
        } else {
            customCmdCheck.checked = true
            emulatorCombo.currentIndex = -1
        }
        
        root.platformIcon = icon || ""

        // Load PC Config defaults
        if (pcConfig !== "") {
            try {
                var json = JSON.parse(pcConfig)
                
                // Match Proton version by name or path
                var pVal = json.umu_proton_version || ""
                var pIndex = -1
                for (var j = 0; j < protonVersionsModel.count; j++) {
                    if (protonVersionsModel.get(j).name === pVal || protonVersionsModel.get(j).path === pVal) {
                        pIndex = j
                        break
                    }
                }
                protonCombo.currentIndex = (pIndex !== -1) ? pIndex : 0

                pcStoreField.text = json.umu_store || ""
                pcPrefixField.text = json.wine_prefix || ""
                pcExtraField.text = json.extra_args || ""
                pcWrapperField.text = json.wrapper || ""
                pcGameIdField.text = json.umu_id || ""
                pcProtonVerbField.text = json.proton_verb || ""
                pcDisableFixesCheck.checked = !!json.disable_fixes
                pcNoRuntimeCheck.checked = !!json.no_runtime
                
                var logLevel = json.log_level || "Default (1)"
                var logIdx = ["None", "Default (1)", "Debug"].indexOf(logLevel)
                pcLogLevelCombo.currentIndex = logIdx !== -1 ? logIdx : 1

                var logIdx = ["None", "Default (1)", "Debug"].indexOf(logLevel)
                pcLogLevelCombo.currentIndex = logIdx !== -1 ? logIdx : 1

                pcMangohudCheck.checked = !!json.use_mangohud
                
                // Gamescope restore
                pcGamescopeCheck.checked = !!json.use_gamescope
                if (json.gs_state) {
                    var gs = json.gs_state
                    gsWidthField.text = gs.w || ""
                    gsHeightField.text = gs.h || ""
                    gsOutWidthField.text = gs.W || ""
                    gsOutHeightField.text = gs.H || ""
                    gsRefreshField.text = gs.r || ""
                    gsScalingCombo.currentIndex = gs.S || 0
                    gsUpscalerCombo.currentIndex = gs.U || 0
                    gsFullscreenCheck.checked = !!gs.f
                }

                // Native PC restore
                nativeArgsField.text = json.extra_args || ""
                nativeWorkDirField.text = json.working_dir || ""

            } catch(e) { }
        } else {
            pcStoreField.text = ""
            pcExtraField.text = ""
            pcWrapperField.text = ""
            pcGameIdField.text = ""
            pcProtonVerbField.text = ""
            pcDisableFixesCheck.checked = false
            pcNoRuntimeCheck.checked = false
            pcLogLevelCombo.currentIndex = 1
            pcGamescopeCheck.checked = false
            gsWidthField.text = ""
            gsHeightField.text = ""
            gsOutWidthField.text = ""
            gsOutHeightField.text = ""
            gsRefreshField.text = ""
            gsScalingCombo.currentIndex = 0
            gsUpscalerCombo.currentIndex = 0
            gsFullscreenCheck.checked = false
            nativeArgsField.text = ""
            nativeWorkDirField.text = ""
            applyGlobalDefaults()
        }
    }

    function getPlatformModel(cat) {
        // We now always return the full list regardless of the category tab
        // this prevents the dropdown from "shrinking" when a PC platform is selected.
        var list = []
        try {
            var data = JSON.parse(appSettings.defaultPlatformsJson)
            for(var i=0; i<data.length; i++) {
                list.push({ text: data[i].name, value: data[i].slug, icon: data[i].icon_url })
            }
            list.sort((a,b) => a.text.localeCompare(b.text))
            
            // Add PC types if not already in JSON (old versions might not have them)
            var hasLinux = list.some(p => p.value === "PC (Linux)");
            var hasWindows = list.some(p => p.value === "PC (Windows)");
            var hasSteam = list.some(p => p.value === "steam");
            var hasHeroic = list.some(p => p.value === "heroic");
            var hasLutris = list.some(p => p.value === "lutris");
            
            if (!hasLinux) list.push({ text: "PC (Linux)", value: "PC (Linux)", icon: "assets/systems/linux.png" });
            if (!hasWindows) list.push({ text: "PC (Windows)", value: "PC (Windows)", icon: "assets/systems/windows.png" });
            if (!hasSteam) list.push({ text: "Steam", value: "steam", icon: "assets/systems/steam.png" });
            if (!hasHeroic) list.push({ text: "Heroic", value: "heroic", icon: "assets/systems/heroic.png" });
            if (!hasLutris) list.push({ text: "Lutris", value: "lutris", icon: "assets/systems/lutris.png" });
            
            list.push({ text: "Other", value: "Other", icon: "" })
        } catch(e) { }
        return list
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0

        // SIDEBAR: System List
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 280
            color: Theme.sidebar
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 15

                Text {
                    text: "Collections"
                    font.bold: true
                    color: Theme.text
                    font.pixelSize: 20
                }

                ListView {
                    id: systemList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: platformModel
                    clip: true
                    spacing: 4
                    
                    delegate: Rectangle {
                        width: systemList.width
                        height: 50
                        color: selectedIndex === index ? Theme.accent : (sysMouse.containsMouse ? Theme.hover : "transparent")
                        radius: 8
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 15
                            spacing: 12
                            
                            Rectangle {
                                width: 24; height: 24
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: {
                                        var iconLoc = platformIcon
                                        if (!iconLoc) return ""
                                        if (iconLoc.startsWith("http") || iconLoc.startsWith("file://") || iconLoc.startsWith("qrc:/") || iconLoc.startsWith("/")) {
                                            return (iconLoc.startsWith("/") ? "file://" + iconLoc : iconLoc) + "?t=" + platformModel.cache_buster
                                        }
                                        if (iconLoc.startsWith("assets/")) {
                                            return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + iconLoc + "?t=" + platformModel.cache_buster
                                        }
                                        return "file://" + iconLoc + "?t=" + platformModel.cache_buster
                                    }
                                    fillMode: Image.PreserveAspectFit
                                }
                                visible: platformIcon !== ""
                            }
                            
                            Text {
                                text: platformName
                                color: Theme.text
                                font.bold: selectedIndex === index
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: sysMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                selectedIndex = index
                                var idx = platformModel.index(index, 0)
                                loadSystemData(
                                    platformModel.data(idx, 256),
                                    platformModel.data(idx, 257),
                                    platformModel.data(idx, 258),
                                    platformModel.data(idx, 259),
                                    platformModel.data(idx, 260),
                                    platformModel.data(idx, 261),
                                    platformModel.data(idx, 262),
                                    platformModel.data(idx, 263)
                                )
                                creatingNewCollection = false
                            }
                            hoverEnabled: true
                        }
                    }
                    
                    ScrollBar.vertical: TheophanyScrollBar {}
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                // "Create New" Button
                Rectangle {
                    Layout.fillWidth: true
                    height: 50
                    radius: 8
                    color: selectedIndex === -1 ? Theme.accent : (importMouse.containsMouse ? Theme.hover : "transparent")
                    border.color: selectedIndex === -1 ? "transparent" : Theme.border
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        spacing: 12
                        Text { text: "➕"; font.pixelSize: 16; color: Theme.text }
                        Text {
                            text: "Create New Collection"
                            color: Theme.text
                            font.bold: selectedIndex === -1
                        }
                    }

                    MouseArea {
                        id: importMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            selectedIndex = -1
                            creatingNewCollection = true
                        }
                        hoverEnabled: true
                    }
                }
            }
        }

        // MAIN CONTENT AREA
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 30
            Layout.rightMargin: 30
            Layout.bottomMargin: 30
            Layout.leftMargin: 60
            spacing: 20

            StackLayout {
                id: mainStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: selectedIndex !== -1 ? 1 : 0


                // State 1: Name Prompt
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 30
                
                    ColumnLayout {
                        spacing: 15
                        Layout.alignment: Qt.AlignCenter
                    
                        Text {
                            text: "Create New Collection"
                            color: Theme.text
                            font.pixelSize: 24
                            font.bold: true
                        }
                    
                        Text {
                            text: "Give your collection a name to get started. You can configure emulators and import games afterwards."
                            color: Theme.secondaryText
                            font.pixelSize: 14
                            Layout.preferredWidth: 400
                            wrapMode: Text.WordWrap
                        }
                    
                        TheophanyTextField {
                            id: newNameField
                            placeholderText: "Collection Name (e.g. SNES, PlayStation 2)"
                            Layout.preferredWidth: 400
                            focus: creatingNewCollection && selectedIndex === -1
                            onAccepted: createBtn.onClicked()
                        }
                    
                        RowLayout {
                            spacing: 15
                            TheophanyButton {
                                text: "Create Empty Collection"
                                onClicked: {
                                    var newId = platformModel.createPlatform(newNameField.text)
                                    if (newId !== "") {
                                        root.platformAdded(newId)
                                        creatingNewCollection = false
                                        newNameField.text = ""
                                        selectNewTimer.targetId = newId
                                        selectNewTimer.start()
                                    }
                                }
                            }
                            TheophanyButton {
                                text: "Create Collection & Add Content..."
                                primary: true
                                onClicked: {
                                    root.openImportRequested(newNameField.text, "")
                                    root.close()
                                }
                            }
                        }
                    }
                }
            
                // State 2: Configuration Form
                ColumnLayout {
                    id: formLayout
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 20

                    RowLayout {
                        spacing: 15
                        Layout.fillWidth: true
                    
                        Rectangle {
                            width: 32; height: 32
                            color: "transparent"
                            visible: root.platformIcon !== ""
                            Image {
                                anchors.fill: parent
                                source: {
                                    var iconLoc = root.platformIcon
                                    if (!iconLoc) return ""
                                    if (iconLoc.startsWith("http") || iconLoc.startsWith("file://") || iconLoc.startsWith("qrc:/") || iconLoc.startsWith("/")) {
                                        return (iconLoc.startsWith("/") ? "file://" + iconLoc : iconLoc) + "?t=" + platformModel.cache_buster
                                    }
                                    if (iconLoc.startsWith("assets/")) {
                                        return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + iconLoc + "?t=" + platformModel.cache_buster
                                    }
                                    return "file://" + iconLoc + "?t=" + platformModel.cache_buster
                                }
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        Text {
                            text: platformName !== "" ? platformName : "Create New Collection"
                            font.bold: true
                            color: Theme.text
                            font.pixelSize: 24
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                    
                    // Category Tabs
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        
                        Repeater {
                            model: ["Emulation", "Native", "Windows (Proton)"]
                            delegate: Rectangle {
                                Layout.preferredWidth: 140
                                Layout.preferredHeight: 36
                                radius: 18
                                color: currentCategory === index ? Theme.accent : (tabMouse.containsMouse ? Theme.hover : "transparent")
                                border.color: currentCategory === index ? "transparent" : Theme.border
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Theme.text
                                    font.bold: currentCategory === index
                                }
                                
                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        currentCategory = index
                                        if (!editMode) {
                                            // Autopopulate platform type based on category with sensible defaults from full list
                                            var targetText = ""
                                            if (index === 1) targetText = "PC (Linux)"
                                            else if (index === 2) targetText = "PC (Windows)"
                                            else targetText = "NES" // Default for emulation

                                            for (var i = 0; i < platformCombo.model.length; i++) {
                                                if (platformCombo.model[i].text === targetText) {
                                                    platformCombo.currentIndex = i
                                                    platformCombo.activated(i)
                                                    break
                                                }
                                            }
                                        }
                                    }
                                    hoverEnabled: true
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: parent.width - 20
                            spacing: 25

                            // Section: General
                            ColumnLayout {
                                spacing: 12
                                Layout.fillWidth: true
                                Text { text: "GENERAL CONFIGURATION"; color: Theme.secondaryText; font.pixelSize: 11; font.bold: true }
                                
                                GridLayout {
                                    columns: 2
                                    rowSpacing: 15
                                    columnSpacing: 15
                                    Layout.fillWidth: true

                                    Label { text: "Collection Name"; color: Theme.text }
                                        TheophanyTextField {
                                            id: nameField
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 50
                                            placeholderText: "Collection Name"
                                        }

                                    Label { text: "Platform Type"; color: Theme.text }
                                    TheophanyComboBox {
                                        id: platformCombo
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 50
                                        model: root.getPlatformModel(0)
                                        textRole: "text"
                                        valueRole: "value"
                                        onActivated: {
                                            var item = model[index];
                                            if (root.platformIcon === "" || root.platformIcon.startsWith("assets/")) {
                                                 // Get icon data from model
                                                 var iconUrl = item.icon || "";
                                                 
                                                 if (iconUrl.startsWith("assets/") && !iconUrl.startsWith("assets/systems/")) {
                                                     // Direct local asset
                                                     root.platformIcon = iconUrl;
                                                 } else if (iconUrl !== "") {
                                                     var slug = currentText; 
                                                     // Use slug for better naming if available, otherwise text
                                                     if (item.value && item.value !== "Other") slug = item.value;

                                                     // Try to get existing local icon or trigger download
                                                     var localPath = platformModel.ensureSystemIcon(iconUrl, slug);
                                                     
                                                     if (localPath !== "") {
                                                         root.platformIcon = localPath;
                                                     }
                                                 }
                                            }

                                            // Bi-directional category switching based on platform selection
                                            var pVal = item.value || ""
                                            if (pVal === "PC (Linux)" || pVal === "steam" || pVal === "heroic" || pVal === "lutris") {
                                                currentCategory = 1;
                                            } else if (pVal === "PC (Windows)" || pVal === "epic") {
                                                currentCategory = 2;
                                            } else {
                                                currentCategory = 0;
                                            }
                                        }
                                    }

                                    Label { text: "Collection Icon"; color: Theme.text }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        TheophanyTextField {
                                            id: iconField
                                            text: root.platformIcon
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 50
                                            onTextChanged: root.platformIcon = text
                                        }
                                        TheophanyButton {
                                            text: "Browse"
                                            tooltipText: "Select Local Folder"
                                            onClicked: iconFileDialog.open()
                                        }
                                        TheophanyButton {
                                            text: "🔍"
                                            tooltipText: "Search for System Icon"
                                            onClicked: {
                                                iconSearchDialog.initialQuery = (nameField.text || "System") 
                                                iconSearchDialog.activeSystemName = platformCombo.currentValue || "system"
                                                iconSearchDialog.open()
                                            }
                                        }
                                    }

                                    TheophanyButton {
                                        text: "Import Games to this Collection..."
                                        visible: editMode
                                        Layout.fillWidth: true
                                        onClicked: root.openImportRequested(platformName, platformId)
                                    }
                                }
                            }

                            // Adaptive Sections
                            StackLayout {
                                Layout.fillWidth: true
                                currentIndex: currentCategory
                                
                                // CATEGORY 0: Emulation
                                ColumnLayout {
                                    spacing: 25
                                    
                                    // Section: Launch
                                    ColumnLayout {
                                        spacing: 12
                                        Layout.fillWidth: true
                                        Text { text: "LAUNCH CONFIGURATION"; color: Theme.secondaryText; font.pixelSize: 11; font.bold: true }
                                        
                                        ColumnLayout {
                                            spacing: 10
                                            Layout.fillWidth: true
                                            
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                TheophanyComboBox {
                                                    id: emulatorCombo
                                                    Layout.fillWidth: true
                                                    model: emulatorModel
                                                    textRole: "profileName"
                                                    valueRole: "profileId"
                                                    enabled: !customCmdCheck.checked
                                                }
                                                TheophanyButton {
                                                    text: "+"
                                                    tooltipText: "Manage Emulators"
                                                    Layout.preferredWidth: 36
                                                    onClicked: root.manageEmulatorsRequested()
                                                    visible: !customCmdCheck.checked
                                                }
                                            }
                                            
                                            CheckBox {
                                                id: customCmdCheck
                                                text: "Use Custom Launch Command"
                                                checked: false
                                                palette.windowText: Theme.text
                                                indicator: Rectangle {
                                                    implicitWidth: 18; implicitHeight: 18
                                                    x: customCmdCheck.leftPadding
                                                    y: parent.height / 2 - height / 2
                                                    radius: 3
                                                    border.color: customCmdCheck.checked ? Theme.accent : Theme.secondaryText
                                                    color: "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✓"
                                                        color: Theme.accent
                                                        visible: customCmdCheck.checked
                                                        font.bold: true
                                                        font.pixelSize: 14
                                                    }
                                                }
                                                onCheckedChanged: if (checked) emulatorCombo.currentIndex = -1
                                            }

                                            TheophanyTextField {
                                                id: cmdField
                                                visible: customCmdCheck.checked
                                                Layout.fillWidth: true
                                                placeholderText: "/usr/bin/emu %ROM%"
                                            }
                                        }
                                    }
                                }

                                // CATEGORY 1: Native
                                ColumnLayout {
                                    spacing: 25
                                    
                                    ColumnLayout {
                                        spacing: 12
                                        Layout.fillWidth: true
                                        Text { text: "NATIVE EXECUTION"; color: Theme.secondaryText; font.pixelSize: 11; font.bold: true }
                                        
                                        GridLayout {
                                            columns: 2
                                            rowSpacing: 15
                                            columnSpacing: 15
                                            Layout.fillWidth: true

                                            Label { text: "Executable Path"; color: Theme.text }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField {
                                                    id: nativeExeField
                                                    text: (currentCategory === 1 && customCmdCheck.checked) ? cmdField.text : ""
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 50
                                                    placeholderText: "/usr/bin/game-executable"
                                                    onTextChanged: if (currentCategory === 1) {
                                                        customCmdCheck.checked = true
                                                        cmdField.text = text
                                                    }
                                                }
                                                TheophanyButton {
                                                    text: "Browse"
                                                    tooltipText: "Select Native Executable"
                                                    onClicked: nativeExeFileDialog.open()
                                                }
                                            }

                                            Label { text: "Arguments"; color: Theme.text }
                                            TheophanyTextField {
                                                id: nativeArgsField
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 50
                                                placeholderText: "--fullscreen --gl"
                                            }
                                            
                                            Label { text: "Working Dir"; color: Theme.text }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField {
                                                    id: nativeWorkDirField
                                                    Layout.fillWidth: true
                                                    placeholderText: "/path/to/game/folder"
                                                }
                                                TheophanyButton {
                                                    text: "Browse"
                                                    tooltipText: "Select Working Directory"
                                                    onClicked: nativeWorkDirDialog.open()
                                                }
                                            }
                                        }
                                    }
                                }

                                // CATEGORY 2: Windows (Proton)
                                ColumnLayout {
                                    spacing: 25
                                    
                                    ColumnLayout {
                                        spacing: 12
                                        Layout.fillWidth: true
                                        Text { text: "DEFAULT PC CONFIGURATION"; color: Theme.secondaryText; font.pixelSize: 11; font.bold: true }
                                        
                                        GridLayout {
                                            columns: 2
                                            rowSpacing: 15
                                            columnSpacing: 15
                                            Layout.fillWidth: true

                                            Label { text: "Proton Version"; color: Theme.text }
                                            TheophanyComboBox {
                                                id: protonCombo
                                                Layout.fillWidth: true
                                                model: protonVersionsModel
                                                textRole: "name"
                                                valueRole: "path"
                                            }

                                            Label { text: "Wine Prefix"; color: Theme.text }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                TheophanyTextField {
                                                    id: pcPrefixField
                                                    Layout.fillWidth: true
                                                    placeholderText: "/path/to/prefix (optional)"
                                                }
                                                TheophanyButton {
                                                    text: "📁"
                                                    tooltipText: "Select Wine Prefix"
                                                    Layout.preferredWidth: 36
                                                    onClicked: pcPrefixDialog.open()
                                                }
                                            }

                                            Label { text: "Command Wrapper"; color: Theme.text }
                                            TheophanyTextField {
                                                id: pcWrapperField
                                                Layout.fillWidth: true
                                                placeholderText: "e.g. firejail --net=none"
                                            }

                                            Label { text: "Extra Arguments"; color: Theme.text }
                                            TheophanyTextField {
                                                id: pcExtraField
                                                Layout.fillWidth: true
                                                placeholderText: "e.g. -novid"
                                            }
                                        }

                                        Item { Layout.preferredHeight: 10 }

                                        // Gamescope Section
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            CheckBox {
                                                id: pcMangohudCheck
                                                text: "Enable MangoHud"
                                                palette.windowText: Theme.text
                                                font.bold: true
                                                indicator: Rectangle {
                                                    implicitWidth: 18; implicitHeight: 18
                                                    x: pcMangohudCheck.leftPadding
                                                    y: parent.height / 2 - height / 2
                                                    radius: 3
                                                    border.color: pcMangohudCheck.checked ? Theme.accent : Theme.secondaryText
                                                    color: "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✓"
                                                        color: Theme.accent
                                                        visible: pcMangohudCheck.checked
                                                        font.bold: true
                                                        font.pixelSize: 14
                                                    }
                                                }
                                            }

                                            CheckBox {
                                                id: pcGamescopeCheck
                                                text: "Enable Gamescope"
                                                palette.windowText: Theme.text
                                                font.bold: true
                                                indicator: Rectangle {
                                                    implicitWidth: 18; implicitHeight: 18
                                                    x: pcGamescopeCheck.leftPadding
                                                    y: parent.height / 2 - height / 2
                                                    radius: 3
                                                    border.color: pcGamescopeCheck.checked ? Theme.accent : Theme.secondaryText
                                                    color: "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✓"
                                                        color: Theme.accent
                                                        visible: pcGamescopeCheck.checked
                                                        font.bold: true
                                                        font.pixelSize: 14
                                                    }
                                                }
                                            }

                                            GridLayout {
                                                columns: 4
                                                rowSpacing: 10
                                                columnSpacing: 10
                                                visible: pcGamescopeCheck.checked
                                                Layout.leftMargin: 28
                                                
                                                Label { text: "Width"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyTextField { id: gsWidthField; Layout.preferredWidth: 80; placeholderText: "1920" }
                                                Label { text: "Height"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyTextField { id: gsHeightField; Layout.preferredWidth: 80; placeholderText: "1080" }

                                                Label { text: "Output W"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyTextField { id: gsOutWidthField; Layout.preferredWidth: 80; placeholderText: "3840" }
                                                Label { text: "Output H"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyTextField { id: gsOutHeightField; Layout.preferredWidth: 80; placeholderText: "2160" }

                                                Label { text: "Refresh"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyTextField { id: gsRefreshField; Layout.preferredWidth: 80; placeholderText: "60" }
                                                
                                                Label { text: "Scaling"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyComboBox {
                                                    id: gsScalingCombo
                                                    Layout.preferredWidth: 100
                                                    model: ["Auto", "Integer", "Fit", "Fill", "Stretch"]
                                                }
                                                
                                                Label { text: "Upscaler"; color: Theme.secondaryText; font.pixelSize: 11 }
                                                TheophanyComboBox {
                                                    id: gsUpscalerCombo
                                                    Layout.preferredWidth: 100
                                                    model: ["None", "FSR", "NIS", "Pixel"]
                                                }

                                                CheckBox {
                                                    id: gsFullscreenCheck
                                                    text: "Fullscreen"
                                                    palette.windowText: Theme.secondaryText
                                                    Layout.columnSpan: 2
                                                    indicator: Rectangle {
                                                        implicitWidth: 18; implicitHeight: 18
                                                        x: gsFullscreenCheck.leftPadding
                                                        y: parent.height / 2 - height / 2
                                                        radius: 3
                                                        border.color: gsFullscreenCheck.checked ? Theme.accent : Theme.secondaryText
                                                        color: "transparent"
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "✓"
                                                            color: Theme.accent
                                                            visible: gsFullscreenCheck.checked
                                                            font.bold: true
                                                            font.pixelSize: 14
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Item { Layout.preferredHeight: 10 }

                                        // Advanced Section
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "ADVANCED UMU SETTINGS"; color: Theme.secondaryText; font.pixelSize: 10; font.bold: true; Layout.fillWidth: true }
                                                Text { 
                                                    text: advancedCollapsed ? "▶\ufe0e" : "▼\ufe0e"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        onClicked: advancedCollapsed = !advancedCollapsed
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                visible: !advancedCollapsed
                                                spacing: 12

                                                GridLayout {
                                                    columns: 2
                                                    rowSpacing: 12
                                                    columnSpacing: 15
                                                    Layout.fillWidth: true

                                                    Label { text: "Store (Steam/Epic)"; color: Theme.text }
                                                    TheophanyTextField {
                                                        id: pcStoreField
                                                        Layout.fillWidth: true
                                                        placeholderText: "e.g. steam, epic"
                                                    }

                                                    Label { text: "Game ID"; color: Theme.text }
                                                    TheophanyTextField {
                                                        id: pcGameIdField
                                                        Layout.fillWidth: true
                                                        placeholderText: "umu-database ID (optional)"
                                                    }

                                                    Label { text: "Proton Verb"; color: Theme.text }
                                                    TheophanyTextField {
                                                        id: pcProtonVerbField
                                                        Layout.fillWidth: true
                                                        placeholderText: "Default: waitforexitandrun"
                                                    }

                                                    Label { text: "Log Level"; color: Theme.text }
                                                    TheophanyComboBox {
                                                        id: pcLogLevelCombo
                                                        Layout.fillWidth: true
                                                        model: ["None", "Default (1)", "Debug"]
                                                    }
                                                }

                                                RowLayout {
                                                    spacing: 20
                                                    CheckBox {
                                                        id: pcDisableFixesCheck
                                                        text: "Disable Protonfixes"
                                                        palette.windowText: Theme.text
                                                        indicator: Rectangle {
                                                            implicitWidth: 18; implicitHeight: 18
                                                            x: pcDisableFixesCheck.leftPadding
                                                            y: parent.height / 2 - height / 2
                                                            radius: 3
                                                            border.color: pcDisableFixesCheck.checked ? Theme.accent : Theme.secondaryText
                                                            color: "transparent"
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "✓"
                                                                color: Theme.accent
                                                                visible: pcDisableFixesCheck.checked
                                                                font.bold: true
                                                                font.pixelSize: 14
                                                            }
                                                        }
                                                    }
                                                    CheckBox {
                                                        id: pcNoRuntimeCheck
                                                        text: "No Steam Runtime"
                                                        palette.windowText: Theme.text
                                                        indicator: Rectangle {
                                                            implicitWidth: 18; implicitHeight: 18
                                                            x: pcNoRuntimeCheck.leftPadding
                                                            y: parent.height / 2 - height / 2
                                                            radius: 3
                                                            border.color: pcNoRuntimeCheck.checked ? Theme.accent : Theme.secondaryText
                                                            color: "transparent"
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "✓"
                                                                color: Theme.accent
                                                                visible: pcNoRuntimeCheck.checked
                                                                font.bold: true
                                                                font.pixelSize: 14
                                                            }
                                                        }
                                                    }
                                                
                                                    // Removed pcMangohudCheck from here
                                                }
                                            }
                                        }
                                    }
                                }
                            } // End of Adaptive StackLayout
                        } // End of scroll content wrapper
                    } // End of ScrollView

                    // Shared Logic
                    Timer {
                        id: selectNewTimer
                        property string targetId: ""
                        interval: 50
                        onTriggered: {
                            for (var i = 0; i < platformModel.rowCount(); i++) {
                                if (platformModel.getId(i) === targetId) {
                                    selectedIndex = i
                                    var idx = platformModel.index(i, 0)
                                    loadSystemData(
                                        platformModel.data(idx, 256),
                                        platformModel.data(idx, 257),
                                        platformModel.data(idx, 258),
                                        platformModel.data(idx, 259),
                                        platformModel.data(idx, 260),
                                        platformModel.data(idx, 261),
                                        platformModel.data(idx, 262),
                                        platformModel.data(idx, 263)
                                    )
                                    break
                                }
                            }
                        }
                    }

                    // Footer
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15
                        Layout.topMargin: 10
                        visible: mainStack.currentIndex === 1

                        TheophanyButton {
                            text: "Delete Collection"
                            visible: editMode
                            onClicked: {
                                root.deleteCollectionRequested(root.platformId, root.platformName)
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        TheophanyButton {
                            text: "Cancel"
                            onClicked: root.close()
                        }

                        TheophanyButton {
                            text: "Save Changes"
                            primary: true
                            onClicked: {
                                var emuId = ""
                                var finalCmd = ""
                                var emuName = ""
                                if (customCmdCheck.checked) {
                                    finalCmd = cmdField.text
                                    emuName = "Custom Command"
                                } else if (emulatorCombo.currentIndex !== -1) {
                                    emuId = emulatorModel.data(emulatorModel.index(emulatorCombo.currentIndex, 0), 256)
                                    emuName = emulatorCombo.currentText
                                }
                                
                                var finalPcConfig = ""
                                if (currentCategory === 1) {
                                    finalPcConfig = JSON.stringify({
                                        "extra_args": nativeArgsField.text,
                                        "working_dir": nativeWorkDirField.text
                                    })
                                } else if (currentCategory === 2) {
                                    var pcData = {
                                        "umu_proton_version": protonCombo.currentValue,
                                        "umu_store": pcStoreField.text,
                                        "wine_prefix": pcPrefixField.text,
                                        "extra_args": pcExtraField.text,
                                        "wrapper": pcWrapperField.text,
                                        "umu_id": pcGameIdField.text,
                                        "proton_verb": pcProtonVerbField.text,
                                        "disable_fixes": pcDisableFixesCheck.checked,
                                        "no_runtime": pcNoRuntimeCheck.checked,
                                        "log_level": pcLogLevelCombo.currentText,
                                        "use_gamescope": pcGamescopeCheck.checked,
                                        "use_mangohud": pcMangohudCheck.checked,
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
                                        }
                                    }
                                    finalPcConfig = JSON.stringify(pcData)
                                }

                                var finalPType = (platformCombo.currentIndex >= 0 && platformCombo.model[platformCombo.currentIndex]) ? platformCombo.model[platformCombo.currentIndex].value : "Other"
                                root.systemConfigured(nameField.text, root.extensions, "", finalCmd, emuId, emuName, finalPType, root.platformIcon, finalPcConfig)
                                
                                root.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // Dialogs


    FileDialog {
        id: iconFileDialog
        title: "Select System Icon"
        nameFilters: ["Image files (*.png *.jpg *.svg)", "All files (*)"]
        onAccepted: root.platformIcon = selectedFile.toString().replace("file://", "")
    }

    FileDialog {
        id: nativeExeFileDialog
        title: "Select Native Executable"
        onAccepted: nativeExeField.text = selectedFile.toString().replace("file://", "")
    }

    FolderDialog {
        id: nativeWorkDirDialog
        title: "Select Working Directory"
        onAccepted: nativeWorkDirField.text = selectedFolder.toString().replace("file://", "")
    }

    FileDialog {
        id: windowsExeFileDialog
        title: "Select Windows Executable"
        nameFilters: ["Executables (*.exe)", "All items (*)"]
        onAccepted: windowsExeField.text = selectedFile.toString().replace("file://", "")
    }

    Timer {
        interval: 100
        running: root.visible
        repeat: true
        onTriggered: platformModel.checkAsyncResponses()
    }

    SystemIconSearchDialog {
        id: iconSearchDialog
        platformModel: root.platformModel
        onIconSelected: (path) => {
            root.platformIcon = path
        }
    }

    ListModel { id: protonVersionsModel }
    
    function refreshProtonVersions() {
        protonVersionsModel.clear()
        protonVersionsModel.append({ "name": "Default (umu-run choice)", "path": "" })
        protonVersionsModel.append({ "name": "Auto (GE-Proton)", "path": "GE-Proton" })
        try {
            var versions = JSON.parse(platformModel.getProtonVersions())
            for (var i = 0; i < versions.length; i++) {
                protonVersionsModel.append(versions[i])
            }
        } catch(e) { }
    }
    
    function applyGlobalDefaults() {
        if (appSettings) {
             pcMangohudCheck.checked = appSettings.defaultProtonUseMangohud
             
             var defaultRunner = appSettings.defaultProtonRunner
             if (defaultRunner && defaultRunner !== "") {
                var foundIdx = -1
                for (var i = 0; i < protonVersionsModel.count; i++) {
                    if (protonVersionsModel.get(i).path === defaultRunner) {
                        foundIdx = i
                        break
                    }
                }
                protonCombo.currentIndex = foundIdx !== -1 ? foundIdx : 0
             } else {
                protonCombo.currentIndex = 0
             }

             pcPrefixField.text = appSettings.defaultProtonPrefix
             pcWrapperField.text = appSettings.defaultProtonWrapper
             pcExtraField.text = "" // Global extra args not usually desired as default for all games
             
             pcGamescopeCheck.checked = appSettings.defaultProtonUseGamescope
             gsWidthField.text = appSettings.defaultProtonGamescopeW
             gsHeightField.text = appSettings.defaultProtonGamescopeH
             gsOutWidthField.text = appSettings.defaultProtonGamescopeOutW
             gsOutHeightField.text = appSettings.defaultProtonGamescopeOutH
             gsRefreshField.text = appSettings.defaultProtonGamescopeRefresh
             gsScalingCombo.currentIndex = appSettings.defaultProtonGamescopeScaling
             gsUpscalerCombo.currentIndex = appSettings.defaultProtonGamescopeUpscaler
             gsFullscreenCheck.checked = appSettings.defaultProtonGamescopeFullscreen
             
             // UMU Specifics typically stay blank as they are game-dependent (ID/Store/Verb)
             // but we can set defaults for flags if they exist in global settings (though currently they don't seem to be in global)
        } else {
             // Fallbacks if appSettings is null for some reason
             protonCombo.currentIndex = 0
             pcPrefixField.text = ""
             pcMangohudCheck.checked = false
             pcGamescopeCheck.checked = false
        }
    }

    Component.onCompleted: refreshProtonVersions()

    FolderDialog {
        id: pcPrefixDialog
        title: "Select Wine Prefix Folder"
        onAccepted: pcPrefixField.text = selectedFolder.toString().replace("file://", "")
    }
}
