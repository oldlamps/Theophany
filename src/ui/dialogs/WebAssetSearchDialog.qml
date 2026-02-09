import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../style"

Dialog {
    id: root
    width: 800
    height: 600
    title: "Web Search: " + targetCategory
    modal: true
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.Cancel

    property string gameId: ""
    property string targetCategory: ""
    property string initialQuery: ""
    
    // Returns the file path on success
    signal assetSelected(string localPath)

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    // State
    property bool searching: false

    onOpened: {
        searchInput.text = initialQuery
        startSearch()
    }

    function startSearch() {
        if (searchInput.text.trim() === "") return
        resultsModel.clear()
        searching = true
        gameModel.searchWebImages(searchInput.text)
    }

    contentItem: ColumnLayout {
        spacing: 15
        
        // Header / Search Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            TheophanyTextField {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: "Search images..."
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
            text: root.searching ? "Searching..." : (resultsModel.count === 0 ? "No results found." : "Select an image to download:")
            color: Theme.secondaryText
            font.pixelSize: 14
            visible: true
        }

        // Results Grid
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 160
            cellHeight: 180
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
                        
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#111"
                            clip: true
                            
                            Image {
                                anchors.fill: parent
                                source: "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMCIgaGVpZ2h0PSIyMCIgZmlsbC1vcGFjaXR5PSIwLjEiPjxyZWN0IHdpZHRoPSIxMCIgaGVpZ2h0PSIxMCIgLz48cmVjdCB4PSIxMCIgeT0iMTAiIHdpZHRoPSIxMCIgaGVpZ2h0PSIxMCIgLz48L3N2Zz4="
                                fillMode: Image.Tile
                                opacity: 0.3
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
                        
                        TheophanyButton {
                            text: "Use Image"
                            Layout.fillWidth: true
                            onClicked: {
                                root.searching = true
                                gameModel.downloadWebAsset(model.url, root.gameId, root.targetCategory)
                            }
                        }
                    }
                }
            }
            
            ScrollBar.vertical: TheophanyScrollBar {}
        }
    }
    
    Connections {
        target: gameModel
        
        function onWebSearchFinished(json) {
            root.searching = false
            try {
                var results = JSON.parse(json)
                resultsModel.clear()
                for (var i = 0; i < results.length; i++) {
                    resultsModel.append({
                        url: results[i].id, 
                        thumbnailUrl: results[i].thumbnail_url || results[i].id,
                        resolution: results[i].resolution || ""
                    })
                }
            } catch (e) {

            }
        }
        
        function onWebAssetDownloadFinished(category, localPath) {
             if (category === root.targetCategory) {
                root.searching = false
                root.assetSelected(localPath)
                root.close()
             }
        }
    }
}
