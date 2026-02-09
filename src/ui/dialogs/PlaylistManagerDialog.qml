import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Theophany.Bridge 1.0
import "../style"
import "../components"

Dialog {
    id: root
    title: "Manage Playlists"
    modal: true
    focus: true
    
    // Custom window controls means disabling standard flags if possible, or just hiding header
    // In QtQuick Controls Dialog, setting header to null removes system/theme header usually
    header: null
    
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: 900
    height: 650

    signal playlistUpdated()

    property string dbPath: ""
    property string selectedPlaylistId: ""
    property string selectedPlaylistName: ""

    // Use AppInfo to ensure correct path if dbPath is empty
    AppInfo { id: appInfoDialog }

    // Proxy models for this dialog
    GameListModel {
        id: internalGameModel
        Component.onCompleted: {
             // Init with provided path or lookup from appInfo
             var path = root.dbPath
             if (path === "") path = appInfoDialog.getDataPath() + "/games.db"
             init(path)
        }
    }
    
    // Ensure model is ready when dialog opens
    onOpened: {
        var path = root.dbPath
        if (path === "") path = appInfoDialog.getDataPath() + "/games.db"
        
        // Re-init or refresh to ensure connection is alive
        // If already initialized, init might be a no-op or safe re-connect
        internalGameModel.init(path)
        
        // Clear previous selection
        root.selectedPlaylistId = ""
        root.selectedPlaylistName = ""
        // Set to a non-existent playlist ID so no games load initially
        // When a real playlist is selected, it will properly filter
        internalGameModel.setPlaylistFilter("__none__")
    }
    
    // Polling timer for async model updates
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: internalGameModel.checkAsyncResponses()
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12
        
        // Premium subtle glow matches EmulatorManager
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20
        
        // --- Header ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 15
            
            Text { 
                text: "Manage Playlists" 
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

        // --- Main Content ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 24

            // Left Panel: Playlist List
            ColumnLayout {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                spacing: 15

                Text {
                    text: "Your Playlists"
                    color: Theme.secondaryText
                    font.pixelSize: 14
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.sidebar
                    radius: 8
                    border.color: Theme.border

                    ListView {
                        id: playlistView
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        model: playlistModel
                        spacing: 2
                        
                        delegate: Rectangle {
                            width: playlistView.width - 8
                            height: 40
                            color: root.selectedPlaylistId === playlistId ? Theme.accent : (ma.containsMouse ? Theme.hover : "transparent")
                            radius: 6
                            
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedPlaylistId = playlistId
                                    root.selectedPlaylistName = playlistName
                                    
                                    // Set playlist filter (this clears other filters and refreshes)
                                    internalGameModel.setPlaylistFilter(playlistId)
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                
                                Text {
                                    text: "📜"
                                    font.pixelSize: 14
                                }
                                
                                Text {
                                    text: playlistName
                                    color: Theme.text
                                    font.pixelSize: 14
                                    font.bold: root.selectedPlaylistId === playlistId
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                ToolButton {
                                    text: "🗑️"
                                    visible: ma.containsMouse || root.selectedPlaylistId === playlistId
                                    onClicked: {
                                        deleteConfirmDialog.playlistId = playlistId
                                        deleteConfirmDialog.playlistName = playlistName
                                        deleteConfirmDialog.open()
                                    }
                                    background: Rectangle { color: "transparent" }
                                }
                            }
                        }
                    }
                }

                // Create New Playlist
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    TheophanyTextField {
                        id: newNameInput
                        placeholderText: "New Playlist..."
                        Layout.fillWidth: true
                        onAccepted: createBtn.clicked()
                    }

                    TheophanyButton {
                        id: createBtn
                        text: "+"
                        Layout.preferredWidth: 40
                        primary: true
                        onClicked: {
                            if (newNameInput.text !== "") {
                                var newId = playlistModel.createPlaylist(newNameInput.text)
                                root.playlistUpdated()
                                newNameInput.text = ""
                                if (newId !== "") {
                                    root.selectedPlaylistId = newId
                                    root.selectedPlaylistName = "" // Will update on refresh
                                    // Set playlist filter (this clears other filters and refreshes)
                                    internalGameModel.setPlaylistFilter(newId)
                                }
                            }
                        }
                    }
                }
            }

            // Vertical Separator
            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: Theme.border
            }

            // Right Panel: Games in Playlist
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.selectedPlaylistId === "" ? "Select a playlist" : root.selectedPlaylistName
                        color: Theme.text
                        font.pixelSize: 18
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    
                    TheophanyButton {
                        text: "Rename"
                        visible: root.selectedPlaylistId !== ""
                        flat: true
                        onClicked: renameDialog.open()
                    }

                    TheophanyButton {
                        text: "Delete Playlist"
                        visible: root.selectedPlaylistId !== ""
                        accentColor: "#ff4444"
                        flat: true
                        onClicked: {
                            deleteConfirmDialog.playlistId = root.selectedPlaylistId
                            deleteConfirmDialog.playlistName = root.selectedPlaylistName
                            deleteConfirmDialog.open()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.background
                    radius: 8
                    border.color: Theme.border
                    visible: root.selectedPlaylistId !== ""

                    ListView {
                        id: gameView
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        model: internalGameModel
                        spacing: 2
                        
                        delegate: Rectangle {
                            width: gameView.width - 8
                            height: 45
                            color: gma.containsMouse ? Theme.hover : "transparent"
                            radius: 6
                            
                            MouseArea {
                                id: gma
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12
                                
                                Image {
                                    source: {
                                        if (!model.gamePlatformIcon || model.gamePlatformIcon === "") return ""
                                        var pIcon = model.gamePlatformIcon
                                        if (pIcon.startsWith("http") || pIcon.startsWith("file://") || pIcon.startsWith("qrc:/") || pIcon.startsWith("/")) {
                                            return pIcon.startsWith("/") ? "file://" + pIcon : pIcon
                                        }
                                        if (pIcon.startsWith("assets/")) {
                                            return "file://" + appInfoDialog.getAssetsDir().replace("/assets", "") + "/" + pIcon
                                        }
                                        return "file://" + pIcon
                                    }
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    fillMode: Image.PreserveAspectFit
                                    visible: source != ""
                                }
                                
                                Text {
                                    text: gameTitle
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                
                                Rectangle {
                                    width: 1
                                    height: 20
                                    color: Theme.border
                                }

                                TheophanyButton {
                                    text: "Remove"
                                    Layout.preferredHeight: 28
                                    Layout.preferredWidth: 80
                                    accentColor: "#ff4444"
                                    flat: true
                                    onClicked: {
                                        playlistModel.removeFromPlaylist(root.selectedPlaylistId, model.gameId)
                                        // Refresh the view
                                        internalGameModel.refresh() 
                                        root.playlistUpdated()
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "No games in this playlist"
                            color: Theme.secondaryText
                            visible: internalGameModel.rowCount() === 0
                            font.italic: true
                        }
                    }
                }
                
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.selectedPlaylistId === ""
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            text: "📜"
                            font.pixelSize: 48
                            Layout.alignment: Qt.AlignHCenter
                            opacity: 0.3
                        }
                        Text {
                            text: "Select a playlist on the left to manage its games."
                            color: Theme.secondaryText
                            font.italic: true
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }
        
        // --- Footer ---
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
        
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 12
            
            TheophanyButton {
                text: "Close"
                primary: true // Use primary for the main close action
                onClicked: root.close()
                Layout.preferredWidth: 100
            }
        }
    }

    // Set standard buttons to null to remove default footer
    footer: null 

    // Sub-dialogs
    Dialog {
        id: deleteConfirmDialog
        anchors.centerIn: Overlay.overlay
        modal: true
        padding: 0 // Using custom layout for better control
        header: null
        footer: null
        
        property string playlistId: ""
        property string playlistName: ""

        background: Rectangle { 
            color: Theme.secondaryBackground
            border.color: Theme.border
            radius: 12
            implicitWidth: 400
            implicitHeight: 250
            
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                color: "#40000000"
                radius: 20
                samples: 41
            }
        }
        
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            Text {
                text: "Delete Playlist"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 }

            Label {
                text: "Are you sure you want to delete the playlist <b>" + deleteConfirmDialog.playlistName + "</b>?"
                color: Theme.text
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                
                Item { Layout.fillWidth: true }
                
                TheophanyButton {
                    text: "No"
                    onClicked: deleteConfirmDialog.reject()
                    Layout.preferredWidth: 80
                }
                
                TheophanyButton {
                    text: "Yes, Delete"
                    primary: true
                    accentColor: "#ff4444"
                    onClicked: deleteConfirmDialog.accept()
                    Layout.preferredWidth: 120
                }
            }
        }

        onAccepted: {
            playlistModel.deletePlaylist(playlistId)
            root.playlistUpdated()
            if (root.selectedPlaylistId === playlistId) {
                root.selectedPlaylistId = ""
                root.selectedPlaylistName = ""
            }
        }
    }

    Dialog {
        id: renameDialog
        anchors.centerIn: Overlay.overlay
        modal: true
        padding: 0
        header: null
        footer: null

        background: Rectangle { 
            color: Theme.secondaryBackground
            border.color: Theme.border
            radius: 12
            implicitWidth: 400
            implicitHeight: 280
            
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                color: "#40000000"
                radius: 20
                samples: 41
            }
        }
        
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            Text {
                text: "Rename Playlist"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "New name for <b>" + root.selectedPlaylistName + "</b>:"; color: Theme.secondaryText; font.pixelSize: 13 }
                TheophanyTextField {
                    id: renameInput
                    text: root.selectedPlaylistName
                    Layout.fillWidth: true
                    focus: true
                    onAccepted: renameDialog.accept()
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                
                Item { Layout.fillWidth: true }
                
                TheophanyButton {
                    text: "Cancel"
                    onClicked: renameDialog.reject()
                    Layout.preferredWidth: 100
                }
                
                TheophanyButton {
                    text: "Rename"
                    primary: true
                    onClicked: renameDialog.accept()
                    Layout.preferredWidth: 100
                }
            }
        }

        onAccepted: {
            if (renameInput.text !== "") {
                playlistModel.renamePlaylist(root.selectedPlaylistId, renameInput.text)
                root.selectedPlaylistName = renameInput.text
                root.playlistUpdated()
            }
        }
    }
}
