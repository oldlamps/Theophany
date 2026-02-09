import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.platform 1.1 as Platform
import "../components"
import "../style"

Dialog {
    id: root
    width: 600
    height: 500
    title: "Manage Resources"
    modal: true
    
    anchors.centerIn: Overlay.overlay

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
    
    property string gameId: ""
    property string editingResourceId: ""
    property bool isEditing: false
    signal resourcesChanged()

    header: Rectangle {
        color: "transparent"
        height: 50
        Label {
            anchors.centerIn: parent
            text: "MANAGE RESOURCES"
            font.bold: true
            font.pixelSize: 16
            font.letterSpacing: 1
            color: Theme.accent
        }
    }

    // Load Data
    function load(id) {
        root.gameId = id
        root.cancelEdit()
        var json = gameModel.getGameMetadata(id)
        try {
            var data = JSON.parse(json)
            resourceModel.clear()
            if (data.resources) {
                for (var i = 0; i < data.resources.length; i++) {
                    resourceModel.append(data.resources[i])
                }
            }
        } catch (e) {

        }
    }

    function cancelEdit() {
        root.isEditing = false
        root.editingResourceId = ""
        urlField.text = ""
        labelField.text = ""
    }

    contentItem: ColumnLayout {
        spacing: 0
        
        // List of Resources
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background
            border.color: Theme.border
            radius: 6
            clip: true
            
            ListView {
                id: resListView
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                model: ListModel { id: resourceModel }
                
                delegate: Rectangle {
                    width: resListView.width
                    height: 40
                    color: Theme.secondaryBackground
                    radius: 4
                    border.color: Theme.border
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10
                        
                        // Icon
                        Text {
                            text: {
                                var u = model.url.toLowerCase()
                                var t = model.type.toLowerCase()
                                
                                if (u.includes("wikipedia.org")) return "🌐"
                                if (u.includes("mobygames.com")) return "🎮"
                                if (u.includes("steam")) return "🎮"
                                if (u.includes("youtube.com") || u.includes("youtu.be")) return "▶️"
                                if (u.includes(".pdf")) return "📄"
                                
                                // Fallback to type
                                if (t.includes("manual")) return "📄"
                                if (t.includes("video")) return "🎬"
                                if (model.url.startsWith("file://")) return "📁"
                                return "🔗"
                            }
                            font.pixelSize: 16
                            Layout.preferredWidth: 24
                        }
                        
                        // Label
                        Label {
                            text: model.label
                            font.bold: true
                            color: Theme.text
                            Layout.preferredWidth: 120
                            elide: Text.ElideRight
                        }
                        
                        // URL
                        Label {
                            text: model.url
                            color: Theme.secondaryText
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                        
                        // Edit Button
                        TheophanyButton {
                            text: "✎"
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 24
                            onClicked: {
                                root.isEditing = true
                                root.editingResourceId = model.id
                                labelField.text = model.label
                                urlField.text = model.url
                            }
                        }

                        // Delete Button
                        TheophanyButton {
                            text: "×"
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 24
                            background: Rectangle { 
                                color: parent.down ? "#aa0000" : (parent.hovered ? "#dd0000" : "transparent")
                                radius: 4
                            }
                            onClicked: {
                                gameModel.removeGameResource(model.id)
                                root.resourcesChanged()
                                root.load(root.gameId)
                            }
                        }
                    }
                }
            }
            
            Text {
                anchors.centerIn: parent
                text: "No resources added yet."
                color: Theme.secondaryText
                visible: resListView.count === 0
            }
        }
        
        // Add Section
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            Layout.margins: 10
            color: "transparent"
            
            ColumnLayout {
                anchors.fill: parent
                spacing: 12
                
                Label { 
                    text: root.isEditing ? "Edit Resource" : "Add New Resource"
                    font.bold: true
                    font.pixelSize: 14
                    color: Theme.accent 
                }
                
                // Fields
                GridLayout {
                    columns: 2
                    rowSpacing: 10
                    columnSpacing: 10
                    Layout.fillWidth: true
                    
                    Label { text: "Label:" }
                    TheophanyTextField {
                        id: labelField
                        Layout.fillWidth: true
                        placeholderText: "e.g. Official Site, Walkthrough"
                    }
                    
                    Label { text: "URL / Path:" }
                    RowLayout {
                        Layout.fillWidth: true
                        TheophanyTextField {
                            id: urlField
                            Layout.fillWidth: true
                            placeholderText: "https://... or file path"
                            onTextChanged: {
                                // Auto-suggest label if empty
                                if (labelField.text === "") {
                                    if (text.includes("wikipedia.org")) labelField.text = "Wikipedia"
                                    else if (text.includes("mobygames.com")) labelField.text = "MobyGames"
                                    else if (text.includes("steam")) labelField.text = "Steam"
                                    else if (text.includes("gog.com")) labelField.text = "GOG"
                                }
                            }
                        }
                        TheophanyButton {
                            text: "📁" 
                            Layout.preferredWidth: 30
                            onClicked: fileDialog.open()
                            tooltipText: "Browse Local File"
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    
                    Item { Layout.fillWidth: true }
                    
                    TheophanyButton {
                        text: "Close"
                        onClicked: root.close()
                    }
                    
                    TheophanyButton {
                        text: "Cancel"
                        visible: root.isEditing
                        onClicked: root.cancelEdit()
                    }

                    TheophanyButton {
                        text: root.isEditing ? "Update Resource" : "Add Resource"
                        primary: true
                        enabled: urlField.text !== "" && labelField.text !== ""
                        onClicked: {
                            var u = urlField.text
                            var l = labelField.text
                            var t = "Web"
                            
                            // Simple type inference
                            if (u.includes("youtube") || u.includes("vimeo")) t = "Video"
                            else if (u.startsWith("file") || u.includes(".pdf")) t = "Manual"
                            else if (u.includes("wikipedia")) t = "Wikipedia"
                            
                            if (root.isEditing) {
                                gameModel.updateGameResource(root.editingResourceId, t, u, l)
                            } else {
                                gameModel.addGameResource(root.gameId, t, u, l)
                            }
                            
                            root.resourcesChanged()
                            root.cancelEdit()
                            root.load(root.gameId)
                        }
                    }
                }
            }
        }
    }
    
    Platform.FileDialog {
        id: fileDialog
        onAccepted: {
            // Remove file:// prefix if present for cleaner display, backend handles it?
            // Models logic says "file://" for local, but raw path is okay too if we prepend later.
            // Let's store full URI "file:///..." if it comes that way, or just path.
            // Platform.FileDialog returns file:/// usually.
            urlField.text = file.toString()
        }
    }
}
