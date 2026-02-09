
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../style"
import Qt5Compat.GraphicalEffects

Dialog {
    id: root
    
    // Floating "Island" styling
    width: 600
    height: Math.min(contentLayout.implicitHeight + 40, 500)
    
    x: (parent.width - width) / 2
    y: parent.height * 0.15 // Top-ish of the screen
    
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    // No standard window decorations
    background: Rectangle {
        color: Theme.secondaryBackground
        radius: 12
        border.color: Theme.accent
        border.width: 1
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#60000000"
            radius: 24
            samples: 25
            verticalOffset: 8
        }
    }
    
    signal gameSelected(string romId)
    signal launchRequested(string romId)
    signal collectionSelected(string collectionId)
    signal playlistSelected(string playlistId)
    
    property var searchResults: []
    
    function handleResult(data, modifiers) {
        if (!data) return

        if (modifiers & Qt.ControlModifier && data.result_type === "game") {
            root.gameSelected(data.id)
        } else {
            if (data.result_type === "collection") {
                root.collectionSelected(data.id)
            } else if (data.result_type === "playlist") {
                root.playlistSelected(data.id)
            } else {
                root.launchRequested(data.id)
            }
        }
        root.close()
    }
    
    function show() {
        searchInput.text = ""
        root.searchResults = []
        root.open()
        searchInput.forceActiveFocus()
    }
    
    function performSearch(text) {

        if (text.length < 2) {
            root.searchResults = []
            return
        }
        

        var json = gameModel.globalSearch(text)

        try {
            root.searchResults = JSON.parse(json)
        } catch(e) {

            root.searchResults = []
        }
    }
    
    contentItem: ColumnLayout {
        id: contentLayout
        spacing: 15
        
        // Search Input
        TextField {
            id: searchInput
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            placeholderText: "Search Library..."
            font.pixelSize: 18
            color: Theme.text
            
            background: Rectangle {
                color: Theme.background
                radius: 8
                border.color: searchInput.activeFocus ? Theme.accent : Theme.border
            }
            
            onTextChanged: performSearch(text)
            
            Keys.onDownPressed: {
                if (resultList.count > 0) {
                    resultList.currentIndex = 0
                    resultList.forceActiveFocus()
                }
            }

            Keys.onReturnPressed: (event) => {
                if (root.searchResults.length > 0) {
                    handleResult(root.searchResults[0], event.modifiers)
                }
            }

            Keys.onEnterPressed: (event) => {
                if (root.searchResults.length > 0) {
                    handleResult(root.searchResults[0], event.modifiers)
                }
            }
            
            Keys.onEscapePressed: root.close()
        }
        
        // Results
        ListView {
            id: resultList
            visible: root.searchResults.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 400)
            clip: true
            ScrollBar.vertical: TheophanyScrollBar { 
                policy: resultList.visibleArea.heightRatio < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff 
                persistentVisibility: true
            }
            
            model: root.searchResults
            delegate: ItemDelegate {
                id: delegate
                width: ListView.view.width
                height: 50
                
                background: Rectangle {
                    color: delegate.highlighted ? Theme.accent : "transparent"
                    opacity: delegate.highlighted ? 0.3 : 0
                    radius: 6
                }
                
                contentItem: RowLayout {
                    spacing: 12
                    
                    // Icon
                    Image {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        source: modelData.icon || modelData.boxart
                        fillMode: Image.PreserveAspectFit
                        visible: source != ""
                    }
                    
                    // Text Info
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        
                        Text {
                            text: modelData.title
                            color: Theme.text
                            font.bold: true
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        
                        Text {
                            text: modelData.platform
                            color: Theme.secondaryText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    
                    // Launch Action Hint
                    Text {
                        text: "⏎ Launch"
                        color: Theme.secondaryText
                        font.pixelSize: 11
                        visible: delegate.highlighted
                    }
                    
                    // Select Action Hint
                    Text {
                        text: "Ctrl+⏎ View"
                        color: Theme.secondaryText
                        font.pixelSize: 11
                        visible: delegate.highlighted
                    }
                }
                
                highlighted: ListView.isCurrentItem
                
                onClicked: handleResult(modelData, Qt.NoModifier)
            }
            
            Keys.onEnterPressed: (event) => {
                if (currentItem) {
                    handleResult(model[currentIndex], event.modifiers)
                }
            }
            
            Keys.onReturnPressed: (event) => {
                if (currentItem) {
                    handleResult(model[currentIndex], event.modifiers)
                }
            }
            
            Keys.onUpPressed: decrementCurrentIndex()
            Keys.onDownPressed: incrementCurrentIndex()
            Keys.onEscapePressed: {
                searchInput.forceActiveFocus()
            }
        }
        
        // Hints
        RowLayout {
            Layout.fillWidth: true
            spacing: 20
            visible: root.searchResults.length === 0
            
            Text {
                text: "Start typing to search..."
                color: Theme.secondaryText
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
    
    // Dim background behind
    Overlay.modal: Rectangle {
        color: "#80000000"
    }
}
