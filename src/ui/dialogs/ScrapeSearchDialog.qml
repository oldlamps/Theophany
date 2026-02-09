import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    width: 900 // Increased width for tabs and larger image grid
    height: 700
    title: "Scrape Online"
    modal: true
    header: null
    standardButtons: Dialog.NoButton

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 8

        // Premium subtle glow
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }

    property string query: ""
    property string platform: ""
    property string targetCategory: "Box - Front" // Default category for image search text
    property string ollamaUrl: ""
    property string ollamaModel: ""
    property string geminiKey: ""
    property string openaiKey: ""
    property string llmProvider: ""
    property alias currentTab: stackLayout.currentIndex
    property bool searching: false
    property bool fetchingDetails: false
    
    property string preferredScraper: "IGDB"
    property string preferredImageScraper: "Web Search"
    
    // Signals for different actions
    signal resultSelected(string sourceId, string provider)
    signal imageSelected(string url, string category)

    onOpened: {
        // Init logic

        if (root.query !== "") {
             metaSearchInput.text = root.query
             // Append platform to image search query for better results
             imgSearchInput.text = (root.platform !== "" && root.platform !== "Unknown") ? (root.query + " " + root.platform) : root.query
        }
        
        // Sync with preferred metadata scraper
        var metaIdx = metaProviderBox.find(root.preferredScraper)
        if (metaIdx >= 0) metaProviderBox.currentIndex = metaIdx
        
        // Sync with preferred image scraper
        var imgIdx = imgProviderBox.find(root.preferredImageScraper)
        if (imgIdx >= 0) imgProviderBox.currentIndex = imgIdx
        else if (root.preferredImageScraper === "Web Search") imgProviderBox.currentIndex = imgProviderBox.find("Web Search")
    }

    function showToast(message, isError) {
        mstText.text = message
        toast.toastError = isError
        toast.opacity = 1
        toastTimer.restart()
    }

    function startMetaSearch() {


        
        metadataModel.clear()
        if (metaSearchInput.text.trim() !== "") {
            root.searching = true
            gameModel.searchOnline(metaSearchInput.text, root.platform, metaProviderBox.currentText, root.ollamaUrl, root.ollamaModel, root.geminiKey, root.openaiKey, root.llmProvider)
        }
    }
    
    function startImageSearch() {
        imageModel.clear()
        if (imgSearchInput.text.trim() !== "") {
            root.searching = true
            // Use Web Search for images as it's the most reliable source for game art
            gameModel.searchOnline(imgSearchInput.text, root.platform, "Web Search", root.ollamaUrl, root.ollamaModel, root.geminiKey, root.openaiKey, root.llmProvider)
        }
    }

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
        spacing: 0

        // Custom Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                
                Label {
                    text: "Scrape Online"
                    color: Theme.text
                    font.pixelSize: 18
                    font.bold: true
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
            
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
        
        // --- Sidebar ---
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 200
            color: Theme.background
            
            ColumnLayout {
                anchors.fill: parent
                spacing: 2
                
                Label {
                    text: "MODE"
                    color: Theme.secondaryText
                    font.pixelSize: 11
                    font.bold: true
                    Layout.leftMargin: 15
                    Layout.topMargin: 20
                    Layout.bottomMargin: 10
                }

                Repeater {
                    model: ["Metadata", "Images", "Other"]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        color: stackLayout.currentIndex === index ? Theme.secondaryBackground : "transparent"
                        
                        Rectangle {
                            anchors.left: parent.left
                            width: 3
                            height: parent.height
                            color: Theme.accent
                            visible: stackLayout.currentIndex === index
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: stackLayout.currentIndex === index ? Theme.text : Theme.secondaryText
                            font.bold: stackLayout.currentIndex === index
                            font.pixelSize: 14
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stackLayout.currentIndex = index
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
            }
        }
        
        Rectangle { width: 1; Layout.fillHeight: true; color: Theme.border }

        // --- Content ---
        StackLayout {
            id: stackLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 0
            
            // --- TAB 1: METADATA ---
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 15
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        TheophanyTextField {
                            id: metaSearchInput
                            Layout.fillWidth: true
                            text: root.query
                            placeholderText: "Search metadata..."
                            onAccepted: root.startMetaSearch()
                        }
                        TheophanyComboBox {
                            id: metaProviderBox
                            model: gameModel.getAvailableScrapers()
                            Layout.preferredWidth: 200
                        }
                        TheophanyButton {
                            text: "Search"
                            primary: true
                            onClicked: root.startMetaSearch()
                        }
                    }
                    
                    ListView {
                        id: resultsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: metadataModel
                        spacing: 8
                        
                        delegate: ItemDelegate {
                            width: resultsList.width
                            height: 70
                            
                            background: Rectangle {
                                color: parent.hovered ? Theme.hover : Theme.background
                                radius: 4
                            }
                            
                            contentItem: RowLayout {
                                spacing: 15
                                
                                Rectangle {
                                    Layout.preferredWidth: 45
                                    Layout.preferredHeight: 60
                                    color: Theme.secondaryBackground
                                    radius: 2
                                    Image {
                                        anchors.fill: parent
                                        source: model.thumbnailUrl || ""
                                        fillMode: Image.PreserveAspectFit
                                        visible: model.thumbnailUrl && model.thumbnailUrl !== ""
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { 
                                        text: model.title
                                        color: Theme.text
                                        font.bold: true
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text { 
                                        text: (model.platform ? model.platform : "Unknown Platform") + (model.releaseYear ? " (" + model.releaseYear + ")" : "")
                                        color: Theme.secondaryText
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                Item { Layout.fillWidth: true }
                                
                                TheophanyButton {
                                    text: "Import"
                                    onClicked: {
                                        root.resultSelected(model.sourceId, metaProviderBox.currentText)
                                        // fetchOnlineMetadata is called by Main.qml usually via this signal
                                    }
                                }
                            }
                        }
                        
                        ScrollBar.vertical: ScrollBar { }
                        
                        // Loading Overlay
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.alpha(Theme.background, 0.7)
                            visible: root.searching && stackLayout.currentIndex === 0
                            
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                BusyIndicator {
                                    id: metaBusy
                                    Layout.alignment: Qt.AlignHCenter
                                    running: parent.parent.visible
                                }
                                Text {
                                    text: "Searching Metadata..."
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                        
                        // Waiting for Details Overlay
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.alpha(Theme.background, 0.7)
                            visible: root.fetchingDetails
                            z: 10
                            
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                BusyIndicator {
                                    id: fetchBusy
                                    Layout.alignment: Qt.AlignHCenter
                                    running: parent.parent.visible
                                }
                                Text {
                                    text: "Fetching Metadata..."
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: metaSearchInput.text === "" ? "Enter a query to search metadata" : "No results found for \"" + metaSearchInput.text + "\""
                            color: Theme.secondaryText
                            visible: !root.searching && resultsList.count === 0
                        }
                    }
                }
            }
            
            // --- TAB 2: IMAGES ---
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 15
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        TheophanyTextField {
                            id: imgSearchInput
                            Layout.fillWidth: true
                            text: root.query
                            placeholderText: "Search images..."
                            onAccepted: root.startImageSearch()
                        }
                        TheophanyComboBox {
                            id: imgProviderBox
                            model: ["Web Search"] // Default and currently only separate image search logic
                            currentIndex: 0
                            Layout.preferredWidth: 150
                            enabled: false // Lock to Web Search for now as requested default
                        }
                        TheophanyButton {
                            text: "Find Images"
                            primary: true
                            onClicked: root.startImageSearch()
                        }
                    }
                    
                    GridView {
                        id: imageGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: 220 // Larger box
                        cellHeight: 220
                        model: imageModel
                        
                        delegate: ItemDelegate {
                            width: imageGrid.cellWidth
                            height: imageGrid.cellHeight
                            
                            contentItem: ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8
                                
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: Theme.background
                                    border.color: parent.hovered ? Theme.accent : Theme.border
                                    border.width: parent.hovered ? 2 : 1
                                    radius: 4
                                    clip: true
                                    
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        source: model.thumbnailUrl || "" // Use thumbnail for grid
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    
                                    // Resolution Badge
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.right: parent.right
                                        width: resText.width + 10
                                        height: 18
                                        color: Qt.rgba(0, 0, 0, 0.8)
                                        
                                        Text {
                                            id: resText
                                            anchors.centerIn: parent
                                            text: model.resolution || "Unknown"
                                            color: "white"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }
                                
                                RowLayout {
                                    Layout.fillWidth: true
                                    TheophanyButton {
                                        text: "Use Image"
                                        Layout.fillWidth: true
                                        onClicked: {
                                            // sourceId is the full URL for Web Search
                                            categorySelectDialog.pendingUrl = model.sourceId
                                            
                                            // Set default if valid
                                            var idx = categoryCombo.find(root.targetCategory)
                                            if (idx >= 0) categoryCombo.currentIndex = idx
                                            
                                            categorySelectDialog.open()
                                        }
                                    }
                                }
                            }
                        }
                        ScrollBar.vertical: ScrollBar { }
                        
                        // Loading Overlay
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.alpha(Theme.background, 0.7)
                            visible: root.searching && stackLayout.currentIndex === 1
                            
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                BusyIndicator {
                                    id: imgBusy
                                    Layout.alignment: Qt.AlignHCenter
                                    running: parent.parent.visible
                                }
                                Text {
                                    text: "Searching Images..."
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: imgSearchInput.text === "" ? "Search for images to see results" : "No images found for \"" + imgSearchInput.text + "\""
                            color: Theme.secondaryText
                            visible: !root.searching && imageModel.count === 0
                        }
                    }
                }
            }
            
            // --- TAB 3: OTHER ---
             Item {
                Text {
                    anchors.centerIn: parent
                    text: "Other Options (Placeholders)"
                    color: Theme.secondaryText
                }
            }
        }
    }
    }

    Rectangle {
        id: toast
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 30
        width: Math.min(mstText.implicitWidth + 40, root.width - 40)
        height: Math.max(40, mstText.implicitHeight + 20)
        radius: 20
        color: toastError ? "#D32F2F" : "#388E3C"
        opacity: 0
        visible: opacity > 0
        z: 100

        property bool toastError: false

        Label {
            id: mstText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.width - 80)
            text: ""
            color: "white"
            font.bold: true
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Timer {
        id: toastTimer
        interval: 3000
        onTriggered: toast.opacity = 0
    }

    ListModel { id: metadataModel }
    ListModel { id: imageModel }
    
    // Timer to poll for Rust async responses
    Timer {
         interval: 100; repeat: true; running: true
         onTriggered: gameModel.checkAsyncResponses()
    }

    // Category Selection Popup
    Dialog {
        id: categorySelectDialog
        title: "Select Image Category"
        width: 350
        height: 250
        modal: true
        header: null
        standardButtons: Dialog.NoButton
        
        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.border
            radius: 12
        }

        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        
        property string pendingUrl: ""
        
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20
            
            Label {
                text: "Select Image Category"
                color: Theme.text
                font.pixelSize: 18
                font.bold: true
            }

            Label {
                text: "Where should this image be saved?"
                color: Theme.secondaryText
                font.pixelSize: 14
            }
            
            TheophanyComboBox {
                id: categoryCombo
                Layout.fillWidth: true
                model: [
                    "Icon",
                    "Box - Front",
                    "Box - Back",
                    "Screenshot",
                    "Banner",
                    "Clear Logo",
                    "Background"
                ]
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                TheophanyButton {
                    text: "Cancel"
                    Layout.fillWidth: true
                    onClicked: categorySelectDialog.reject()
                }
                TheophanyButton {
                    text: "Save"
                    primary: true
                    Layout.fillWidth: true
                    onClicked: categorySelectDialog.accept()
                }
            }
        }
        
        onAccepted: {
            root.imageSelected(pendingUrl, categoryCombo.currentText)
        }
    }

    Connections {
        target: gameModel
        function onSearchFinished(json) {
            root.searching = false
            try {
                var results = JSON.parse(json)
                var targetModel = (stackLayout.currentIndex === 1) ? imageModel : metadataModel
                targetModel.clear()
                
                for (var i = 0; i < results.length; i++) {
                    targetModel.append({
                        sourceId: results[i].id,
                        title: results[i].title,
                        platform: results[i].platform || "",
                        releaseYear: results[i].release_year || 0,
                        thumbnailUrl: results[i].thumbnail_url || "",
                        resolution: results[i].resolution || ""
                    })
                }
            } catch (e) {

            }
        }
        
        function onAssetDownloadFinished(category, path) {
             root.showToast("Saved " + category, false)
             categorySelectDialog.close()
        }
        
        function onAssetDownloadFailed(category, message) {
             root.showToast("Failed to save " + category + ": " + message, true)
             categorySelectDialog.close()
        }
    }
}
}
