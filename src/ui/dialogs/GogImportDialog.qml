import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import GOG Games"
    modal: true
    closePolicy: Popup.NoAutoClose
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

        onGogLibraryFinished: (resultsJson) => {
            var results = JSON.parse(resultsJson)
            results.sort(function(a, b) { return a.title.localeCompare(b.title) })

            gogModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                gogModel.append({
                    "checked":          item.is_installed,
                    "gameId":           item.id || "",
                    "title":            (item.title || "").replace(/ Game$/, ""),
                    "path":             item.path || "",
                    "filename":         item.filename || "",
                    "icon_path":        item.icon_path || "",
                    "boxart_path":      item.boxart_path || "",
                    "background_path":  item.background_path || "",
                    "platform_id":      item.platform_id || "",
                    "platform_name":    item.platform_name || "GOG",
                    "tags":             item.tags || "",
                    "developer":        item.developer || "",
                    "genre":            item.genre || "",
                    "description":      item.description || "",
                    "total_play_time":  item.total_play_time || 0,
                    "last_played":      item.last_played || 0,
                    "is_installed":     item.is_installed
                })
            }
            loading = false
        }

        onGogAuthUrlReceived: (url) => {
            // Open the GOG login page in the default browser, then ask the user to paste
            // the full redirect URL from the browser's address bar.
            Qt.openUrlExternally(url)
            waitingForAuth = true
            loading = false
        }

        onGogAuthFinished: (success, message) => {
            if (success) {
                loading = true
                isLoggedIn = true
                waitingForAuth = false
                storeBridge.refresh_gog_library()
            } else {
                loading = false
                if (message.indexOf("lgogdownloader binary not found") !== -1) {
                    errorDialog.text = "Login Failed: " + message + ". Please ensure lgogdownloader is installed."
                    root.redirectAfterError = true
                } else {
                    errorDialog.text = "Login Failed: " + message
                    root.redirectAfterError = false
                }
                errorDialog.open()
            }
        }

        onGogLogoutFinished: (success, message) => {
            loading = false
            if (success) {
                isLoggedIn = false
                waitingForAuth = false
                gogModel.clear()
            } else {
                errorDialog.text = "Logout Failed: " + message
                errorDialog.open()
            }
        }

        onInstallProgress: (appName, progress, message) => {
            progressDialog.open()
            progressDialog.progress = progress
            progressDialog.status = message
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
                if (message === "Cancelled") return
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
    property bool redirectAfterError: false
    ListModel { id: gogModel }
    ListModel { id: filteredPlatforms }

    property int selectedCount: {
        var count = 0
        for (var i = 0; i < gogModel.count; i++) {
            if (gogModel.get(i).checked) count++
        }
        return count
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) return

        var selectedIdx = 0
        var hasGog = false

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = sidebar.platformModel.data(idx, 261) || ""
            if (type === "gog" || name.toLowerCase().indexOf("gog") !== -1) {
                filteredPlatforms.append({
                    "name": name,
                    "id": sidebar.platformModel.data(idx, 256)
                })
                hasGog = true
            }
        }

        if (!hasGog) {
            filteredPlatforms.insert(0, {
                "name": "GOG (Default)",
                "id": "virtual_gog"
            })
            selectedIdx = 0
        } else {
            for (var j = 0; j < filteredPlatforms.count; j++) {
                if (filteredPlatforms.get(j).name.toLowerCase().indexOf("gog") !== -1) {
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
        isLoggedIn = storeBridge.check_gog_auth()
        if (isLoggedIn) {
            storeBridge.refresh_gog_library()
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
                text: "Import GOG Games"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5
            }

            // ── Not Logged In ───────────────────────────────────────────────────
            ColumnLayout {
                visible: !isLoggedIn && !waitingForAuth
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 20
                Layout.alignment: Qt.AlignCenter

                Text {
                    text: "You are not logged into GOG via lgogdownloader."
                    color: Theme.secondaryText
                    Layout.alignment: Qt.AlignCenter
                }

                Text {
                    text: "lgogdownloader must be installed on your system."
                    color: Theme.secondaryText
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignCenter
                }

                TheophanyButton {
                    text: "Login with GOG"
                    primary: true
                    Layout.alignment: Qt.AlignCenter
                    loading: root.loading
                    enabled: !root.loading
                    onClicked: {
                        root.loading = true
                        storeBridge.get_gog_auth_url()
                    }
                }
            }

            // ── Redirect URL Paste View (GOG browser-login) ────────────────────
            ColumnLayout {
                visible: waitingForAuth
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16
                Layout.alignment: Qt.AlignCenter

                Text {
                    text: "A browser window has opened for GOG login."
                    color: Theme.text
                    font.bold: true
                    Layout.alignment: Qt.AlignCenter
                }

                Text {
                    text: "After you have logged in, copy the full URL from your browser's address bar\n" +
                          "and paste it below (it should look like: https://embed.gog.com/on_login_success?...)"
                    color: Theme.secondaryText
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignCenter
                }

                TheophanyTextField {
                    id: redirectUrlField
                    Layout.preferredWidth: 520
                    Layout.alignment: Qt.AlignCenter
                    placeholderText: "Paste full redirect URL here..."
                }

                RowLayout {
                    Layout.alignment: Qt.AlignCenter
                    spacing: 15

                    TheophanyButton {
                        text: "Submit"
                        primary: true
                        loading: root.loading
                        enabled: !root.loading && redirectUrlField.text.trim() !== ""
                        onClicked: {
                            root.loading = true
                            storeBridge.authenticate_gog(redirectUrlField.text.trim())
                        }
                    }

                    TheophanyButton {
                        text: "Cancel"
                        onClicked: waitingForAuth = false
                    }
                }
            }

            // ── Library View ────────────────────────────────────────────────────
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
                                    addSystemDialog.openAddWithType("gog", "GOG")
                                }
                            }
                        }
                    }

                    TheophanyButton {
                        text: "Refresh Library"
                        Layout.alignment: Qt.AlignBottom
                        loading: root.loading
                        enabled: !root.loading
                        onClicked: {
                            root.loading = true
                            storeBridge.refresh_gog_library()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15
                    visible: gogModel.count > 0 && !root.loading

                    TheophanyButton {
                        text: "Select All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            for (var i = 0; i < gogModel.count; i++) gogModel.setProperty(i, "checked", true)
                        }
                    }

                    TheophanyButton {
                        text: "Deselect All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            for (var i = 0; i < gogModel.count; i++) gogModel.setProperty(i, "checked", false)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: selectedCount + " of " + gogModel.count + " games selected"
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
                        model: gogModel
                        spacing: 0
                        visible: !root.loading && gogModel.count > 0
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

                                // Game icon / fallback letter
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
                                        text: "G"
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
                                        text: "GOG" + (model.is_installed ? " (Installed)" : " (Not installed locally)")
                                        color: model.is_installed ? Theme.accent : Theme.secondaryText
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "No games found in your GOG library."
                        color: Theme.secondaryText
                        visible: !root.loading && gogModel.count === 0 && isLoggedIn
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.loading
                        visible: running
                    }
                }
            }

            // ── Bottom bar ──────────────────────────────────────────────────────
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
                    loading: root.loading
                    enabled: !root.loading
                    onClicked: {
                        root.loading = true
                        storeBridge.logout_gog()
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

                        // Auto-create a GOG collection if none exists yet
                        if (platformId === "virtual_gog") {
                            var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                            sidebar.platformModel.updateSystem(
                                newId, "GOG", "", "", "", "gog", "assets/systems/gog", ""
                            )
                            platformId = newId
                        }

                        var selectedRoms = []
                        for (var i = 0; i < gogModel.count; i++) {
                            var item = gogModel.get(i)
                            if (item.checked) {
                                selectedRoms.push({
                                    id:               item.gameId,
                                    platform_id:      platformId,
                                    path:             item.path,
                                    filename:         item.filename,
                                    file_size:        0,
                                    title:            item.title,
                                    icon_path:        item.icon_path || "",
                                    boxart_path:      item.boxart_path || "",
                                    background_path:  item.background_path || "",
                                    tags:             item.tags || "",
                                    developer:        item.developer || "",
                                    genre:            item.genre || "",
                                    description:      item.description || "",
                                    total_play_time:  item.total_play_time || 0,
                                    last_played:      item.last_played || 0,
                                    is_installed:     item.is_installed
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
        title: "Importing GOG Games"
        onClosed: {
            root.close()
        }
    }

    TheophanyMessageDialog {
        id: errorDialog
        title: "Import Status"
        onAccepted: {
            if (root.redirectAfterError) {
                root.close()
                settingsDialog.open()
                settingsDialog.openTab("System")
                root.redirectAfterError = false
            }
        }
    }
}
