import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import Steam Games"
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
        onSteamLibraryFinished: (resultsJson) => {
            var results = JSON.parse(resultsJson)
            
            // Sort alphabetically
            results.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })

            // Create a set of existing IDs
            var existingIds = {}
            for (var k = 0; k < steamModel.count; k++) {
                existingIds[steamModel.get(k).gameId] = true
            }

            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                if (!existingIds[item.id]) {
                    var sanitized = {
                        "checked": true,
                        "gameId": item.id || "",
                        "title": item.title || "Unknown Game",
                        "path": item.path || "",
                        "filename": item.filename || "",
                        "icon_path": item.icon_path || "",
                        "boxart_path": item.boxart_path || "",
                        "background_path": item.background_path || "",
                        "platform_id": item.platform_id || "",
                        "tags": item.tags || "",
                        "total_play_time": item.total_play_time || 0,
                        "is_installed": (typeof item.is_installed !== "undefined") ? item.is_installed : true
                    }
                    steamModel.append(sanitized)
                }
            }
            loading = false
        }

        onRemoteSteamLibraryFinished: (resultsJson, success, message) => {
            if (success) {
                var results = JSON.parse(resultsJson)
                
                results.sort(function(a, b) {
                    return a.title.localeCompare(b.title)
                })

                // Create a set of existing IDs
                var existingIds = {}
                for (var i = 0; i < steamModel.count; i++) {
                    existingIds[steamModel.get(i).gameId] = true
                }

                for (var j = 0; j < results.length; j++) {
                    var item = results[j]
                    if (!existingIds[item.id]) {
                        var sanitized = {
                            "checked": true,
                            "gameId": item.id || "",
                            "title": item.title || "Unknown Game",
                            "path": item.path || "",
                            "filename": item.filename || "",
                            "icon_path": item.icon_path || "",
                            "boxart_path": item.boxart_path || "",
                            "background_path": item.background_path || "",
                            "platform_id": item.platform_id || "",
                            "tags": item.tags || "",
                            "total_play_time": item.total_play_time || 0,
                            "is_installed": (typeof item.is_installed !== "undefined") ? item.is_installed : false
                        }
                        steamModel.append(sanitized)
                    }
                }
                remoteLoading = false
            } else {
                remoteLoading = false
                errorDialog.text = "Failed to fetch remote library:\n" + message
                errorDialog.open()
            }
        }
        
        onInstallProgress: (appName, progress, message) => {
            progressDialog.open()
            progressDialog.progress = progress
            progressDialog.status = message

            // Sync with global ticker
            window.backgroundActivityId = "Artwork"
            window.backgroundActivityProgress = progress
            window.backgroundActivityStatus = message
            window.hasBackgroundActivity = true
        }

        onInstallFinished: (appName, success, message) => {
            if (success) {
                // Keep open for user confirmation
                progressDialog.progress = 1.0
                progressDialog.status = "Import complete! " + message
                gameModel.refresh()
            } else {
                progressDialog.close()
                errorDialog.text = "Import Result for " + appName + ":\n" + message
                errorDialog.open()
            }
            window.hasBackgroundActivity = false
        }
    }

    Connections {
        target: addSystemDialog
        function onSystemConfigured() {
            if (root.visible) refreshFilteredPlatforms()
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: storeBridge.poll()
    }

    property bool loading: false
    property bool remoteLoading: false
    ListModel { id: steamModel }
    ListModel { id: filteredPlatforms }

    property int selectedCount: {
        var count = 0
        for (var i = 0; i < steamModel.count; i++) {
            if (steamModel.get(i).checked) count++
        }
        return count
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) {

            return
        }
        
        var hasSteam = false
        var selectedIdx = 0

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = sidebar.platformModel.data(idx, 261) || ""
            if (type === "steam" || name.toLowerCase().indexOf("steam") !== -1) {
                // If existing Steam platform found
                filteredPlatforms.append({
                    "name": name,
                    "id": sidebar.platformModel.data(idx, 256)
                })
                hasSteam = true
            }
        }

        // Add virtual default if none found
        if (!hasSteam) {
             filteredPlatforms.insert(0, {
                 "name": "Steam (Default)",
                 "id": "virtual_steam"
             })
             selectedIdx = 0
        }
        
        platformSelector.currentIndex = selectedIdx

    }

    function openImport() {
        loading = true
        steamModel.clear()
        storeBridge.refresh_steam_library()
        if (appSettings.steamId !== "" && appSettings.steamApiKey !== "") {
            remoteLoading = true
            storeBridge.refresh_remote_steam_library(appSettings.steamId, appSettings.steamApiKey)
        } else {
            remoteLoading = false
        }
        refreshFilteredPlatforms()
        open()
    }

    contentItem: Item {
        implicitHeight: mainCol.implicitHeight
        
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15

            // Standard Modal Header
            Text {
                text: "Import Steam Games"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            // Configuration Row
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
                                addSystemDialog.openAddWithType("steam", "Steam")
                            }
                        }
                    }
                }

                TheophanyButton {
                    text: "Refresh Installed Library"
                    Layout.alignment: Qt.AlignBottom
                    visible: appSettings.steamId === "" || appSettings.steamApiKey === ""
                    onClicked: {
                        root.loading = true
                        storeBridge.refresh_steam_library()
                    }
                }
            }

            // Remote Library Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                Text {
                    text: (appSettings.steamId !== "" && appSettings.steamApiKey !== "") 
                        ? "Remote API config found. Remote library auto-sourced." 
                        : "No Steam API credentials found. Add them in Settings to import uninstalled games."
                    color: Theme.accent
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }
                
                TheophanyButton {
                    text: "Open Settings"
                    visible: appSettings.steamId === "" || appSettings.steamApiKey === ""
                    onClicked: {
                        root.close()
                        // Ensure settingsDialog exists in scope, it usually does from main
                        settingsDialog.open()
                        settingsDialog.openTab("Accounts")
                    }
                }
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }


            // Selection Controls Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                visible: steamModel.count > 0 && !root.loading && !root.remoteLoading

                TheophanyButton {
                    text: "Select All"
                    flat: true
                    font.pixelSize: 12
                    onClicked: {
                        for (var i = 0; i < steamModel.count; i++) steamModel.setProperty(i, "checked", true)
                    }
                }

                TheophanyButton {
                    text: "Deselect All"
                    flat: true
                    font.pixelSize: 12
                    onClicked: {
                        for (var i = 0; i < steamModel.count; i++) steamModel.setProperty(i, "checked", false)
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: selectedCount + " of " + steamModel.count + " games selected"
                    color: Theme.secondaryText
                    font.pixelSize: 12
                }
            }

            // List View Container
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
                    model: steamModel
                    spacing: 0
                    visible: !root.loading && !root.remoteLoading && steamModel.count > 0
                    clip: true

                    ScrollBar.vertical: TheophanyScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: list.width; height: 60
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
                            onClicked: model.checked = !model.checked
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 15

                            TheophanyCheckBox {
                                checked: model.checked
                                onToggled: model.checked = checked
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Rectangle {
                                width: 36; height: 36
                                color: "transparent"
                                radius: 4
                                clip: true
                                Layout.alignment: Qt.AlignVCenter
                                
                                Image {
                                    id: iconImg
                                    anchors.fill: parent
                                    source: model.icon_path ? (model.icon_path.startsWith("http") ? model.icon_path : "file://" + model.icon_path) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false 
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "♨️"
                                    font.pixelSize: 20
                                    visible: iconImg.status !== Image.Ready
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                Text {
                                    text: model.title
                                    color: Theme.text
                                    font.bold: true
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "App ID: " + model.path.replace("steam://", "")
                                    color: Theme.secondaryText
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true                                    
                                }
                                Text {
                                    text: model.installed ? "Installed Locally" : "Remote (Not Installed)"
                                    color: model.installed ? Theme.accent : Theme.secondaryText
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No Steam games found. Ensure Steam is installed and configured."
                    color: Theme.secondaryText
                    visible: !root.loading && !root.remoteLoading && steamModel.count === 0
                }

                TheophanySpinner {
                    anchors.centerIn: parent
                    running: root.loading || root.remoteLoading
                    visible: running
                    size: 48
                    text: root.loading ? "Refreshing Local..." : "Fetching Remote..."
                }
            }
            
            // Footer Buttons
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
                    enabled: selectedCount > 0 && !root.loading
                    onClicked: {

                        var idx = platformSelector.currentIndex
                        if (idx < 0) {

                            return
                        }
                        
                        var platformId = filteredPlatforms.get(idx).id
                        
                        // Handle Virtual Default Platform
                        if (platformId === "virtual_steam") {
                             var newId = "platform-" + Math.random().toString(36).substr(2, 9)

                             sidebar.platformModel.updateSystem(
                                 newId, "Steam", "*.desktop", "%ROM%", "", "steam", "assets/systems/steam", ""
                             )
                             platformId = newId
                        }
                        
                        var selectedRoms = []
                        
                        for (var i = 0; i < steamModel.count; i++) {
                            var item = steamModel.get(i)
                            if (item.checked) {
                                selectedRoms.push({
                                    id: item.gameId,
                                    platform_id: platformId,
                                    path: item.path,
                                    filename: item.filename,
                                    file_size: 0,
                                    title: item.title,
                                    icon_path: item.icon_path || "",
                                    boxart_path: item.boxart_path || "",
                                    background_path: item.background_path || "",
                                    tags: item.tags || "",
                                    total_play_time: item.total_play_time || 0,
                                    is_installed: item.installed
                                })
                            }
                        }
                        

                        if (selectedRoms.length > 0) {
                            // Show progress immediately
                            progressDialog.progress = 0.0
                            progressDialog.status = "Preparing to import " + selectedRoms.length + " games..."
                            progressDialog.open()
                            
                            // Start Import
                            storeBridge.import_steam_games_bulk(JSON.stringify(selectedRoms), platformId)
                        } else {

                        }
                    }
                }
            }
        }
    }

    ImportProgressDialog {
        id: progressDialog
        title: "Importing Steam Games"
        onClosed: {

            root.close()
        }
    }

    TheophanyMessageDialog {
        id: errorDialog
        title: "Import Status"
        // buttons: Dialog.Ok // Default
    }
}
