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
    property bool suppressSave: false
    property var currentTargetFilters: null

    signal filterChanged()

    readonly property bool isFiltered: (genreBox.currentIndex > 0) || 
                                       (regionBox.currentIndex > 0) || 
                                       (developerBox.currentIndex > 0) || 
                                       (publisherBox.currentIndex > 0) || 
                                       (yearBox.currentIndex > 0) || 
                                       (ratingBox.currentIndex > 0) || 
                                       (installedButton.checked) ||
                                       (favButton.checked && (typeof window !== "undefined" ? window.currentPlatformId !== "favorites" : true)) ||
                                       (selectedTags.length > 0)

    function getFilterState() {
        return {
            genre: (genreBox.currentIndex > 0 && genreBox.currentText) ? genreBox.currentText : "All Genres",
            region: (regionBox.currentIndex > 0 && regionBox.currentText) ? regionBox.currentText : "All Regions",
            developer: (developerBox.currentIndex > 0 && developerBox.currentText) ? developerBox.currentText : "All Developers",
            publisher: (publisherBox.currentIndex > 0 && publisherBox.currentText) ? publisherBox.currentText : "All Publishers",
            year: (yearBox.currentIndex > 0 && yearBox.currentText) ? yearBox.currentText : "All Years",
            rating: ratingBox.currentIndex * 10,
            installed_only: installedButton.checked,
            favorites_only: (typeof window !== "undefined" && window.currentPlatformId === "favorites") ? false : favButton.checked,
            tags: selectedTags.slice()
        }
    }

    function setTargetFilters(f) {
        currentTargetFilters = f ? JSON.parse(JSON.stringify(f)) : null
        suppressSave = true

        var fObj = f || {}
        genreBox.currentIndex = 0
        regionBox.currentIndex = 0
        developerBox.currentIndex = 0
        publisherBox.currentIndex = 0
        yearBox.currentIndex = 0
        installedButton.checked = !!fObj.installed_only
        favButton.checked = (typeof window !== "undefined" && window.currentPlatformId === "favorites") || !!fObj.favorites_only
        selectedTags = (fObj.tags && Array.isArray(fObj.tags)) ? fObj.tags.slice() : []
        ratingBox.currentIndex = Math.max(0, Math.min(10, Math.floor((fObj.rating || 0) / 10)))

        refreshModels()

        suppressSave = false
    }

    function clearFilters() {
        suppressSave = true
        genreBox.currentIndex = 0
        regionBox.currentIndex = 0
        developerBox.currentIndex = 0
        publisherBox.currentIndex = 0
        yearBox.currentIndex = 0
        ratingBox.currentIndex = 0
        installedButton.checked = false
        favButton.checked = (typeof window !== "undefined" && window.currentPlatformId === "favorites")
        selectedTags = []
        currentTargetFilters = null
        suppressSave = false
        
        if (gameModel) {
            gameModel.clearAllSecondaryFilters()
            if (typeof window !== "undefined" && window.currentPlatformId === "favorites") {
                gameModel.setFavoritesOnly(true)
            }
        }
        root.filterChanged()
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
        currentTargetFilters = root.isFiltered ? root.getFilterState() : null
        root.filterChanged()
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
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
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
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
            }
        }

        // Genre Dropdown
        TheophanyComboBox {
            id: genreBox
            model: ["All Genres"]
            
            onActivated: {
                if (gameModel) gameModel.setGenreFilter(currentText)
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
            }
        }

        // Region Dropdown
        TheophanyComboBox {
            id: regionBox
            model: ["All Regions"]
            
            onActivated: {
                if (gameModel) gameModel.setRegionFilter(currentText)
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
            }
        }

        // Developer Dropdown
        TheophanyComboBox {
            id: developerBox
            model: ["All Developers"]
            
            onActivated: {
                if (gameModel) gameModel.setDeveloperFilter(currentText)
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
            }
        }

        // Publisher Dropdown
        TheophanyComboBox {
            id: publisherBox
            model: ["All Publishers"]
            
            onActivated: {
                if (gameModel) gameModel.setPublisherFilter(currentText)
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
            }
        }

        // Year Dropdown
        TheophanyComboBox {
            id: yearBox
            model: ["All Years"]
            
            onActivated: {
                if (gameModel) gameModel.setYearFilter(currentText)
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
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
                currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                root.filterChanged()
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
                            currentTargetFilters = root.isFiltered ? root.getFilterState() : null
                            root.filterChanged()
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
        if (!gameModel) return

        var targetGenre = (currentTargetFilters && currentTargetFilters.genre) ? currentTargetFilters.genre : "All Genres"
        var targetRegion = (currentTargetFilters && currentTargetFilters.region) ? currentTargetFilters.region : "All Regions"
        var targetDev = (currentTargetFilters && currentTargetFilters.developer) ? currentTargetFilters.developer : "All Developers"
        var targetPub = (currentTargetFilters && currentTargetFilters.publisher) ? currentTargetFilters.publisher : "All Publishers"
        var targetYear = (currentTargetFilters && currentTargetFilters.year) ? currentTargetFilters.year : "All Years"

        genreBox.model = gameModel.getGenres()
        regionBox.model = gameModel.getRegions()
        developerBox.model = gameModel.getDevelopers()
        publisherBox.model = gameModel.getPublishers()
        yearBox.model = gameModel.getYears()
        allTags = gameModel.getTags()

        var idx = genreBox.find(targetGenre)
        genreBox.currentIndex = idx >= 0 ? idx : 0
        if (idx < 0 && targetGenre !== "All Genres" && !suppressSave) {
            gameModel.setGenreFilter("All Genres")
            if (currentTargetFilters) currentTargetFilters.genre = "All Genres"
        }

        idx = regionBox.find(targetRegion)
        regionBox.currentIndex = idx >= 0 ? idx : 0
        if (idx < 0 && targetRegion !== "All Regions" && !suppressSave) {
            gameModel.setRegionFilter("All Regions")
            if (currentTargetFilters) currentTargetFilters.region = "All Regions"
        }

        idx = developerBox.find(targetDev)
        developerBox.currentIndex = idx >= 0 ? idx : 0
        if (idx < 0 && targetDev !== "All Developers" && !suppressSave) {
            gameModel.setDeveloperFilter("All Developers")
            if (currentTargetFilters) currentTargetFilters.developer = "All Developers"
        }

        idx = publisherBox.find(targetPub)
        publisherBox.currentIndex = idx >= 0 ? idx : 0
        if (idx < 0 && targetPub !== "All Publishers" && !suppressSave) {
            gameModel.setPublisherFilter("All Publishers")
            if (currentTargetFilters) currentTargetFilters.publisher = "All Publishers"
        }

        idx = yearBox.find(targetYear)
        yearBox.currentIndex = idx >= 0 ? idx : 0
        if (idx < 0 && targetYear !== "All Years" && !suppressSave) {
            gameModel.setYearFilter("All Years")
            if (currentTargetFilters) currentTargetFilters.year = "All Years"
        }

        currentTargetFilters = root.isFiltered ? root.getFilterState() : null
    }

    function selectRegion(name) {
        if (!regionBox.model) return
        var idx = regionBox.model.indexOf(name)
        regionBox.currentIndex = idx >= 0 ? idx : 0
        if (gameModel) gameModel.setRegionFilter(regionBox.currentText)
        currentTargetFilters = root.isFiltered ? root.getFilterState() : null
        root.filterChanged()
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
            currentTargetFilters = root.isFiltered ? root.getFilterState() : null
            root.filterChanged()
        }
    }
}
