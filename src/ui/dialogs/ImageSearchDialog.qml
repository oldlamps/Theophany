import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../style"

Dialog {
    id: root
    anchors.centerIn: Overlay.overlay
    width: 900 // Slightly wider for game art
    height: 700
    title: "Search Asset Online"
    modal: true
    // x: (parent.width - width) / 2
    // y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    footer: null
    header: null
    
    property string gameId: ""
    property string initialQuery: ""
    property string assetType: ""    // e.g. "boxart", "screenshot"


    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }
    
    // Ensure responses are checked while this dialog is open (if using async Rust)
    Timer {
        interval: 100
        running: root.visible
        repeat: true
        onTriggered: {
            if (gameModel) gameModel.checkAsyncResponses()
        }
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
        if (gameModel) {
             gameModel.searchGameImages(searchInput.text)
        } else {

             searching = false
        }
    }

    contentItem: ColumnLayout {
        spacing: 15
        anchors.fill: parent
        anchors.margins: 20
        
        // Custom Header with Close Button
        RowLayout {
            Layout.fillWidth: true
            
            Text {
                text: "Search Online: " + formatAssetType(root.assetType)
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
            text: root.searching ? "Searching..." : (resultsModel.count === 0 ? "No results found." : "Click to download (Modal stays open for multiple selections)")
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
            cellWidth: 220
            cellHeight: 220
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
                        
                        // Image Container
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.secondaryBackground
                            clip: true
                            radius: 4
                            
                            // Checkerboard (optional, keep it simple for now)

                            Image {
                                anchors.fill: parent
                                source: model.thumbnailUrl
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            
                            // Download Indicator Overlay?
                            // For now just click
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
                    if (model.url && gameModel) {
                        // Trigger download - does not close modal
                        gameModel.downloadAsset(root.gameId, root.assetType, model.url)
                    }
                }
            }
            
            ScrollBar.vertical: TheophanyScrollBar {}
        }
    }
    
    // Connections to GameListModel
    Connections {
        target: gameModel
        ignoreUnknownSignals: true
        
        function onImagesSearchFinished(json) {
            root.searching = false
             try {
                var results = JSON.parse(json)
                resultsModel.clear()
                for (var i = 0; i < results.length; i++) {
                    resultsModel.append({
                        url: results[i].id, // Full URL
                        thumbnailUrl: results[i].thumbnail_url || results[i].id,
                        resolution: results[i].resolution || ""
                    })
                }
            } catch (e) {

            }
        }
        
        function onAssetDownloadFinished(type, path) {
            // Optional: Show a "toast" or success indicator?
            // checking type matches strictly in case we have multiple dialogs (unlikely but good practice)
            if (type === root.assetType) {
                // Success feedback

            }
        }
        
        function onAssetDownloadFailed(type, msg) {
             if (type === root.assetType) {

             }
        }
    }

    function formatAssetType(t) {
        if (t === "boxart") return "Box Front"
        if (t === "boxart_back") return "Box Back"
        if (t === "screenshot") return "Screenshot"
        if (t === "banner") return "Banner"
        if (t === "logo") return "Clear Logo"
        if (t === "background") return "Background"
        return t
    }
}
