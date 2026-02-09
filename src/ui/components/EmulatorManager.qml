import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Manage Emulators"
    width: Overlay.overlay ? Overlay.overlay.width * 0.66 : 1000
    height: Overlay.overlay ? Overlay.overlay.height * 0.66 : 700
    modal: true

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    standardButtons: Dialog.NoButton
    header: null
    
    // Properties to link to backend
    AppInfo { id: appInfo }

    EmulatorListModel {
        id: emulatorModel
        Component.onCompleted: init(appInfo.getDataPath() + "/games.db")
    }

    // State properties
    property bool isEditing: profileList.currentIndex !== -1
    property bool isRetroArch: false
    property string currentCorePath: ""
    property var availableCores: []
    property var modeIndex: QtObject { property int value: 0 }

    property var presetList: []
    property var currentPresetId: "custom"
    property string recommendationText: ""
    property bool showAllPresets: false
    
    // Theme-derived colors
    property color errorBackground: Qt.rgba(1, 0.2, 0.2, 0.15)
    property color errorBorder: Qt.rgba(1, 0.2, 0.2, 0.3)
    property color errorText: "#ff5555"

    // Fetch cores on load
    Component.onCompleted: {
        refreshCores()
        refreshPresets()
    }
    
    // Refresh cores when dialog opens
    onOpened: refreshCores()

    function refreshPresets() {
        var json = emulatorModel.getSupportedPresets();
        try {
             presetList = JSON.parse(json);
        } catch(e) {

             presetList = []
        }
    }

    function refreshCores() {
        var cores = emulatorModel.getRetroArchCores();
        var list = [];
        for (var i = 0; i < cores.length; i++) {
             var path = cores[i].toString();
             var name = path.split('/').pop().replace("_libretro.so", "").replace(".so", "").replace(/_/g, " ").toUpperCase();
             list.push({text: name, value: path});
        }
        // Sort by name
        list.sort((a,b) => a.text.localeCompare(b.text));
        availableCores = list;
    }

    Connections {
        target: profileList
     function onCurrentIndexChanged() {
            if (profileList.currentIndex !== -1) {
                var idx = emulatorModel.index(profileList.currentIndex, 0)
                nameField.text = emulatorModel.data(idx, 257)
                
                // Check if RetroArch
                var isRa = emulatorModel.data(idx, 260)
                isRetroArch = isRa
                
                if (isRa) {
                     currentPresetId = "retroarch"
                     modeIndex.value = 1
                     currentCorePath = emulatorModel.data(idx, 261)
                     // Find in combo
                     for (var i=0; i<availableCores.length; i++) {
                         if (availableCores[i].value === currentCorePath) {
                             coreCombo.currentIndex = i;
                             break;
                         }
                     }
                     retroPathField.text = emulatorModel.data(idx, 258)
                     
                     var fullArgs = emulatorModel.data(idx, 259)
                     var cleanArgs = fullArgs
                         .replace(/-L "[^"]+" %ROM%/, "") 
                         .replace("-f", "")
                         .replace("--verbose", "")
                         .replace(/\s+/g, " ") 
                         .trim()
                         
                     customArgsField.text = cleanArgs
                     flagFullscreen.checked = fullArgs.includes("-f")
                     flagVerbose.checked = fullArgs.includes("--verbose")
                     
                } else {
                     modeIndex.value = 0
                     var loadedPath = String(emulatorModel.data(idx, 258))
                     pathField.text = loadedPath
                     var loadedArgs = String(emulatorModel.data(idx, 259))
                     argsField.text = loadedArgs
                     
                     var foundPreset = false
                     for (var i = 0; i < presetList.length; i++) {
                         var p = presetList[i]
                         if (p.id !== "custom" && !p.isRa) {
                             var pArgs = String(p.args)
                             var pBinary = String(p.binary)
                             
                             var argsMatch = loadedArgs.trim() === pArgs.trim()
                             var pathMatch = false
                             var pathLower = loadedPath.toLowerCase()
                             
                             if ((pBinary !== "" && pathLower.indexOf(pBinary.toLowerCase()) !== -1) ||
                                 (p.id !== "" && pathLower.indexOf(p.id.toLowerCase()) !== -1)) {
                                 pathMatch = true
                             }
                             
                             if (argsMatch || pathMatch) {
                                  currentPresetId = p.id
                                  foundPreset = true
                                  break
                             }
                         }
                     }
                     if (!foundPreset) {
                         currentPresetId = "custom"
                     }
                }
            }
        }
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12
        
        // Premium subtle glow
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: Qt.rgba(0, 0, 0, 0.25)
            radius: 20
            samples: 41
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 280
            Layout.minimumWidth: 280
            Layout.maximumWidth: 280
            Layout.fillWidth: false
            spacing: 15

            Text { 
                text: "Emulator Profiles" 
                font.bold: true 
                color: Theme.text 
                font.pixelSize: 20
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.sidebar
                border.color: Theme.border
                radius: 8
                clip: true

                ListView {
                    id: profileList
                    anchors.fill: parent
                    anchors.margins: 4
                    model: emulatorModel
                    currentIndex: -1
                    spacing: 4
                    clip: true
                    
                    delegate: Rectangle {
                        width: profileList.width - 8
                        height: 50
                        color: profileList.currentIndex === index ? Theme.accent : (profileMouse.containsMouse ? Theme.hover : "transparent")
                        radius: 8
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 15
                            spacing: 12
                            
                            // Indicator Icon (Circle) - Restored
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: model.isRetroArch ? Theme.accent : Theme.text
                                opacity: 0.8
                            }

                            Text {
                                text: profileName
                                color: Theme.text
                                font.bold: profileList.currentIndex === index
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                        
                        MouseArea {
                            id: profileMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: profileList.currentIndex = index
                            hoverEnabled: true
                        }
                    }
                    
                    ScrollBar.vertical: TheophanyScrollBar {}
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

            // "Create New" Button
            Rectangle {
                Layout.fillWidth: true
                height: 50
                radius: 8
                color: profileList.currentIndex === -1 ? Theme.accent : (importMouse.containsMouse ? Theme.hover : "transparent")
                border.color: profileList.currentIndex === -1 ? "transparent" : Theme.border
                
                Text {
                    anchors.centerIn: parent
                    text: "Create New Profile"
                    color: Theme.text
                    font.bold: profileList.currentIndex === -1
                }

                MouseArea {
                    id: importMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        profileList.currentIndex = -1
                        nameField.text = "New Emulator"
                        pathField.text = ""
                        argsField.text = "%ROM%"
                        customArgsField.text = ""
                        flagFullscreen.checked = true
                        flagVerbose.checked = false
                        currentPresetId = "custom"
                        modeIndex.value = 0 
                        isRetroArch = false
                    }
                    hoverEnabled: true
                }
            }

            TheophanyButton {
                text: "Delete Profile"
                Layout.fillWidth: true
                flat: true
                visible: isEditing
                onClicked: confirmDeleteDialog.open()
                Layout.topMargin: -5
            }
        }

        // RIGHT COLUMN: Editor
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 20
            
            RowLayout {
                Layout.fillWidth: true
                Text { 
                    text: isEditing ? "Edit Profile" : "Create Profile"
                    font.bold: true 
                    color: Theme.text 
                    font.pixelSize: 22
                    Layout.fillWidth: true
                }
                 TheophanyButton {
                    text: "✕"
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    flat: true
                    onClicked: root.close()
                }
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            
            // Editor Content in a Scrollable area
            ScrollView {
                id: editorScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                
                ColumnLayout {
                    width: editorScroll.availableWidth
                    spacing: 20

                    // Preset Selector (Multi-row Tabs)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        RowLayout {
                            spacing: 8
                            Label { text: "Choose Emulator Preset"; color: Theme.text; font.pixelSize: 16; font.bold: true }
                            
                            Rectangle {
                                width: 20; height: 20
                                radius: 10
                                color: Theme.accent
                                visible: recommendationText !== ""
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "?"
                                    color: Theme.text
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                                
                                MouseArea {
                                    id: helpMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                                
                                ToolTip {
                                    visible: helpMouse.containsMouse
                                    delay: 0
                                    contentItem: Text {
                                        text: recommendationText
                                        color: Theme.text
                                        font.pixelSize: 12
                                        textFormat: Text.RichText
                                    }
                                    background: Rectangle {
                                        color: Theme.secondaryBackground
                                        border.color: Theme.border
                                        radius: 4
                                    }
                                }
                            }
                        }
                        
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            
                            Repeater {
                                model: showAllPresets ? presetList : presetList.slice(0, 8)
                                delegate: Rectangle {
                                    id: chip
                                    height: 36
                                    width: chipLabel.implicitWidth + 30
                                    radius: 18
                                    color: currentPresetId === modelData.id ? Theme.accent : (chipMouse.containsMouse ? Theme.hover : "transparent")
                                    border.color: currentPresetId === modelData.id ? Theme.accent : Theme.border
                                    border.width: 1
                                    
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    
                                    Label {
                                        id: chipLabel
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        color: Theme.text
                                        font.bold: currentPresetId === modelData.id
                                    }

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: {
                                            var p = modelData
                                            currentPresetId = p.id
                                            recommendationText = p.recommendation || ""
                                            isRetroArch = p.isRa
                                            modeIndex.value = isRetroArch ? 1 : 0
                                            
                                            if (p.id !== "custom") {
                                                if (p.isRa) {
                                                     var raPath = emulatorModel.detectRetroArch()
                                                     if (raPath) retroPathField.text = raPath
                                                     if (!isEditing) {
                                                         if (coreCombo.currentIndex >= 0) {
                                                             nameField.text = "RetroArch (" + availableCores[coreCombo.currentIndex].text + ")"
                                                         } else {
                                                             nameField.text = "RetroArch"
                                                         }
                                                     }
                                                } else {
                                                     argsField.text = p.args
                                                     var detected = emulatorModel.detectEmulator(p.id, p.binary)
                                                     pathField.text = detected // Set detected (empty if not found)
                                                     
                                                     if (!isEditing) {
                                                         nameField.text = p.name
                                                     }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // "See More" Toggle
                            Rectangle {
                                visible: presetList.length > 8
                                height: 36
                                width: toggleLabel.implicitWidth + 30
                                radius: 18
                                color: "transparent"
                                border.color: Theme.border
                                border.width: 1

                                Behavior on width { NumberAnimation { duration: 150 } }

                                Label {
                                    id: toggleLabel
                                    anchors.centerIn: parent
                                    text: showAllPresets ? "See Less" : "See More..."
                                    color: Theme.accent
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: showAllPresets = !showAllPresets
                                    hoverEnabled: true
                                }
                            }
                        }
                    }

                    // Name Field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "Profile Name"; color: Theme.secondaryText; font.bold: true }
                        TheophanyTextField {
                            id: nameField
                            placeholderText: {
                                if (currentPresetId === "retroarch") return "e.g. Game Boy Advance"
                                for (var i = 0; i < presetList.length; i++) {
                                    if (presetList[i].id === currentPresetId) {
                                        var name = presetList[i].name
                                        if (name.indexOf('(') !== -1) {
                                            return "e.g. " + name.split('(')[1].replace(')', '').trim()
                                        }
                                        return "e.g. " + name
                                    }
                                }
                                return "e.g. Nintendo Switch"
                            }
                            Layout.fillWidth: true
                        }
                    }

                    StackLayout {
                        currentIndex: modeIndex.value
                        Layout.fillWidth: true

                        // PAGE 0: Custom
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "Executable Path"; color: Theme.secondaryText; font.bold: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                     TheophanyTextField {
                                         id: pathField
                                         Layout.fillWidth: true
                                         placeholderText: "/usr/bin/emulator"
                                     }
                                     TheophanyButton {
                                         text: "Browse"
                                         onClicked: fileDialog.open() 
                                     }
                                }
                                // Warning Label
                                Rectangle {
                                    visible: currentPresetId !== "custom" && pathField.text === "" && !isRetroArch
                                    Layout.fillWidth: true
                                    implicitHeight: warningRow.implicitHeight + 16
                                    color: errorBackground
                                    radius: 6
                                    border.color: errorBorder
                                    border.width: 1
                                    
                                    RowLayout {
                                        id: warningRow
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: 8
                                        spacing: 8
                                        Label {
                                            text: "⚠️"
                                            Layout.alignment: Qt.AlignTop
                                        }
                                        Label {
                                            text: "Emulator executable not found. Please install it or browse manually."
                                            color: errorText 
                                            font.pixelSize: 12
                                            font.bold: true
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "Launch Arguments"; color: Theme.secondaryText; font.bold: true }
                                TheophanyTextField {
                                    id: argsField
                                    Layout.fillWidth: true
                                    placeholderText: "--fullscreen %ROM%"
                                }
                                Text { 
                                    text: "Use %ROM% as a placeholder for the game file path."
                                    color: Theme.secondaryText
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // PAGE 1: RetroArch
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "Libretro Core"; color: Theme.secondaryText; font.bold: true }
                                TheophanyComboBox {
                                    id: coreCombo
                                    Layout.fillWidth: true
                                    model: availableCores
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        if (!isEditing && isRetroArch && currentIndex >= 0) {
                                            nameField.text = "RetroArch (" + availableCores[currentIndex].text + ")"
                                        }
                                    }
                                }
                                Text {
                                    text: "Detected " + availableCores.length + " cores installed on your system."
                                    color: Theme.accent
                                    font.pixelSize: 12
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "Options"; color: Theme.secondaryText; font.bold: true }
                                
                                RowLayout {
                                    TheophanyCheckBox {
                                        id: flagFullscreen
                                        text: "Fullscreen (-f)"
                                        checked: true
                                    }
                                    TheophanyCheckBox {
                                        id: flagVerbose
                                        text: "Verbose (--verbose)"
                                    }
                                }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "Custom Arguments"; color: Theme.secondaryText; font.bold: true }
                                TheophanyTextField {
                                    id: customArgsField
                                    Layout.fillWidth: true
                                    placeholderText: "--fps-show ... "
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Label { text: "RetroArch Executable (Advanced)"; color: Theme.secondaryText; font.bold: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    TheophanyTextField {
                                        id: retroPathField
                                        Layout.fillWidth: true
                                        placeholderText: "Auto-detecting..." 
                                    }
                                    TheophanyButton {
                                        text: "Auto-Detect"
                                        onClicked: {
                                            var detected = emulatorModel.detectRetroArch();
                                            if (detected) retroPathField.text = detected;
                                        }
                                    }
                                }
                                Text { 
                                    text: "Command used to launch RetroArch."
                                    color: Theme.secondaryText
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
            
            // Footer Actions
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 12
                
                TheophanyButton {
                    text: "Close"
                    flat: true
                    onClicked: root.close()
                }

                Label {
                    id: statusLabel
                    text: ""
                    color: Theme.accent
                    visible: text !== ""
                }

                TheophanyButton {
                    text: "Save Profile"
                    primary: true
                    onClicked: saveProfile()
                }
            }
        }
    }
    
    function saveProfile() {
        var name = nameField.text
        var path = ""
        var args = ""
        var core = ""
        var isRa = isRetroArch
        
        if (isRa) {
            // RetroArch Logic
            path = retroPathField.text
            if (path === "") path = emulatorModel.detectRetroArch() // Fallback
            
            // Get selected core path
            if (coreCombo.currentIndex >= 0 && coreCombo.currentIndex < availableCores.length) {
                core = availableCores[coreCombo.currentIndex].value
            }
            
            // Construct arguments
            args = "-L \"" + core + "\" %ROM%"
            if (flagFullscreen.checked) args += " -f"
            if (flagVerbose.checked) args += " --verbose"
            if (customArgsField.text !== "") args += " " + customArgsField.text
            
        } else {
            // Custom Logic
            path = pathField.text
            args = argsField.text
        }
        
        if (name === "") {
            statusLabel.text = "Name is required!"
            return
        }
        
        if (profileList.currentIndex !== -1) {
             var id = emulatorModel.data(emulatorModel.index(profileList.currentIndex, 0), 256)
             emulatorModel.updateProfile(id, name, path, args, isRa, core)
        } else {
             emulatorModel.addProfile(name, path, args, isRa, core)
        }
        statusLabel.text = "Saved!"
        statusTimer.restart()
    }

    Timer {
        id: statusTimer
        interval: 3000
        onTriggered: statusLabel.text = ""
    }

    FileDialog {
        id: fileDialog
        title: "Select Emulator Executable"
        onAccepted: {
            pathField.text = fileDialog.selectedFile.toString().replace("file://", "")
        }
    }

    Dialog {
        id: confirmDeleteDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 400
        padding: 25

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.border
            border.width: 1
            radius: 12
        }

        contentItem: ColumnLayout {
            spacing: 20

            Text {
                text: "Delete Profile"
                color: Theme.text
                font.pixelSize: 22
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 }

            Label {
                text: "Are you sure you want to delete this emulator profile?"
                color: Theme.text
                font.pixelSize: 15
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            
            Item { height: 10 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                
                Item { Layout.fillWidth: true }
                
                TheophanyButton {
                    text: "Cancel"
                    onClicked: confirmDeleteDialog.close()
                }

                TheophanyButton {
                    text: "Delete"
                    primary: true
                    onClicked: {
                        var id = emulatorModel.data(emulatorModel.index(profileList.currentIndex, 0), 256);
                        emulatorModel.deleteProfile(id);
                        profileList.currentIndex = -1
                        confirmDeleteDialog.close()
                    }
                }
            }
        }
    }
}
