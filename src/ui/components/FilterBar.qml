import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../style"

Rectangle {
    id: root
    height: 50
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
    
    // property alias searchFieldRef: searchField // Removed, moving to Top Bar
    
    signal filterChanged()

    readonly property bool isFiltered: (genreBox.currentIndex > 0) || 
                                       (regionBox.currentIndex > 0) || 
                                       (developerBox.currentIndex > 0) || 
                                       (publisherBox.currentIndex > 0) || 
                                       (yearBox.currentIndex > 0) || 
                                       (ratingBox.currentIndex > 0) || 
                                       (installedButton.checked) ||
                                       (favButton.checked)

    function clearFilters() {
        genreBox.currentIndex = 0
        regionBox.currentIndex = 0
        developerBox.currentIndex = 0
        publisherBox.currentIndex = 0
        yearBox.currentIndex = 0
        ratingBox.currentIndex = 0
        installedButton.checked = false
        favButton.checked = false
        
        if (gameModel) {
            gameModel.setGenreFilter("All Genres")
            gameModel.setRegionFilter("All Regions")
            gameModel.setDeveloperFilter("All Developers")
            gameModel.setPublisherFilter("All Publishers")
            gameModel.setYearFilter("All Years")
            gameModel.setRatingFilter(0)
            gameModel.setInstalledOnly(false)
            gameModel.setFavoritesOnly(false)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        spacing: 15

        // All filters moved to Top Bar or added here

        // Genre Dropdown
        TheophanyComboBox {
            id: genreBox
            model: ["All Genres"]
            Layout.preferredWidth: 150
            Layout.preferredHeight: 35
            
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
            Layout.preferredWidth: 130
            Layout.preferredHeight: 35
            
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
            Layout.preferredWidth: 150
            Layout.preferredHeight: 35
            
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
            Layout.preferredWidth: 150
            Layout.preferredHeight: 35
            
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
            Layout.preferredWidth: 100
            Layout.preferredHeight: 35
            
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
            Layout.preferredWidth: 100
            Layout.preferredHeight: 35
            onActivated: {
                if (gameModel) {
                    // Map "Any Rating" to 0, "1+" to 10, "2+" to 20, etc.
                    // Rust divides by 10.0 for the f32 comparison (e.g., 10 -> 1.0)
                    gameModel.setRatingFilter(index * 10)
                }
            }
        }

        // Installed Toggle
        TheophanyButton {
            id: installedButton
            checkable: true
            text: "☁"
            font.pixelSize: 18
            Layout.preferredWidth: 40
            Layout.preferredHeight: 35
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
            Layout.preferredWidth: 40
            Layout.preferredHeight: 35
            primary: checked
            
            onClicked: {
                if (gameModel) gameModel.setFavoritesOnly(checked)
            }
        }

        Item { Layout.fillWidth: true }
    }

    Connections {
        target: gameModel
        function onFilterOptionsChanged() {
            refreshModels()
        }
    }
    
    function refreshModels() {
        if (gameModel) {
            genreBox.model = gameModel.getGenres()
            regionBox.model = gameModel.getRegions()
            developerBox.model = gameModel.getDevelopers()
            publisherBox.model = gameModel.getPublishers()
            yearBox.model = gameModel.getYears()
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
