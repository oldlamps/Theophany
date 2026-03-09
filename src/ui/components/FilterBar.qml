import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../style"

Rectangle {
    id: root
    implicitHeight: flowLayout.childrenRect.height + 24
    
    color: Qt.rgba(Theme.secondaryBackground.r, Theme.secondaryBackground.g, Theme.secondaryBackground.b, 0.85)
    
    property var gameModel: null
    property alias genreBox: genreBox
    property alias regionBox: regionBox
    property alias developerBox: developerBox
    property alias publisherBox: publisherBox
    property alias yearBox: yearBox
    property alias ratingBox: ratingBox
    property alias installedButton: installedButton
    property alias favButton: favButton
    property var selectedTags: []
    property var allTags: []

    signal filterChanged()

    readonly property bool isFiltered: (genreBox.currentIndex > 0) || 
                                       (regionBox.currentIndex > 0) || 
                                       (developerBox.currentIndex > 0) || 
                                       (publisherBox.currentIndex > 0) || 
                                       (yearBox.currentIndex > 0) || 
                                       (ratingBox.currentIndex > 0) || 
                                       (installedButton.checked) ||
                                       (favButton.checked) ||
                                       (selectedTags.length > 0)

    function clearFilters() {
        genreBox.currentIndex = 0
        regionBox.currentIndex = 0
        developerBox.currentIndex = 0
        publisherBox.currentIndex = 0
        yearBox.currentIndex = 0
        ratingBox.currentIndex = 0
        installedButton.checked = false
        favButton.checked = false
        selectedTags = []
        
        if (gameModel) {
            gameModel.setGenreFilter("All Genres")
            gameModel.setRegionFilter("All Regions")
            gameModel.setDeveloperFilter("All Developers")
            gameModel.setPublisherFilter("All Publishers")
            gameModel.setYearFilter("All Years")
            gameModel.setRatingFilter(0)
            gameModel.setInstalledOnly(false)
            gameModel.setFavoritesOnly(false)
            gameModel.clearTagFilters()
        }
    }

    function toggleTag(tag, active) {
        var tags = selectedTags
        if (active) {
            if (tags.indexOf(tag) === -1) {
                tags.push(tag)
            }
        } else {
            var idx = tags.indexOf(tag)
            if (idx >= 0) {
                tags.splice(idx, 1)
            }
        }
        selectedTags = tags.slice() // Trigger re-evaluation
        if (gameModel) gameModel.setTagFilter(tag, active)
    }

    Flow {
        id: flowLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        anchors.topMargin: 12
        spacing: 12

        // All filters moved to Top Bar or added here

        // Installed Toggle
        TheophanyButton {
            id: installedButton
            checkable: true
            text: "💾"
            font.pixelSize: 18
            primary: checked
            tooltipText: checked ? "Show All Games" : "Show Installed Only"
            
            onClicked: {
                if (gameModel) gameModel.setInstalledOnly(checked)
            }
        }

        // Favorites Toggle
        TheophanyButton {
            id: favButton
            checkable: true
            text: "❤"
            font.pixelSize: 18
            primary: checked
            
            onClicked: {
                if (gameModel) gameModel.setFavoritesOnly(checked)
            }
        }

        // Genre Dropdown
        TheophanyComboBox {
            id: genreBox
            model: ["All Genres"]
            
            onActivated: {
                if (gameModel) gameModel.setGenreFilter(currentText)
            }
            
            Component.onCompleted: {
                if (gameModel) {
                    model = gameModel.getGenres()
                }
            }
        }

        // Region Dropdown
        TheophanyComboBox {
            id: regionBox
            model: ["All Regions"]
            
            onActivated: {
                if (gameModel) gameModel.setRegionFilter(currentText)
            }
            
            Component.onCompleted: {
                if (gameModel) {
                    model = gameModel.getRegions()
                }
            }
        }

        // Developer Dropdown
        TheophanyComboBox {
            id: developerBox
            model: ["All Developers"]
            
            onActivated: {
                if (gameModel) gameModel.setDeveloperFilter(currentText)
            }
            
            Component.onCompleted: {
                if (gameModel) {
                    model = gameModel.getDevelopers()
                }
            }
        }

        // Publisher Dropdown
        TheophanyComboBox {
            id: publisherBox
            model: ["All Publishers"]
            
            onActivated: {
                if (gameModel) gameModel.setPublisherFilter(currentText)
            }
            
            Component.onCompleted: {
                if (gameModel) {
                    model = gameModel.getPublishers()
                }
            }
        }

        // Year Dropdown
        TheophanyComboBox {
            id: yearBox
            model: ["All Years"]
            
            onActivated: {
                if (gameModel) gameModel.setYearFilter(currentText)
            }
            
            Component.onCompleted: {
                if (gameModel) {
                    model = gameModel.getYears()
                }
            }
        }

        // Min Rating (1-10 scale)
        TheophanyComboBox {
            id: ratingBox
            model: ["Any Rating", "1+", "2+", "3+", "4+", "5+", "6+", "7+", "8+", "9+", "10"]
            onActivated: {
                if (gameModel) {
                    // Map "Any Rating" to 0, "1+" to 10, "2+" to 20, etc.
                    // Rust divides by 10.0 for the f32 comparison (e.g., 10 -> 1.0)
                    gameModel.setRatingFilter(index * 10)
                }
            }
        }

        // Tags Button & Popover
        TheophanyButton {
            id: tagsButton
            text: selectedTags.length > 0 ? "Tags (" + selectedTags.length + ") ▼" : "Tags ▼"
            primary: selectedTags.length > 0
            onClicked: tagPopup.open()
            
            Popup {
                id: tagPopup
                y: tagsButton.height + 5
                width: 250
                height: 350
                padding: 10
                background: Rectangle {
                    color: Theme.background
                    border.color: Theme.accent
                    border.width: 1
                    radius: 4
                }
                
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8
                    
                    TheophanyTextField {
                        id: tagSearch
                        Layout.fillWidth: true
                        placeholderText: "Search tags..."
                        onTextChanged: tagList.model = root.allTags.filter(t => t.toLowerCase().includes(text.toLowerCase()))
                    }
                    
                    ListView {
                        id: tagList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.allTags
                        spacing: 2
                        
                        delegate: Item {
                            width: tagList.width
                            height: 30
                            
                            RowLayout {
                                anchors.fill: parent
                                spacing: 10
                                
                                TheophanyCheckBox {
                                    id: cb
                                    checked: root.selectedTags.indexOf(modelData) >= 0
                                    onToggled: root.toggleTag(modelData, checked)
                                }
                                
                                Text {
                                    text: modelData
                                    color: Theme.text
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.toggleTag(modelData, !cb.checked)
                                    }
                                }
                            }
                        }
                    }
                    
                    TheophanyButton {
                        text: "Clear Tags"
                        Layout.fillWidth: true
                        visible: selectedTags.length > 0
                        onClicked: {
                            root.selectedTags = []
                            if (gameModel) gameModel.clearTagFilters()
                            tagPopup.close()
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: gameModel
        function onFilterOptionsChanged() {
            refreshModels()
        }
    }
    
    function refreshModels() {
        if (gameModel) {
            var oldGenre = genreBox.currentText
            var oldRegion = regionBox.currentText
            var oldDev = developerBox.currentText
            var oldPub = publisherBox.currentText
            var oldYear = yearBox.currentText

            genreBox.model = gameModel.getGenres()
            regionBox.model = gameModel.getRegions()
            developerBox.model = gameModel.getDevelopers()
            publisherBox.model = gameModel.getPublishers()
            yearBox.model = gameModel.getYears()
            allTags = gameModel.getTags()

            // Restore selections if they still exist in the new models
            var idx = genreBox.find(oldGenre)
            if (idx >= 0) genreBox.currentIndex = idx
            
            idx = regionBox.find(oldRegion)
            if (idx >= 0) regionBox.currentIndex = idx
            
            idx = developerBox.find(oldDev)
            if (idx >= 0) developerBox.currentIndex = idx
            
            idx = publisherBox.find(oldPub)
            if (idx >= 0) publisherBox.currentIndex = idx
            
            idx = yearBox.find(oldYear)
            if (idx >= 0) yearBox.currentIndex = idx
        }
    }

    function selectRegion(name) {
        if (!regionBox.model) return
        var idx = regionBox.model.indexOf(name)
        if (idx >= 0) {
            regionBox.currentIndex = idx
        } else {
            regionBox.currentIndex = 0
        }
    }

    function selectGenre(name) {
        if (!genreBox.model) return
        var idx = -1
        for (var i = 0; i < genreBox.model.length; i++) {
            if (genreBox.model[i].toLowerCase() === name.toLowerCase()) {
                idx = i
                break
            }
        }
        
        if (idx >= 0) {
            genreBox.currentIndex = idx
            if (gameModel) gameModel.setGenreFilter(genreBox.model[idx])
        }
    }
}
