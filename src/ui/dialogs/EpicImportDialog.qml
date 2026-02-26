import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import Epic Games"
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
        
        onLegendaryLibraryFinished: (resultsJson) => {
            var results = JSON.parse(resultsJson)
             // Sort alphabetically
            results.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })

            epicModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                epicModel.append({
                    "checked": item.is_installed,
                    "gameId": item.id || "",
                    "title": item.title || "Unknown Game",
                    "path": item.path || "",
                    "filename": item.filename || "",
                    "icon_path": item.icon_path || "",
                    "boxart_path": item.boxart_path || "",
                    "background_path": item.background_path || "",
                    "platform_id": item.platform_id || "",
                    "platform_name": item.platform_name || "Epic Games",
                    "tags": item.tags || "",
                    "developer": item.developer || "",
                    "genre": item.genre || "",
                    "description": item.description || "",
                    "total_play_time": item.total_play_time || 0,
                    "last_played": item.last_played || 0,
                    "is_installed": item.is_installed,
                    "cloud_saves_supported": item.cloud_saves_supported || false
                })
            }
            loading = false
        }

        onLegendaryAuthUrlReceived: (url) => {
            Qt.openUrlExternally(url)
            waitingForAuth = true
            loading = false
        }

        onLegendaryAuthFinished: (success, message) => {
            loading = false
            if (success) {
                isLoggedIn = true
                waitingForAuth = false
                storeBridge.refresh_legendary_library()
            } else {
                errorDialog.text = "Login Failed: " + message
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
                progressDialog.progress = 1.0
                progressDialog.status = "Import complete! " + message
                gameModel.refresh()
            } else {
                progressDialog.close()
                if (message === "Cancelled") return;
                
                errorDialog.text = "Import Result for " + appName + ":\n" + message
                errorDialog.open()
            }
            window.hasBackgroundActivity = false
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: storeBridge.poll()
    }

    property bool loading: false
    property bool isLoggedIn: false
    property bool waitingForAuth: false
    ListModel { id: epicModel }
    ListModel { id: filteredPlatforms }

    property int selectedCount: {
        var count = 0
        for (var i = 0; i < epicModel.count; i++) {
            if (epicModel.get(i).checked) count++
        }
        return count
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) return
        
        var selectedIdx = 0
        var hasEpic = false

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = sidebar.platformModel.data(idx, 261) || ""
            if (type === "epic" || name.toLowerCase().indexOf("epic") !== -1) {
                filteredPlatforms.append({
                    "name": name,
                    "id": sidebar.platformModel.data(idx, 256)
                })
                hasEpic = true
            }
        }
        
        // Add virtual default if none found
        if (!hasEpic) {
             filteredPlatforms.insert(0, {
                 "name": "Epic Games (Default)",
                 "id": "virtual_epic"
             })
             selectedIdx = 0
        } else {
            // Auto-select best match if existing
            for (var j = 0; j < filteredPlatforms.count; j++) {
                if (filteredPlatforms.get(j).name.toLowerCase().indexOf("epic") !== -1) {
                    selectedIdx = j
                    break
                }
            }
        }
        
        platformSelector.currentIndex = selectedIdx
    }

    function openImport() {
        loading = true
        waitingForAuth = false
        isLoggedIn = storeBridge.check_legendary_auth()
        if (isLoggedIn) {
            storeBridge.refresh_legendary_library()
        } else {
            loading = false
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

            Text {
                text: "Import Epic Games"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            // Authentication View
            ColumnLayout {
                visible: !isLoggedIn && !waitingForAuth
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 20
                Layout.alignment: Qt.AlignCenter

                Text {
                    text: "You are not logged into Epic Games via Legendary."
                    color: Theme.secondaryText
                    Layout.alignment: Qt.AlignCenter
                }

                TheophanyButton {
                    text: "Login with Epic Games"
                    primary: true
                    Layout.alignment: Qt.AlignCenter
                    onClicked: {
                        root.loading = true
                        storeBridge.get_legendary_auth_url()
                    }
                }
            }

            // Auth Code Entry View
            ColumnLayout {
                visible: waitingForAuth
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 20
                Layout.alignment: Qt.AlignCenter

                Text {
                    text: "Please enter the authorization code from the browser window:"
                    color: Theme.text
                    Layout.alignment: Qt.AlignCenter
                }

                TheophanyTextField {
                    id: codeField
                    Layout.preferredWidth: 300
                    Layout.alignment: Qt.AlignCenter
                    placeholderText: "Paste code here..."
                }

                RowLayout {
                    Layout.alignment: Qt.AlignCenter
                    spacing: 15
                    
                    TheophanyButton {
                        text: "Submit"
                        primary: true
                        onClicked: {
                            root.loading = true
                            storeBridge.authenticate_legendary(codeField.text)
                        }
                    }
                    
                    TheophanyButton {
                        text: "Cancel"
                        onClicked: waitingForAuth = false
                    }
                }
            }

            // Main Library View
            ColumnLayout {
                visible: isLoggedIn && !waitingForAuth
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15

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
                                    addSystemDialog.openAddWithType("epic", "Epic Games")
                                }
                            }
                        }
                    }

                    TheophanyButton {
                        text: "Refresh Library"
                        Layout.alignment: Qt.AlignBottom
                        onClicked: {
                            root.loading = true
                            storeBridge.refresh_legendary_library()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15
                    visible: epicModel.count > 0 && !root.loading

                    TheophanyButton {
                        text: "Select All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            for (var i = 0; i < epicModel.count; i++) epicModel.setProperty(i, "checked", true)
                        }
                    }

                    TheophanyButton {
                        text: "Deselect All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            for (var i = 0; i < epicModel.count; i++) epicModel.setProperty(i, "checked", false)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: selectedCount + " of " + epicModel.count + " games selected"
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
                        model: epicModel
                        spacing: 0
                        visible: !root.loading && epicModel.count > 0
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
                                        text: "E"
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
                                    RowLayout {
                                        Text {
                                            text: model.platform_name + (model.is_installed ? " (Installed)" : " (Cloud)")
                                            color: model.is_installed ? Theme.accent : Theme.secondaryText
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                        
                                        Rectangle {
                                            width: 14; height: 14; color: "transparent"
                                            visible: model.cloud_saves_supported
                                            border.color: Theme.accent
                                            border.width: 1
                                            radius: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            
                                            Text {
                                                anchors.centerIn: parent
                                                text: "☁"
                                                font.pixelSize: 10
                                                color: Theme.accent
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "No games found in your Epic Games library."
                        color: Theme.secondaryText
                        visible: !root.loading && epicModel.count === 0 && isLoggedIn
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
                    text: "Logout"
                    visible: isLoggedIn && !waitingForAuth
                    onClicked: {
                        // Legendary doesn't have a simple 'logout' command that isn't interactive, 
                        // but we can just clear the local state logic-wise if needed.
                        // For now we'll just close or let user manage via CLI if they really want to logout.
                    }
                }

                TheophanyButton {
                    text: "Import Selected (" + selectedCount + ")"
                    primary: true
                    visible: isLoggedIn && !waitingForAuth
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
                        if (platformId === "virtual_epic") {
                                var newId = "platform-" + Math.random().toString(36).substr(2, 9)

                                sidebar.platformModel.updateSystem(
                                    newId, "Epic Games", "", "", "", "epic", "assets/systems/epic", ""
                                )
                                platformId = newId
                        }

                        var selectedRoms = []
                    
                        for (var i = 0; i < epicModel.count; i++) {
                            var item = epicModel.get(i)
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
                                    last_played: item.last_played || 0,
                                    is_installed: item.is_installed
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
        title: "Importing Epic Games"
        onClosed: {
            root.close()
        }
    }

    TheophanyMessageDialog {
        id: errorDialog
        title: "Import Status"
    }
}
