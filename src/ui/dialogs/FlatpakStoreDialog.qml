import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Flatpak Store"
    modal: true
    width: Overlay.overlay ? Overlay.overlay.width * 0.8 : 1000
    height: Overlay.overlay ? Overlay.overlay.height * 0.8 : 700
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null
    
    property bool loading: false
    property string currentCategory: "Featured"
    property string activeSearch: ""
    property int previousViewIndex: 0
    property string targetPlatformId: ""

    ListModel { id: storeModel }
    ListModel { id: trendingModel }
    ListModel { id: popularModel }
    ListModel { id: newModel }
    
    // For featured app of the day
    property var featuredApp: null

    ListModel { id: filteredModel }
    ListModel { id: filteredPlatforms }
    
    ListModel {
        id: categoryModel
        ListElement { name: "Featured"; icon: "⭐"; filter: "Featured" }
        ListElement { name: "Action"; icon: "💥"; filter: "ActionGame" }
        ListElement { name: "Adventure"; icon: "🗺️"; filter: "AdventureGame" }
        ListElement { name: "Arcade"; icon: "🕹️"; filter: "ArcadeGame" }
        ListElement { name: "Board"; icon: "🎲"; filter: "BoardGame" }
        ListElement { name: "Card"; icon: "🃏"; filter: "CardGame" }
        ListElement { name: "Kids"; icon: "🎈"; filter: "KidsGame" }
        ListElement { name: "Logic"; icon: "🧩"; filter: "LogicGame" }
        ListElement { name: "Role Playing"; icon: "🛡️"; filter: "RolePlaying" }
        ListElement { name: "Shooter"; icon: "🔫"; filter: "Shooter" }
        ListElement { name: "Simulation"; icon: "✈️"; filter: "Simulation" }
        ListElement { name: "Sports"; icon: "⚽"; filter: "SportsGame" }
        ListElement { name: "Strategy"; icon: "🧠"; filter: "StrategyGame" }
        ListElement { name: "Emulators"; icon: "📀"; filter: "Emulator" }
    }

    function updateFilteredModel() {
        filteredModel.clear()
        for (var i = 0; i < storeModel.count; i++) {
            var item = storeModel.get(i)
            filteredModel.append(item)
        }
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        var targetIndex = -1
        var defaultFlatpakIndex = -1

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = sidebar.platformModel.data(idx, 261) || ""
            var id = sidebar.platformModel.data(idx, 256)
            
            if (type === "PC (Linux)") {
                filteredPlatforms.append({
                    "name": name,
                    "id": id
                })
                
                var newIndex = filteredPlatforms.count - 1
                if (id === root.targetPlatformId) {
                    targetIndex = newIndex
                }
                if (name === "Flatpak Games") {
                    defaultFlatpakIndex = newIndex
                }
            }
        }
        
        if (targetIndex !== -1) {
            platformSelector.currentIndex = targetIndex
        } else if (defaultFlatpakIndex !== -1) {
            platformSelector.currentIndex = defaultFlatpakIndex
        } else if (filteredPlatforms.count > 0) {
            platformSelector.currentIndex = 0
        } else {
            // Add virtual default if none found
            filteredPlatforms.insert(0, {
                "name": "Flatpak Games (Default)",
                "id": "virtual_flatpak"
            })
            platformSelector.currentIndex = 0
        }
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }
    StoreBridge {
        id: storeBridge
        onSearchFinished: (resultsJson) => {

            var results = JSON.parse(resultsJson)
            storeModel.clear()
            for (var i = 0; i < results.length; i++) {
                var res = results[i]
                // Convert sub_categories array to a list model compatible format
                var subCats = []
                if (res.subCategories) {
                    for (var j = 0; j < res.subCategories.length; j++) {
                        subCats.push({"value": res.subCategories[j]})
                    }
                }
                res.subCategories = subCats
                storeModel.append(res)
            }
            updateFilteredModel()
            
            // Switch view if not featured
            if (root.currentCategory !== "Featured") {
                mainStack.currentIndex = 1
            }
            
            root.loading = false
        }
        
        onFeaturedContentReceived: (json) => {

            try {
                var content = JSON.parse(json)
                
                // Helper to populate model
                function populate(model, list) {
                    model.clear()
                    if (!list) return
                    for (var i = 0; i < list.length; i++) {
                         var item = list[i]
                         // Ensure subCategories is list compatible
                         var subCats = []
                         if (item.subCategories) {
                             for (var j = 0; j < item.subCategories.length; j++) {
                                 subCats.push({"value": item.subCategories[j]})
                             }
                         }
                         item.subCategories = subCats
                         model.append(item)
                    }
                }

                root.featuredApp = content.appOfTheDay
                populate(trendingModel, content.trending)
                populate(popularModel, content.popular)
                populate(newModel, content.newReleases)
                
                // Ensure we are viewing the featured page
                mainStack.currentIndex = 0
            } catch (e) {

            }
            root.loading = false
        }

        onInstallProgress: (appId, progress, status) => {
            installOverlay.visible = true
            installOverlay.appId = appId
            installOverlay.progress = progress
            installOverlay.status = status
            
            // Update global state in Main.qml
            window.isFlatpakInstalling = true
            window.flatpakInstallAppId = appId
            window.flatpakInstallProgress = progress
            window.flatpakInstallStatus = status
        }
        onInstallFinished: (appId, success, message) => {
            installOverlay.visible = false
            
            // Clear global state
            window.isFlatpakInstalling = false
            window.flatpakInstallAppId = ""
            window.flatpakInstallProgress = 0.0
            window.flatpakInstallStatus = ""
            
            if (!success) {
                statusDialog.title = "Installation Error"
                statusDialog.text = "Failed to install " + appId + ":\n" + message
                statusDialog.open()
            } else {
                statusDialog.title = "Installation Successful"
                statusDialog.text = appId + " has been successfully installed and added to your library."
                statusDialog.open()
                gameModel.refresh() // Refresh library to show new game
            }
        }
        onAppDetailsReceived: (json) => {

             try {
                 var details = JSON.parse(json)
                 detailsView.details = details
             } catch (e) {

             }
             root.loading = false
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: storeBridge.poll()
    }

    onOpened: {

        root.loading = true
        root.currentCategory = "Featured"
        categoryList.currentIndex = 0
        root.activeSearch = ""
        searchField.text = ""
        refreshFilteredPlatforms()
        
        mainStack.currentIndex = 0 // Default to featured
        root.previousViewIndex = 0 // Reset history
        storeBridge.browse_store("Featured")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 25
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true
                Text {
                    text: "Flatpak Store"
                    font.bold: true
                    color: Theme.text
                    font.pixelSize: 28
                }
                Text {
                    text: "Discover and install Linux games from Flathub"
                    color: Theme.secondaryText
                    font.pixelSize: 14
                }
            }

            RowLayout {
                spacing: 8
                Text { text: "Install to:"; color: Theme.text; font.pixelSize: 13 }
                TheophanyComboBox {
                    id: platformSelector
                    Layout.preferredWidth: 220
                    model: filteredPlatforms
                    textRole: "name"
                }
                
                TheophanyButton {
                    text: "+"
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 32
                    onClicked: nameCollectionDialog.open()
                    tooltipText: "Create New Collection"
                }
            }

            RowLayout {
                Layout.preferredWidth: 250
                spacing: 0
                TheophanyTextField {
                    id: searchField
                    placeholderText: "Search Flathub..."
                    Layout.fillWidth: true
                    onTextChanged: {
                        if (text === "" && root.activeSearch !== "") {
                            root.activeSearch = ""
                            updateFilteredModel()
                        }
                    }
                    Keys.onReturnPressed: {
                        if (text !== "") {
                            root.loading = true
                            root.activeSearch = text
                            storeBridge.search_store(text)
                            mainStack.currentIndex = 1 // Switch to grid view for search
                        }
                    }
                }
                
                TheophanyButton {
                    visible: searchField.text !== ""
                    text: "✕"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    flat: true
                    onClicked: {
                        searchField.text = ""
                        root.activeSearch = ""
                        updateFilteredModel()
                    }
                }
            }

            TheophanyButton {
                text: "Search"
                primary: true
                onClicked: {
                    if (searchField.text !== "") {
                        root.loading = true
                        root.activeSearch = searchField.text
                        storeBridge.search_store(searchField.text)
                        mainStack.currentIndex = 1 // Switch to grid view for search
                    }
                }
            }

            TheophanyButton {
                text: "✕"
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                flat: true
                onClicked: root.close()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.3 }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Sidebar
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 200
                color: "transparent"
                
                ListView {
                    id: categoryList
                    anchors.fill: parent
                    anchors.rightMargin: 15
                    model: categoryModel
                    spacing: 5
                    clip: true
                    currentIndex: 0

                    delegate: Item {
                        width: parent.width
                        height: 40
                        
                        MouseArea {
                            id: catMa; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                categoryList.currentIndex = index
                                root.currentCategory = filter
                                root.activeSearch = ""
                                searchField.text = ""
                                
                                // Reset scroll positions
                                if (featuredScroll.ScrollBar.vertical) featuredScroll.ScrollBar.vertical.position = 0
                                grid.contentY = 0
                                
                                // Fetch new category from backend
                                root.loading = true
                                storeModel.clear() // Clear immediately to show loading state cleanly
                                storeBridge.browse_store(filter)
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: categoryList.currentIndex === index ? Theme.accent : (catMa.containsMouse ? Theme.hover : "transparent")
                            opacity: categoryList.currentIndex === index ? 1.0 : 0.6

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                spacing: 10
                                Text {
                                    text: icon
                                    color: Theme.text
                                    font.pixelSize: 16
                                }
                                Text {
                                    text: name
                                    color: Theme.text
                                    font.pixelSize: 14
                                    font.bold: categoryList.currentIndex === index
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillHeight: true
                width: 1
                color: Theme.border
                opacity: 0.2
            }

            // Content Container for Stack + Loading Overlay
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20

                StackLayout {
                    id: mainStack
                    anchors.fill: parent
                    currentIndex: 0
                
                // Index 0: Featured View
                ScrollView {
                    id: featuredScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth

                    // Hide if not on index 0 to prevent overlay issues/unnecessary rendering
                    visible: mainStack.currentIndex === 0

                    ColumnLayout {
                        width: parent.width - 30
                        spacing: 25
                        
                        // Hero Section (App of the Day) - Removed as per user request
                        
                        // Component for section header + horizontal carousel
                        component FeaturedSection : ColumnLayout {
                            property string title
                            property var modelData
                            
                            spacing: 10
                            Layout.fillWidth: true
                            
                            Text {
                                text: title
                                color: Theme.text
                                font.bold: true
                                font.pixelSize: 20
                            }
                            
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 210 // Increased to accommodate scrollbar

                                ListView {
                                    id: featuredList
                                    anchors.fill: parent
                                    anchors.bottomMargin: 10
                                    orientation: ListView.Horizontal
                                    spacing: 15
                                    clip: true
                                    model: modelData
                                    snapMode: ListView.SnapToItem
                                    
                                    ScrollBar.horizontal: TheophanyScrollBar {
                                        policy: ScrollBar.AsNeeded
                                        parent: featuredList.parent
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                    }
                                    
                                    delegate: Rectangle {
                                        width: 150
                                        height: 190
                                        color: hoverMa.containsMouse ? Theme.hover : Theme.background
                                        radius: 8
                                        border.color: Theme.border
                                        
                                        MouseArea {
                                            id: hoverMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                if (model.appId) {
                                                    root.loading = true
                                                    detailsView.appId = model.appId
                                                    detailsView.details = null
                                                    storeBridge.get_app_details(model.appId)
                                                    root.previousViewIndex = 0
                                                    mainStack.currentIndex = 2 // Details view
                                                }
                                            }
                                        }
                                        
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8
                                            
                                            Image {
                                                Layout.preferredWidth: 64
                                                Layout.preferredHeight: 64
                                                Layout.alignment: Qt.AlignHCenter
                                                source: model.iconUrl ? model.iconUrl : ""
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                            }
                                            
                                            Text {
                                                Layout.fillWidth: true
                                                text: model.name; 
                                                color: Theme.text
                                                font.bold: true
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                            }
                                            
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                text: model.summary
                                                color: Theme.secondaryText
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                wrapMode: Text.WordWrap
                                                elide: Text.ElideRight
                                                maximumLineCount: 3
                                            }
                                        }
                                    }
                                }

                                // Left Navigation Button
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -5
                                    width: 32; height: 64
                                    color: Theme.background
                                    radius: 8
                                    opacity: featuredList.contentX > 0 ? 0.8 : 0
                                    visible: opacity > 0
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "❮"
                                        color: Theme.text
                                        font.pixelSize: 20
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            featuredList.flick(1500, 0) // Flick right (scroll left)
                                        }
                                    }
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }

                                // Right Navigation Button
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -5
                                    width: 32; height: 64
                                    color: Theme.background
                                    radius: 8
                                    opacity: (featuredList.contentX + featuredList.width < featuredList.contentWidth) ? 0.8 : 0
                                    visible: opacity > 0
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "❯"
                                        color: Theme.text
                                        font.pixelSize: 20
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            featuredList.flick(-1500, 0) // Flick left (scroll right)
                                        }
                                    }
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }
                        }
                        
                        FeaturedSection {
                            title: "Trending Games"
                            modelData: trendingModel
                            visible: trendingModel.count > 0
                        }
                        
                        FeaturedSection {
                            title: "Most Popular"
                            modelData: popularModel
                            visible: popularModel.count > 0
                        }
                        
                        FeaturedSection {
                            title: "New Releases"
                            modelData: newModel
                            visible: newModel.count > 0
                        }
                        
                        Item { Layout.preferredHeight: 20 }
                    }
                }

                // Index 1: Grid View
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        id: grid
                        anchors.fill: parent
                        model: filteredModel
                        cellWidth: 240
                        cellHeight: 240
                        clip: true
                        visible: !root.loading && filteredModel.count > 0

                        ScrollBar.vertical: TheophanyScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: Item {
                            width: 230; height: 230

                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    root.loading = true
                                    detailsView.appId = appId
                                    detailsView.details = null // Clear previous
                                    storeBridge.get_app_details(appId)
                                    root.previousViewIndex = 1
                                    mainStack.currentIndex = 2 // Details view (Index 2 now)
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 5
                                color: ma.containsMouse ? Theme.hover : Theme.sidebar
                                radius: 12
                                border.color: ma.containsMouse ? Theme.accent : Theme.border
                                border.width: ma.containsMouse ? 2 : 1

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 15
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 80
                                        Layout.alignment: Qt.AlignHCenter
                                        color: "transparent"
                                        radius: 8
                                        
                                        Image {
                                            id: iconImg
                                            anchors.fill: parent
                                            source: iconUrl || ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            visible: status === Image.Ready
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "🎮"
                                            font.pixelSize: 48
                                            visible: iconImg.status !== Image.Ready
                                        }
                                    }

                                    Text {
                                        text: name
                                        color: Theme.text
                                        font.bold: true
                                        font.pixelSize: 15
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: summary
                                        color: Theme.secondaryText
                                        font.pixelSize: 11
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 3
                                        wrapMode: Text.WordWrap
                                        Layout.fillHeight: true
                                    }

                                    TheophanyButton {
                                        text: "Install"
                                        primary: true
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 32
                                        onClicked: {
                                            var idx = platformSelector.currentIndex
                                            if (idx < 0) {
                                                statusDialog.title = "No Collection Selected"
                                                statusDialog.text = "Please select or create a collection to install games into."
                                                statusDialog.open()
                                                return
                                            }
                                            var platformId = filteredPlatforms.get(idx).id
                                            
                                            // Handle on-demand creation of default collection
                                            if (platformId === "virtual_flatpak") {
                                                var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                                
                                                
                                                sidebar.platformModel.updateSystem(
                                                    newId, "Flatpak Games", "*.desktop", "%ROM%", "", "PC (Linux)", "assets/systems/flatpak", ""
                                                )
                                                
                                                storeBridge.install_app(appId, newId, name, summary, iconUrl || "", "", "[]", developer || "")
                                            } else {
                                                storeBridge.install_app(appId, platformId, name, summary, iconUrl || "", "", "[]", developer || "")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !root.loading && filteredModel.count === 0 && mainStack.currentIndex === 0
                        spacing: 15
                        Text {
                            text: root.activeSearch !== "" ? "No games found for '" + root.activeSearch + "'." : "No games in this category."
                            color: Theme.secondaryText
                            font.pixelSize: 18
                            Layout.alignment: Qt.AlignHCenter
                        }
                        TheophanyButton {
                            text: "Reload Store"
                            onClicked: {
                                root.loading = true
                                storeBridge.browse_store("")
                            }
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                }

                // Index 2: Details View
                FlatpakDetailsView {
                    id: detailsView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    
                    onBackClicked: {
                        mainStack.currentIndex = root.previousViewIndex
                        detailsView.details = null
                    }
                    
                    onInstallClicked: (appId, name, summary, iconUrl, description, screenshotsJson, developer) => {
                         var idx = platformSelector.currentIndex
                         if (idx < 0) {
                             statusDialog.title = "No Collection Selected"
                             statusDialog.text = "Please select or create a collection to install games into."
                             statusDialog.open()
                             return
                         }
                         var platformId = filteredPlatforms.get(idx).id
                         
                         if (platformId === "virtual_flatpak") {
                            var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                            sidebar.platformModel.updateSystem(newId, "Flatpak Games", "*.desktop", "%ROM%", "", "PC (Linux)", "assets/systems/flatpak.png", "")
                            storeBridge.install_app(appId, newId, name, summary, iconUrl, description, screenshotsJson, developer)
                         } else {
                             storeBridge.install_app(appId, platformId, name, summary, iconUrl, description, screenshotsJson, developer)
                         }
                    }
                }
            } // End of mainStackLayout

            // Loading Overlay centered over both Featured and Grid views
            BusyIndicator {
                anchors.centerIn: parent
                // Show if loading and we are NOT on the details view (2)
                running: root.loading && mainStack.currentIndex !== 2
                visible: running
                z: 100
            }
        }
        }
    }

    Rectangle {
        id: installOverlay
        anchors.fill: parent
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.9)
        visible: false
        z: 10
        radius: 12

        property string appId: ""
        property real progress: 0.0
        property string status: ""

        ColumnLayout {
            anchors.centerIn: parent
            width: 300
            spacing: 20

            Text {
                text: "Installing " + installOverlay.appId
                color: Theme.text
                font.bold: true
                font.pixelSize: 18
                Layout.alignment: Qt.AlignHCenter
            }

            ProgressBar {
                Layout.fillWidth: true
                value: installOverlay.progress
            }

            Text {
                text: installOverlay.status
                color: Theme.secondaryText
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
            }
            
            TheophanyButton {
                text: "Close"
                visible: installOverlay.status.indexOf("Finished") !== -1 || installOverlay.status.indexOf("Failed") !== -1
                onClicked: installOverlay.visible = false
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Dialog {
        id: nameCollectionDialog
        title: "New Linux Collection"
        modal: true
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        standardButtons: Dialog.Ok | Dialog.Cancel
        
        onAccepted: {
            if (newNameField.text !== "") {
                var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                sidebar.platformModel.updateSystem(newId, newNameField.text, "*.desktop", "%ROM%", "", "PC (Linux)", "assets/systems/flatpak", "")
                refreshFilteredPlatforms()
                newNameField.text = ""
            }
        }

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.accent
            radius: 8
        }

        ColumnLayout {
            spacing: 15
            width: 300
            Text {
                text: "Enter a name for the new collection:"
                color: Theme.text
            }
            TheophanyTextField {
                id: newNameField
                Layout.fillWidth: true
                placeholderText: "e.g. Linux Games, Proton..."
                focus: true
            }
        }
    }

    TheophanyMessageDialog {
        id: statusDialog
        title: "Status"
        // buttons: Dialog.Ok // Default
    }
}
