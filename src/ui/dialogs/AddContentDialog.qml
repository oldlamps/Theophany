import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Theophany.Bridge 1.0
import "../style"
import "../components"

Dialog {
    id: root
    title: "Import Content into Library"
    modal: true
    width: Overlay.overlay ? Math.min(Overlay.overlay.width * 0.85, 850) : 850
    height: Overlay.overlay ? Math.min(Overlay.overlay.height * 0.9, 750) : 700
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null

    property bool isFolderMode: true
    property var platformModel: null
    property var emulatorModel: null

    property alias newCollectionName: newNameField.text
    property alias isNewMode: newRadio.checked
    property alias existingCollectionIndex: existingCombo.currentIndex
    property string droppedPath: ""
    onDroppedPathChanged: {
        if (droppedPath !== "") {
            if (isFolderMode) {
                storeBridge.analyze_folder(droppedPath)
            } else {
                checkAutoSelectPlatform(droppedPath)
            }
        }
    }

    Connections {
        target: storeBridge
        function onFolderAnalyzed(json) {
            if (!root.isFolderMode) return
            try {
                var data = JSON.parse(json)
                if (data.extensions) extField.text = data.extensions
                
                if (data.platform_type && data.platform_type !== "") {
                    // 1. Try to find existing collection of this type
                    var foundIdx = -1
                    if (platformModel) {
                        for (var i = 0; i < platformModel.rowCount(); i++) {
                            var mIdx = platformModel.index(i, 0)
                            var pType = platformModel.data(mIdx, 261)
                            if (pType === data.platform_type) {
                                foundIdx = i
                                break
                            }
                        }
                    }

                    if (foundIdx !== -1) {
                        existingRadio.checked = true
                        existingCombo.currentIndex = foundIdx
                    } else {
                        newRadio.checked = true
                        newNameField.text = data.collection_name
                        
                        // Find platform type in combo
                        for (var j = 0; j < platformTypeCombo.model.length; j++) {
                            if (platformTypeCombo.model[j].value === data.platform_type || platformTypeCombo.model[j].text === data.platform_type) {
                                platformTypeCombo.currentIndex = j
                                break
                            }
                        }
                    }
                } else if (data.collection_name) {
                    if (newNameField.text === "") newNameField.text = data.collection_name
                }
            } catch(e) { }
        }
    }

    function checkAutoSelectPlatform(path) {
        var lowerPath = path.toLowerCase()
        if (lowerPath.endsWith(".exe")) {
            root.isFolderMode = false
            
            // 1. Try to find existing "PC (Windows)" collection
            var foundIdx = -1
            if (platformModel) {
                for (var i = 0; i < platformModel.rowCount(); i++) {
                    var mIdx = platformModel.index(i, 0)
                    var pType = platformModel.data(mIdx, 261) // Role 261 is platformType
                    if (pType === "windows" || pType === "PC (Windows)") {
                        foundIdx = i
                        break
                    }
                }
            }

            if (foundIdx !== -1) {
                existingRadio.checked = true
                existingCombo.currentIndex = foundIdx
            } else {
                newRadio.checked = true
                newNameField.text = "Windows"
                // Find "PC (Windows)" in platformTypeCombo
                for (var j = 0; j < platformTypeCombo.model.length; j++) {
                    if (platformTypeCombo.model[j].text === "PC (Windows)") {
                        platformTypeCombo.currentIndex = j
                        break
                    }
                }
            }
        }
    }

    ButtonGroup { id: targetGroup }

    signal folderSelected(string path, string platformId, string name, string exts, string emuId, string pType, string icon, string cmd, bool recursive)
    signal fileSelected(string path, string platformId, string name, string exts, string emuId, string pType, string icon, string cmd)

    onClosed: {
        droppedPath = ""
        newNameField.text = ""
        existingRadio.checked = true
        existingCombo.currentIndex = 0
        extField.text = ""
        platformTypeCombo.currentIndex = 0
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    StoreBridge {
        id: storeBridge
    }

    Timer {
        interval: 500
        running: root.visible
        repeat: true
        onTriggered: storeBridge.poll()
    }

    contentItem: Item {
        implicitHeight: mainCol.implicitHeight + 40
        
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 15
            spacing: 12

            Text {
                text: root.title
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
                Layout.topMargin: 5
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.bottomMargin: 5 }

            // Steam / Local Apps / Store Quick Links
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Layout.topMargin: 5

                Label { 
                    text: "Quick Import"
                    color: Theme.accent
                    font.pixelSize: 12
                    font.bold: true 
                }

                RowLayout {
                    spacing: 10
                    Layout.fillWidth: true

                    TheophanyButton {
                        text: "Import from Steam"
                        iconSource: "assets/systems/steam.png"
                        Layout.fillWidth: true
                        onClicked: {
                            root.close()
                            steamImportDialog.openImport()
                        }
                    }

                    TheophanyButton {
                        text: "Import from Heroic"
                        iconSource: "assets/systems/heroic.png"
                        Layout.fillWidth: true
                        onClicked: {
                            root.close()
                            heroicImportDialog.openImport()
                        }
                    }
                }

                RowLayout {
                    spacing: 10
                    Layout.fillWidth: true

                    TheophanyButton {
                        text: "Import from Lutris"
                        iconSource: "assets/systems/lutris.png"
                        Layout.fillWidth: true
                        onClicked: {
                            root.close()
                            lutrisImportDialog.openImport()
                        }
                    }

                    TheophanyButton {
                        text: "Import Local Apps"
                        iconEmoji: "📂"
                        Layout.fillWidth: true
                        onClicked: {
                            root.close()
                            localAppImportDialog.openImport()
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: 5; Layout.bottomMargin: 5 }

            ScrollView {
                id: scrollView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: scrollView.availableWidth
                    spacing: 15

                    // Mode Selector: Scan vs Single File
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        
                        Label { 
                            text: "Import Mode"
                            color: Theme.accent
                            font.pixelSize: 12
                            font.bold: true 
                        }

                        RowLayout {
                            spacing: 10
                            
                            Repeater {
                                model: ["Folder Scan", "Single File"]
                                delegate: Rectangle {
                                    Layout.preferredWidth: 120
                                    Layout.preferredHeight: 32
                                    radius: 16
                                    color: (root.isFolderMode && index === 0) || (!root.isFolderMode && index === 1) ? Theme.accent : (modeMouse.containsMouse ? Theme.hover : "transparent")
                                    border.color: (root.isFolderMode && index === 0) || (!root.isFolderMode && index === 1) ? "transparent" : Theme.border
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: Theme.text
                                        font.bold: (root.isFolderMode && index === 0) || (!root.isFolderMode && index === 1)
                                    }
                                    
                                    MouseArea {
                                        id: modeMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: root.isFolderMode = (index === 0)
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // Dropped Path Display
                    ColumnLayout {
                        visible: root.droppedPath !== ""
                        spacing: 8
                        Layout.fillWidth: true
                        
                        Label {
                            text: "Target Path"
                            color: Theme.accent
                            font.pixelSize: 12
                            font.bold: true
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: Theme.background
                            border.color: Theme.border
                            radius: 6
                            
                            Label {
                                anchors.fill: parent
                                anchors.margins: 10
                                text: root.droppedPath
                                color: Theme.text
                                elide: Text.ElideMiddle
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13
                            }
                            
                            TheophanyButton {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 5
                                text: "✕"
                                flat: true
                                onClicked: root.droppedPath = ""
                            }
                        }
                    }

                    // Mode Selection: Existing vs New
                    ColumnLayout {
                        spacing: 8
                        Layout.fillWidth: true

                        Label { 
                            text: "Target Collection"
                            color: Theme.accent
                            font.pixelSize: 12
                            font.bold: true 
                        }
                        
                        RowLayout {
                            spacing: 30
                            Layout.bottomMargin: -5
                            RadioButton {
                                id: existingRadio
                                text: "Existing Collection"
                                checked: true
                                ButtonGroup.group: targetGroup
                                palette.windowText: Theme.text
                                indicator: Rectangle {
                                    implicitWidth: 18; implicitHeight: 18
                                    x: existingRadio.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 9
                                    border.color: existingRadio.checked ? Theme.accent : Theme.secondaryText
                                    color: "transparent"
                                    Rectangle {
                                        width: 10; height: 10; x: 4; y: 4
                                        radius: 5
                                        color: Theme.accent
                                        visible: existingRadio.checked
                                    }
                                }
                            }
                            RadioButton {
                                id: newRadio
                                text: "Create New Collection"
                                ButtonGroup.group: targetGroup
                                palette.windowText: Theme.text
                                indicator: Rectangle {
                                    implicitWidth: 18; implicitHeight: 18
                                    x: newRadio.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 9
                                    border.color: newRadio.checked ? Theme.accent : Theme.secondaryText
                                    color: "transparent"
                                    Rectangle {
                                        width: 10; height: 10; x: 4; y: 4
                                        radius: 5
                                        color: Theme.accent
                                        visible: newRadio.checked
                                    }
                                }
                            }
                        }

                        StackLayout {
                            Layout.fillWidth: true
                            currentIndex: existingRadio.checked ? 0 : 1
                            
                            // Existing Collection
                            ColumnLayout {
                                spacing: 8
                                Layout.fillWidth: true
                                TheophanyComboBox {
                                    id: existingCombo
                                    Layout.fillWidth: true
                                    model: platformModel
                                    textRole: "platformName"
                                    valueRole: "platformId"
                                    onCurrentIndexChanged: {
                                        if (currentIndex >= 0 && platformModel) {
                                            var modelIdx = platformModel.index(currentIndex, 0)
                                            extField.text = platformModel.data(modelIdx, 258)
                                        }
                                    }
                                    Component.onCompleted: {
                                        if (currentIndex >= 0 && platformModel) {
                                            var modelIdx = platformModel.index(currentIndex, 0)
                                            extField.text = platformModel.data(modelIdx, 258)
                                        }
                                    }
                                }
                                Text {
                                    text: "Select a collection to add the content to."
                                    color: Theme.secondaryText
                                    font.pixelSize: 11
                                    visible: existingRadio.checked
                                }
                            }

                            // New Collection
                            ColumnLayout {
                                spacing: 10
                                Layout.fillWidth: true
                                TheophanyTextField {
                                    id: newNameField
                                    Layout.fillWidth: true
                                    placeholderText: "Collection Name (e.g. SNES)"
                                }
                                ColumnLayout {
                                    spacing: 5
                                    Label { text: "Platform Type"; color: Theme.secondaryText; font.pixelSize: 11 }
                                    TheophanyComboBox {
                                        id: platformTypeCombo
                                        Layout.fillWidth: true
                                        textRole: "text"
                                        valueRole: "value"
                                        model: {
                                            var list = []
                                            try {
                                                var data = JSON.parse(appSettings.defaultPlatformsJson)
                                                for(var i=0; i<data.length; i++) {
                                                    list.push({ text: data[i].name, value: data[i].slug, icon: data[i].icon_url })
                                                }
                                                list.sort((a,b) => a.text.localeCompare(b.text))
                                                list.push({ text: "Other", value: "Other", icon: "" })
                                            } catch(e) { /* empty */ }
                                            return list
                                        }
                                    }
                                }
                            }
                        }

                        // Shared Extensions Field
                        ColumnLayout {
                            spacing: 5
                            Layout.fillWidth: true
                            
                            Label { 
                                text: "File Extensions"
                                color: Theme.accent
                                font.pixelSize: 12
                                font.bold: true 
                                visible: root.isFolderMode
                            }
                            TheophanyTextField {
                                id: extField
                                Layout.fillWidth: true
                                placeholderText: "e.g. sfc,smc,zip (comma separated)"
                                visible: root.isFolderMode
                            }
                        }

                        // Recursive Scan Option
                        CheckBox {
                            id: recursiveCheck
                            visible: root.isFolderMode
                            text: "Recursive Scan (Include Subfolders)"
                            checked: true
                            palette.windowText: Theme.text
                            indicator: Rectangle {
                                implicitWidth: 18; implicitHeight: 18
                                x: recursiveCheck.leftPadding
                                y: parent.height / 2 - height / 2
                                radius: 3
                                border.color: recursiveCheck.checked ? Theme.accent : Theme.secondaryText
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Theme.accent
                                    visible: recursiveCheck.checked
                                    font.bold: true
                                    font.pixelSize: 14
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                Layout.topMargin: 10

                TheophanyButton {
                    text: "Cancel"
                    onClicked: root.close()
                }

                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: droppedPath !== "" ? "Import Content" : (isFolderMode ? "Select Folder..." : "Select Game File...")
                    primary: true
                    onClicked: {
                        if (droppedPath !== "") {
                            processSelection(droppedPath)
                        } else {
                            if (isFolderMode) folderDialog.open()
                            else fileDialog.open()
                        }
                    }
                }
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Select Folder to Add"
        onAccepted: {
            var path = selectedFolder.toString().replace("file://", "")
            root.isFolderMode = true
            root.droppedPath = path
        }
    }

    FileDialog {
        id: fileDialog
        title: "Select Game File to Add"
        onAccepted: {
            var path = selectedFile.toString().replace("file://", "")
            root.isFolderMode = false
            root.droppedPath = path
            // checkAutoSelectPlatform(path) // Triggered via onDroppedPathChanged
        }
    }

    function processSelection(path) {
        var pid = ""
        var name = ""
        var pType = ""
        var exts = ""
        var emuId = ""
        var icon = ""
        var cmd = ""

        if (existingRadio.checked) {
            var idx = existingCombo.currentIndex
            if (idx >= 0) {
                var modelIdx = platformModel.index(idx, 0)
                pid = platformModel.data(modelIdx, 256)
                name = platformModel.data(modelIdx, 257)
                // exts = platformModel.data(modelIdx, 258) // We'll use extField instead
                cmd = platformModel.data(modelIdx, 259)
                emuId = platformModel.data(modelIdx, 260)
                pType = platformModel.data(modelIdx, 261)
                icon = platformModel.data(modelIdx, 262)
            }
        } else {
            name = newNameField.text
            var currentIdx = platformTypeCombo.currentIndex
            if (currentIdx >= 0) {
                var item = platformTypeCombo.model[currentIdx]
                pType = item.value || ""
                var iconUrl = item.icon || ""
                if (iconUrl !== "" && platformModel) {
                    var localPath = platformModel.ensureSystemIcon(iconUrl, pType)
                    icon = (localPath !== "") ? localPath : iconUrl
                } else {
                    icon = iconUrl
                }
            }
        }

        exts = extField.text

        if (isFolderMode) {
            root.folderSelected(path, pid, name, exts, emuId, pType, icon, cmd, recursiveCheck.checked)
        } else {
            root.fileSelected(path, pid, name, exts, emuId, pType, icon, cmd)
        }
        root.close()
    }
}
