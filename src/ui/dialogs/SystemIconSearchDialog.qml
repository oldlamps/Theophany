import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../style"

Dialog {
    id: root
    width: 800
    height: 600
    title: "Select System Icon"
    modal: true
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    footer: null
    header: null
    
    // ...

    property string initialQuery: ""
    property string activeSystemName: "" // For filename generation
    property var platformModel: null // Injected dependency
    
    // Returns the file path on success
    signal iconSelected(string iconPath)

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }
    
    // Ensure responses are checked while this dialog is open
    Timer {
        interval: 100
        running: root.visible
        repeat: true
        onTriggered: {
            if (platformModel) platformModel.checkAsyncResponses()
        }
    }

    // State
    property bool searching: false

    onOpened: {
        searchInput.text = initialQuery + " icon transparent" 
        startSearch()
    }

    function startSearch() {
        if (searchInput.text.trim() === "") return
        resultsModel.clear()
        searching = true
        if (platformModel) platformModel.searchSystemIcons(searchInput.text)
    }

    contentItem: ColumnLayout {
        spacing: 15
        anchors.fill: parent
        anchors.margins: 20
        
        // Custom Header with Close Button
        RowLayout {
            Layout.fillWidth: true
            
            Text {
                text: "Select System Icon"
                color: Theme.text
                font.bold: true
                font.pixelSize: 18
                Layout.fillWidth: true
            }
            
            Text {
                text: "✕"
                color: Theme.secondaryText
                font.pixelSize: 18
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.color = Theme.text
                    onExited: parent.color = Theme.secondaryText
                    onClicked: root.close()
                }
            }
        }
        
        // Search Bar
        RowLayout {
            // ... (existing search bar code)
            Layout.fillWidth: true
            spacing: 12
            
            TheophanyTextField {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: "Search query..."
                onAccepted: root.startSearch()
            }
            
            TheophanyButton {
                text: "Search"
                primary: true
                onClicked: root.startSearch()
            }
        }
        
        // Status
        Text {
            text: root.searching ? "Searching..." : (resultsModel.count === 0 ? "No results found." : "Select an image:")
            color: Theme.secondaryText
            font.pixelSize: 14
            visible: true
            Layout.alignment: Qt.AlignHCenter
        }

        // Results Grid
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 150
            cellHeight: 150
            model: ListModel { id: resultsModel }
            
            delegate: ItemDelegate {
                width: grid.cellWidth
                height: grid.cellHeight
                
                contentItem: Rectangle {
                    color: parent.hovered ? Theme.hover : "transparent"
                    radius: 8
                    border.color: parent.hovered ? Theme.accent : "transparent"
                    border.width: 2
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 5
                        
                        // Image Checkerboard background for transparency
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.secondaryBackground // Use theme secondaryBackground instead of #333
                            clip: true
                            radius: 4
                            
                            // Checkerboard pattern (simplified)
                            Image {
                                anchors.fill: parent
                                source: "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMCIgaGVpZ2h0PSIyMCIgZmlsbC1vcGFjaXR5PSIwLjEiPjxyZWN0IHdpZHRoPSIxMCIgaGVpZ2h0PSIxMCIgLz48cmVjdCB4PSIxMCIgeT0iMTAiIHdpZHRoPSIxMCIgaGVpZ2h0PSIxMCIgLz48L3N2Zz4="
                                fillMode: Image.Tile
                                opacity: 0.1 // Subtle
                            }

                            Image {
                                anchors.fill: parent
                                source: model.thumbnailUrl
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                        }
                        
                        Text {
                            text: model.resolution ? model.resolution : "Unknown"
                            color: Theme.secondaryText
                            font.pixelSize: 10
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
                
                onClicked: {
                    if (model.url) {
                        root.searching = true // Show loading state
                        if (platformModel) platformModel.downloadSystemIcon(model.url, root.activeSystemName)
                    }
                }
            }
            
            ScrollBar.vertical: TheophanyScrollBar {}
        }
    }
    
    // Connections to PlatformModel
    Connections {
        target: platformModel
        
        function onIconSearchFinished(json) {
            root.searching = false
            try {
                var results = JSON.parse(json)
                resultsModel.clear()
                for (var i = 0; i < results.length; i++) {
                    // Filter for better quality if possible?
                    // For now just show all
                    resultsModel.append({
                        url: results[i].id, // Full URL is in ID
                        thumbnailUrl: results[i].thumbnail_url || results[i].id,
                        resolution: results[i].resolution || ""
                    })
                }
            } catch (e) {

            }
        }
        
        function onIconDownloadFinished(localPath) {
            root.searching = false
            root.iconSelected(localPath)
            root.close()
        }
    }
}
