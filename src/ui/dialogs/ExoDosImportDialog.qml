import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import eXoDOS"
    modal: true
    width: Overlay.overlay ? Math.min(Overlay.overlay.width * 0.75, 850) : 800
    height: Overlay.overlay ? Math.min(Overlay.overlay.height * 0.85, 750) : 650
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null
    
    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    StoreBridge {
        id: storeBridge
        
        onExodosLibraryFinished: (resultsJson) => {
            var results = JSON.parse(resultsJson)
            rawResults = results
            results.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })

            exodosModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                exodosModel.append({
                    "gameId": item.id || "",
                    "title": item.title || "Unknown Game",
                    "path": item.path || "",
                    "filename": item.filename || "",
                    "icon_path": "",
                    "platform_id": "DOS",
                    "platform_name": "eXoDOS",
                    "tags": item.tags || "",
                    "developer": item.developer || "",
                    "publisher": item.publisher || "",
                    "genre": item.genre || "",
                    "release_date": item.release_date || "",
                    "description": item.description || "",
                    "resources": item.resources || [],
                    "is_installed": true,
                    "is_favorite": item.is_favorite === true
                })
            }
            selectAllMode = true
            manualToggles = {}
            loading = false
        }

        onInstallProgress: (appName, progress, message) => {
            if (appName === "exodos") {
                progressDialog.open()
                progressDialog.progress = progress
                progressDialog.status = message

                // Sync with global ticker
                window.backgroundActivityId = "exodos"
                window.backgroundActivityProgress = progress
                window.backgroundActivityStatus = message
                window.hasBackgroundActivity = true
            }
        }

        onInstallFinished: (appName, success, message) => {
            if (appName === "exodos") {
                if (success) {
                    progressDialog.progress = 1.0
                    progressDialog.status = "Import complete! " + message
                    gameModel.refresh()
                } else {
                    progressDialog.close()
                    errorDialog.text = "Import Result:\n" + message
                    errorDialog.open()
                }
                window.hasBackgroundActivity = false
            } else if (appName === "exodos_immediate" || appName === "exodos_batch") {
                if (success) {
                    progressDialog.status = message
                    gameModel.refresh()
                }
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: storeBridge.poll()
    }

    property bool loading: false
    property bool selectAllMode: true
    property var manualToggles: ({})
    property var rawResults: []

    ListModel { id: exodosModel }
    ListModel { id: filteredPlatforms }

    property int selectedCount: {
        var manualCount = Object.keys(manualToggles).length
        if (selectAllMode) {
            return Math.max(0, exodosModel.count - manualCount)
        } else {
            return manualCount
        }
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) return
        
        var selectedIdx = 0
        var hasDos = false

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = (sidebar.platformModel.data(idx, 261) || "").toLowerCase()
            if (type === "dos" || name.toLowerCase().indexOf("dos") !== -1) {
                if (name.toLowerCase() === "exodos") name = "eXoDOS"
                filteredPlatforms.append({
                    "name": name,
                    "id": sidebar.platformModel.data(idx, 256)
                })
                hasDos = true
            }
        }
        
        if (!hasDos) {
             filteredPlatforms.insert(0, {
                 "name": "eXoDOS (Default)",
                 "id": "virtual_dos"
             })
             selectedIdx = 0
        } else {
            for (var j = 0; j < filteredPlatforms.count; j++) {
                if (filteredPlatforms.get(j).name.toLowerCase().indexOf("exodos") !== -1) {
                    selectedIdx = j
                    break
                }
            }
        }
        
        platformSelector.currentIndex = selectedIdx
    }

    function openImport() {
        refreshFilteredPlatforms()
        open()
    }

    FolderDialog {
        id: folderDialog
        title: "Select eXoDOS Directory (The parent of 'eXo')"
        onAccepted: {
            var path = selectedFolder.toString()
            if (path.startsWith("file://")) {
                path = path.substring(7)
            }
            appSettings.exodosPath = path
            appSettings.save()
        }
    }

    onOpened: {
        if (appSettings.exodosPath !== "" && exodosModel.count === 0 && !loading) {
            loading = true
            storeBridge.refresh_exodos_library(appSettings.exodosPath)
        }
    }

    contentItem: Item {
        implicitHeight: mainCol.implicitHeight
        
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15

            Text {
                text: "Import eXoDOS Games"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                TheophanyTextField {
                    id: pathField
                    Layout.fillWidth: true
                    placeholderText: "Select eXoDOS installation directory..."
                    text: appSettings.exodosPath
                    onEditingFinished: {
                        if (appSettings.exodosPath !== text) {
                            appSettings.exodosPath = text
                            appSettings.save()
                        }
                    }
                }

                TheophanyButton {
                    text: "Browse..."
                    onClicked: folderDialog.open()
                }
                
                TheophanyButton {
                    text: "Scan"
                    primary: true
                    enabled: appSettings.exodosPath !== "" && !loading
                    onClicked: {
                        loading = true
                        storeBridge.refresh_exodos_library(appSettings.exodosPath)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15
                visible: appSettings.exodosPath !== ""

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true
                        Text { text: "Import to Collection:"; color: Theme.accent; font.pixelSize: 11; font.bold: true }
                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true
                            TheophanyComboBox {
                                id: platformSelector
                                Layout.fillWidth: true
                                model: filteredPlatforms
                                textRole: "name"
                            }
                            
                            TheophanyButton {
                                text: "+"
                                primary: true
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: 32
                                onClicked: {
                                    addSystemDialog.openAddWithType("DOS", "eXoDOS")
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15
                    visible: exodosModel.count > 0 && !root.loading

                    TheophanyButton {
                        text: "Select All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            selectAllMode = true
                            manualToggles = {}
                        }
                    }

                    TheophanyButton {
                        text: "Deselect All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            selectAllMode = false
                            manualToggles = {}
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: selectedCount + " of " + exodosModel.count + " games found"
                        color: Theme.secondaryText
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.sidebar
                    radius: 8
                    clip: true
                    border.color: Theme.border
                    border.width: 1

                    ListView {
                        id: list
                        anchors.fill: parent
                        anchors.margins: 1
                        model: exodosModel
                        spacing: 0
                        visible: !root.loading && exodosModel.count > 0
                        clip: true

                        ScrollBar.vertical: ScrollBar { }

                        delegate: Rectangle {
                            width: list.width; height: 50
                            color: ma.containsMouse ? Theme.hover : "transparent"
                            
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 20
                                height: 1
                                color: Theme.border
                                opacity: 0.1
                            }

                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    var mid = model.gameId
                                    var newToggles = Object.assign({}, manualToggles)
                                    if (newToggles[mid]) {
                                        delete newToggles[mid]
                                    } else {
                                        newToggles[mid] = true
                                    }
                                    manualToggles = newToggles
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 15

                                TheophanyCheckBox {
                                    checked: {
                                        var isManual = !!manualToggles[model.gameId]
                                        return selectAllMode ? !isManual : isManual
                                    }
                                    onToggled: {
                                        var mid = model.gameId
                                        var newToggles = Object.assign({}, manualToggles)
                                        if (newToggles[mid]) {
                                            delete newToggles[mid]
                                        } else {
                                            newToggles[mid] = true
                                        }
                                        manualToggles = newToggles
                                    }
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        text: model.title
                                        color: Theme.text
                                        font.bold: true
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "No games found in the specified eXoDOS directory.\nMake sure you selected the parent of the 'eXo' folder."
                        color: Theme.secondaryText
                        horizontalAlignment: Text.AlignHCenter
                        visible: !root.loading && exodosModel.count === 0 && appSettings.exodosPath !== ""
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.loading
                        visible: running
                    }
                }
            }
            
            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                Layout.topMargin: 5

                TheophanyButton {
                    text: "Close"
                    onClicked: root.close()
                }

                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: "Import Selected (" + selectedCount + ")"
                    primary: true
                    visible: exodosModel.count > 0
                    enabled: selectedCount > 0 && !root.loading
                    onClicked: {
                        var idx = platformSelector.currentIndex
                        if (idx < 0 || filteredPlatforms.count === 0) {
                            return
                        }
                        
                        var platformId = filteredPlatforms.get(idx).id
                        var platformName = filteredPlatforms.get(idx).name
                        console.log("[ExoDosImport] Selected Platform: " + platformName + " (ID: " + platformId + ")")
                        
                        if (platformId === "virtual_dos") {
                                var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                                console.log("[ExoDosImport] Creating new eXoDOS platform with ID: " + newId)
                                sidebar.platformModel.updateSystem(
                                    newId, "eXoDOS", "", "", "", "DOS", "assets/systems/exodos.png", ""
                                )
                                platformId = newId
                        }

                        var selectedRoms = []
                        for (var i = 0; i < rawResults.length; i++) {
                            var rawItem = rawResults[i]
                            var mid = rawItem.id
                            var isManual = !!manualToggles[mid]
                            var isSelected = selectAllMode ? !isManual : isManual
                            
                            if (isSelected) {
                                var romObj = {
                                    id: rawItem.id,
                                    platform_id: platformId,
                                    path: rawItem.path,
                                    filename: rawItem.filename,
                                    file_size: rawItem.file_size || 0,
                                    title: rawItem.title || "",
                                    tags: rawItem.tags || "",
                                    developer: rawItem.developer || "",
                                    publisher: rawItem.publisher || "",
                                    genre: rawItem.genre || "",
                                    release_date: rawItem.release_date || "",
                                    description: rawItem.description || "",
                                    is_installed: true,
                                    is_favorite: rawItem.is_favorite === true,
                                    resources: rawItem.resources || []
                                };
                                selectedRoms.push(romObj);
                            }
                        }
                        
                        if (selectedRoms.length > 0) {
                            var json = JSON.stringify(selectedRoms)
                            console.log("[ExoDosImport] Sending JSON: " + json)
                            progressDialog.progress = 0.0
                            progressDialog.status = "Preparing to import " + selectedRoms.length + " games..."
                            progressDialog.open()
                            storeBridge.import_exodos_games(json, platformId, appSettings.exodosPath)
                        }
                    }
                }
            }
        }
    }

    ImportProgressDialog {
        id: progressDialog
        title: "Importing eXoDOS Games"
        onClosed: {
            root.close()
        }
    }

    TheophanyMessageDialog {
        id: errorDialog
        title: "Import Status"
    }
}
