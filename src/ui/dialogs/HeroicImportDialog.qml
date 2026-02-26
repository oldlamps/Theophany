import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import Heroic Games"
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
        onHeroicLibraryFinished: (resultsJson) => {

            var results = JSON.parse(resultsJson)
             // Sort alphabetically
            results.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })

            heroicModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                heroicModel.append({
                    "checked": true,
                    "gameId": item.id || "",
                    "title": item.title || "Unknown Game",
                    "path": item.path || "",
                    "filename": item.filename || "",
                    "icon_path": item.icon_path || "",
                    "boxart_path": item.boxart_path || "",
                    "background_path": item.background_path || "",
                    "platform_id": item.platform_id || "",
                    "platform_name": item.platform_name || "Heroic",
                    "tags": item.tags || "",
                    "developer": item.developer || "",
                    "genre": item.genre || "",
                    "description": item.description || "",
                    "total_play_time": item.total_play_time || 0,
                    "last_played": item.last_played || 0
                })
            }
            loading = false

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
    ListModel { id: heroicModel }
    ListModel { id: filteredPlatforms }

    property int selectedCount: {
        var count = 0
        for (var i = 0; i < heroicModel.count; i++) {
            if (heroicModel.get(i).checked) count++
        }
        return count
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) return
        
        var selectedIdx = 0
        var hasHeroic = false

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = sidebar.platformModel.data(idx, 261) || ""
            if (type === "heroic" || name.toLowerCase().indexOf("heroic") !== -1) {
                filteredPlatforms.append({
                    "name": name,
                    "id": sidebar.platformModel.data(idx, 256)
                })
                hasHeroic = true
            }
        }
        
        // Add virtual default if none found
        if (!hasHeroic) {
             filteredPlatforms.insert(0, {
                 "name": "Heroic (Default)",
                 "id": "virtual_heroic"
             })
             selectedIdx = 0
        } else {
            // Auto-select best match if existing
            for (var j = 0; j < filteredPlatforms.count; j++) {
                if (filteredPlatforms.get(j).name.toLowerCase().indexOf("heroic") !== -1) {
                    selectedIdx = j
                    break
                }
            }
        }
        
        platformSelector.currentIndex = selectedIdx
    }

    function openImport() {
        loading = true
        storeBridge.refresh_heroic_library()
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

            Text {
                text: "Import Heroic Games"
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
                                addSystemDialog.openAddWithType("heroic", "Heroic")
                            }
                        }
                    }
                }

                TheophanyButton {
                    text: "Refresh Library"
                    Layout.alignment: Qt.AlignBottom
                    onClicked: {
                        root.loading = true
                        storeBridge.refresh_heroic_library()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                visible: heroicModel.count > 0 && !root.loading

                TheophanyButton {
                    text: "Select All"
                    flat: true
                    font.pixelSize: 12
                    onClicked: {
                        for (var i = 0; i < heroicModel.count; i++) heroicModel.setProperty(i, "checked", true)
                    }
                }

                TheophanyButton {
                    text: "Deselect All"
                    flat: true
                    font.pixelSize: 12
                    onClicked: {
                        for (var i = 0; i < heroicModel.count; i++) heroicModel.setProperty(i, "checked", false)
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: selectedCount + " of " + heroicModel.count + " games selected"
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
                    model: heroicModel
                    spacing: 0
                    visible: !root.loading && heroicModel.count > 0
                    clip: true

                    ScrollBar.vertical: ScrollBar { }

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
                                    source: {
                                        var p = model.icon_path || model.boxart_path || ""
                                        if (p === "") return ""
                                        if (p.startsWith("http")) return p
                                        return "file://" + p
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false 
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "H"
                                    font.pixelSize: 20
                                    color: Theme.secondaryText
                                    visible: iconImg.status !== Image.Ready
                                }
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
                                Text {
                                    text: model.platform_name + " | ID: " + model.path.split('/').pop()
                                    color: Theme.secondaryText
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No Heroic games found. Ensure Heroic is installed and configured."
                    color: Theme.secondaryText
                    visible: !root.loading && heroicModel.count === 0
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    running: root.loading
                    visible: running
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
                    enabled: selectedCount > 0 && !root.loading
                        onClicked: {
                            var idx = platformSelector.currentIndex
                            if (idx < 0 || filteredPlatforms.count === 0) {
                                errorDialog.text = "Please select or create a collection to import into."
                                errorDialog.open()
                                return
                            }
                            
                            var platformId = filteredPlatforms.get(idx).id
                            
                            // Handle Virtual Default Platform
                            if (platformId === "virtual_heroic") {
                                 var newId = "platform-" + Math.random().toString(36).substr(2, 9)
    
                                 sidebar.platformModel.updateSystem(
                                     newId, "Heroic", "", "", "", "heroic", "assets/systems/heroic", ""
                                 )
                                 platformId = newId
                            }

                            var selectedRoms = []
                        
                        for (var i = 0; i < heroicModel.count; i++) {
                            var item = heroicModel.get(i)
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
                                    developer: item.developer || "",
                                    genre: item.genre || "",
                                    description: item.description || "",
                                    total_play_time: item.total_play_time || 0,
                                    last_played: item.last_played || 0
                                })
                            }
                        }
                        
                        if (selectedRoms.length > 0) {
                             progressDialog.progress = 0.0
                             progressDialog.status = "Preparing to import " + selectedRoms.length + " games..."
                             progressDialog.open()
                             storeBridge.import_steam_games_bulk(JSON.stringify(selectedRoms), platformId)
                        }
                    }
                }
            }
        }
    }

    ImportProgressDialog {
        id: progressDialog
        title: "Importing Heroic Games"
        onClosed: {

            root.close()
        }
    }

    TheophanyMessageDialog {
        id: errorDialog
        title: "Import Status"
    }
}
