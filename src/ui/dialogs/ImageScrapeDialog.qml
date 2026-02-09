import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../style"

Dialog {
    id: root
    width: 650
    height: 700
    title: "Select Image for " + targetCategory
    modal: true
    standardButtons: Dialog.Cancel

    background: Rectangle {
        color: "#1e1e24"
        border.color: "#333"
        radius: 8
    }

    property string gameId: ""
    property string initialQuery: ""
    property string platform: ""
    property string targetCategory: "" // e.g. "Box - Front"

    signal resultSelected(string url)
    
    // Internal State
    // 0 = Search, 1 = Image Selection
    property int step: 0
    property string selectedSourceId: ""
    property string selectedProvider: ""

    onOpened: {
        step = 0
        searchInput.text = initialQuery
        imageResultsModel.clear()
        resultsModel.clear()
    }

    contentItem: ColumnLayout {
        spacing: 15
        
        // --- STEP 0: SEARCH ---
        ColumnLayout {
            visible: root.step === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TheophanyTextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: "Search game..."
                    onAccepted: root.startSearch()
                }
                TheophanyComboBox {
                    id: providerBox
                    model: ["LaunchBox", "Web Search"]
                    Layout.preferredWidth: 150
                }
                TheophanyButton {
                    text: "Search"
                    onClicked: root.startSearch()
                }
            }
            
            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: ListModel { id: resultsModel }
                
                delegate: ItemDelegate {
                    width: resultsList.width
                    height: 80
                    
                    contentItem: RowLayout {
                        spacing: 15
                        
                        // If it's a web search result, the "thumbnail" is the image and valid
                        // If it's a Launchbox/Moby result, it's a game poster
                        
                        Rectangle {
                            Layout.preferredWidth: parent.height * 0.8
                            Layout.fillHeight: true
                            color: "#222"
                            Image {
                                anchors.fill: parent
                                source: model.thumbnailUrl || ""
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: providerBox.currentText !== "Web Search" // Hide text details for image results if they are self-explanatory? No, keep title.
                            Text { 
                                text: model.title
                                color: "white"
                                font.bold: true
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                            Text { 
                                text: (model.platform || "") + (model.releaseYear ? " (" + model.releaseYear + ")" : "")
                                color: "#aaa"
                                font.pixelSize: 12
                                visible: text !== ""
                            }
                        }
                        
                        // For Web Search, just show the selected state or button
                        TheophanyButton {
                            text: providerBox.currentText === "Web Search" ? "Use Image" : "Select Game"
                            onClicked: {
                                if (providerBox.currentText === "Web Search") {
                                    // Direct selection
                                    // The ID is the URL
                                    root.resultSelected(model.sourceId)
                                    root.close()
                                } else {
                                    root.selectedSourceId = model.sourceId
                                    root.selectedProvider = providerBox.currentText
                                    root.fetchImages()
                                }
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar { }
            }
        }
        
        // --- STEP 1: IMAGE SELECTION ---
        ColumnLayout {
            visible: root.step === 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            
            RowLayout {
                TheophanyButton {
                    text: "← Back"
                    onClicked: root.step = 0
                }
                Label {
                    text: "Select " + root.targetCategory
                    color: "white"
                    font.bold: true
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // Currently Assigned Gallery
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.existingUrls.length > 0
                spacing: 5
                
                Label { 
                    text: "Currently Assigned:"
                    color: Theme.accent
                    font.pixelSize: 11
                    font.bold: true
                }
                
                Row {
                    spacing: 10
                    Repeater {
                        model: root.existingUrls
                        Rectangle {
                            width: 60; height: 60; radius: 4; color: "#111"
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: "file://" + modelData
                                fillMode: Image.PreserveAspectFit
                            }
                        }
                    }
                }
                
                Rectangle { Layout.fillWidth: true; height: 1; color: "#333"; Layout.topMargin: 5; Layout.bottomMargin: 5 }
            }
            
            GridView {
                id: imageGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 160
                cellHeight: 180
                model: ListModel { id: imageResultsModel }
                
                delegate: ItemDelegate {
                    width: imageGrid.cellWidth
                    height: imageGrid.cellHeight
                    
                    contentItem: ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#222"
                            border.color: parent.hovered ? "#ba00e0" : "#333"
                            border.width: parent.hovered ? 2 : 1
                            
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: model.url
                                fillMode: Image.PreserveAspectFit
                            }
                            
                            // Spinner/Loading indicator could go here
                        }
                        
                        TheophanyButton {
                            text: "Download"
                            Layout.fillWidth: true
                            onClicked: {
                                root.resultSelected(model.url)
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar { }
                
                Text {
                    anchors.centerIn: parent
                    text: "No images found for this category."
                    color: "#666"
                    visible: imageResultsModel.count === 0
                }
            }
        }
    }

    property var existingUrls: []
    
    function isDownloaded(url) {
        for (var i = 0; i < existingUrls.length; i++) {
            if (existingUrls[i] === url) return true
        }
        return false
    }

    function refreshExisting() {
        if (!root.gameId) return
        var json = gameModel.getGameMetadata(root.gameId)
        try {
            var data = JSON.parse(json)
            if (data.assets && data.assets[root.targetCategory]) {
                root.existingUrls = data.assets[root.targetCategory]
            } else {
                root.existingUrls = []
            }
        } catch(e) {}
    }

    onTargetCategoryChanged: refreshExisting()
    onGameIdChanged: refreshExisting()

    
    // SEARCH LOGIC
    function startSearch() {
        resultsModel.clear()
        if (searchInput.text.trim() !== "") {
            // Updated to correctly pass query, platform, and provider
            var searchPlatform = root.platform || ""
            gameModel.searchOnline(searchInput.text, searchPlatform, providerBox.currentText)
        }
    }
    
    // IMAGE FETCH LOGIC
    function fetchImages() {
        step = 1
        imageResultsModel.clear()
        // We reuse the generic "fetchOnlineMetadata" to get the full struct, 
        // then parse the assets list here locally.
        gameModel.fetchOnlineMetadata(root.selectedSourceId, root.selectedProvider)
    }
    
    Connections {
        target: gameModel
        
        function onSearchFinished(json) {
            if (root.visible && root.step === 0) {
                try {
                    var results = JSON.parse(json)
                    resultsModel.clear()
                    for (var i = 0; i < results.length; i++) {
                        resultsModel.append({
                            sourceId: results[i].id,
                            title: results[i].title,
                            platform: results[i].platform || "",
                            releaseYear: results[i].release_year || 0,
                            thumbnailUrl: results[i].thumbnail_url || ""
                        })
                    }
                } catch (e) { }
            }
        }
        
        function onFetchFinished(json) {
            if (root.visible && root.step === 1) {
                try {
                    var meta = JSON.parse(json)
                    imageResultsModel.clear()
                    
                    if (meta.assets && meta.assets[root.targetCategory]) {
                        var urls = meta.assets[root.targetCategory]
                        // It is now an array
                        for (var i = 0; i < urls.length; i++) {
                            imageResultsModel.append({ url: urls[i] })
                        }
                    }
                    root.refreshExisting()
                } catch (e) { }
            }
        }
        
        function onAssetDownloadFinished(category, localPath) {
            if (root.visible && category === root.targetCategory) {
                root.refreshExisting()
            }
        }
    }
}
