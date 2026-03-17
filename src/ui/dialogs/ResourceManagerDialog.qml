import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.platform 1.1 as Platform
import "../components"
import "../style"

Dialog {
    id: root
    width: Overlay.overlay ? Overlay.overlay.width * 0.7 : 800
    height: Overlay.overlay ? Overlay.overlay.height * 0.7 : 600
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
                model: DelegateModel {
                    id: visualModel
                    model: ListModel { id: resourceModel }
                    
                    delegate: DropArea {
                        id: delegateRoot
                        width: resListView.width
                        height: 44
                        keys: ["resource"]
                        
                        property int visualIndex: DelegateModel.itemsIndex

                        onEntered: (drag) => {
                            var from = drag.source.visualIndex
                            var to = delegateRoot.visualIndex
                            if (from !== to) {
                                visualModel.items.move(from, to)
                            }
                        }
                        
                        Rectangle {
                            id: contentRect
                            width: delegateRoot.width
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.secondaryBackground
                            radius: 4
                            border.color: Theme.border
                            
                            Drag.active: dragArea.drag.active
                            Drag.source: delegateRoot
                            Drag.keys: ["resource"]
                            
                            states: [
                                State {
                                    when: dragArea.drag.active
                                    ParentChange { target: contentRect; parent: resListView }
                                    AnchorChanges { target: contentRect; anchors.verticalCenter: undefined }
                                    PropertyChanges { target: contentRect; opacity: 0.8; z: 100 }
                                }
                            ]
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10
                                
                                // Drag Handle
                                Text {
                                    text: "☰"
                                    color: Theme.secondaryText
                                    font.pixelSize: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    
                                    MouseArea {
                                        id: dragArea
                                        anchors.fill: parent
                                        cursorShape: Qt.OpenHandCursor
                                        drag.target: contentRect
                                        drag.axis: Drag.YAxis
                                        onReleased: {
                                            // Re-anchor to let states reset cleanly
                                            var orderedIds = []
                                            for(var i = 0; i < visualModel.items.count; i++) {
                                                orderedIds.push(visualModel.items.get(i).model.id)
                                            }
                                            gameModel.saveResourceOrder(root.gameId, JSON.stringify(orderedIds))
                                            root.resourcesChanged()
                                        }
                                    }
                                }
                                
                                // Icon
                                Text {
                                    text: {
                                        var u = model.url.toLowerCase()
                                        var t = model.type.toLowerCase()
                                        
                                        if (u.includes("wikipedia.org")) return "🌐"
                                        if (u.includes("mobygames.com")) return "🎮"
                                        if (u.includes("steam")) return "🎮"
                                        if (u.includes("youtube.com") || u.includes("youtu.be")) return "▶\ufe0e"
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
                                
                                // Launch Button
                                TheophanyButton {
                                    text: "Launch"
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 24
                                    onClicked: {
                                        gameModel.launchResource(root.gameId, model.url)
                                    }
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
           
            urlField.text = file.toString()
        }
    }
}
