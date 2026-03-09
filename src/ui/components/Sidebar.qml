import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import Theophany.Bridge 1.0
import "../style"

Rectangle {
    id: root
    color: Theme.sidebar
    border.color: Theme.border
    border.width: 1

    signal addSystemClicked()
    signal platformSelected(string platformId, string platformName, string platformIcon)
    signal editSystemRequested(string id, string name, string extensions, string command, string emuId, string pType, string icon, string pcConfig)
    signal systemDeleted()
    signal manageEmulatorsClicked()
    signal rescanRequested(string platformId)
    signal settingsRequested()
    signal addContentRequested()
    signal addContentToCollectionRequested(string platformId)
    signal platformTypeSelected(string platformType, string icon)
    signal managePlaylistsRequested()
    signal deleteCollectionRequested(string platformId, string platformName)

    property string activeViewType: "all" // all, favorites, recent, platform, playlist
    property string activeId: ""
    property int allGamesCount: 0
    property var deletingIds: ({})

    property var appSettings: null
    property var appSettingsRef: null
    
    property bool collapsed: appSettings ? appSettings.sidebarCollapsed : false
    onCollapsedChanged: {
        if (appSettings.sidebarCollapsed !== collapsed) {
            appSettings.sidebarCollapsed = collapsed
            appSettings.save()
        }
    }

    property bool libraryCollapsed: appSettings ? appSettings.sidebarLibraryCollapsed : false
    onLibraryCollapsedChanged: {
        if (appSettings && appSettings.sidebarLibraryCollapsed !== libraryCollapsed) {
            appSettings.sidebarLibraryCollapsed = libraryCollapsed
            appSettings.save()
        }
    }

    property bool collectionsCollapsed: appSettings ? appSettings.sidebarCollectionsCollapsed : false
    onCollectionsCollapsedChanged: {
        if (appSettings && appSettings.sidebarCollectionsCollapsed !== collectionsCollapsed) {
            appSettings.sidebarCollectionsCollapsed = collectionsCollapsed
            appSettings.save()
        }
    }

    property bool platformsCollapsed: appSettings ? appSettings.sidebarPlatformsCollapsed : false
    onPlatformsCollapsedChanged: {
        if (appSettings && appSettings.sidebarPlatformsCollapsed !== platformsCollapsed) {
            appSettings.sidebarPlatformsCollapsed = platformsCollapsed
            appSettings.save()
        }
    }

    property bool playlistsCollapsed: appSettings ? appSettings.sidebarPlaylistsCollapsed : false
    onPlaylistsCollapsedChanged: {
        if (appSettings && appSettings.sidebarPlaylistsCollapsed !== playlistsCollapsed) {
            appSettings.sidebarPlaylistsCollapsed = playlistsCollapsed
            appSettings.save()
        }
    }
    
    property alias platformModel: platformModel

    // Legacy functions for compatibility (could be updated later)
    function getSidebarItems() {
        var items = []
        
        // 1. Library Items
        items.push({type: "all", id: "", name: "All Games", icon: "🎮"})
        items.push({type: "favorites", id: "favorites", name: "Favorites", icon: "⭐"})
        items.push({type: "recent", id: "recent", name: "Recently Played", icon: "🕒"})
        
        // 2. Collections (Systems)
        for (var i = 0; i < platformModel.rowCount(); i++) {
             var idx = platformModel.index(i, 0)
             var pid = platformModel.data(idx, 256) // id
             var pname = platformModel.data(idx, 257) // name
             var picon = platformModel.data(idx, 262) // icon
             items.push({type: "platform", id: pid, name: pname, icon: picon})
        }
        
        // 3. Playlists
        for (var j = 0; j < playlistModel.rowCount(); j++) {
             var idx2 = playlistModel.index(j, 0)
             var plId = playlistModel.data(idx2, 256)
             var plName = playlistModel.data(idx2, 257)
             items.push({type: "playlist", id: plId, name: plName, icon: "📜"})
        }
        
        return items
    }

    function findCurrentIndex(items) {
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (activeViewType === "playlist") {
                 if (item.type === "playlist" && item.id === activeId) return i
            } else if (activeViewType === "platform") {
                 if (item.type === "platform" && item.id === activeId) return i
            } else if (activeViewType === "platformType") {
                 // activeId is name
                 if (item.type === "platformType" && item.id === activeId) return i
            } else {
                 if (item.type === activeViewType) return i
            }
        }
        return 0 // Default to first if not found
    }

    function selectSidebarItem(item) {
        if (!item) return
        
        root.activeViewType = item.type
        root.activeId = item.id
        
        if (item.type === "playlist") {
            root.platformSelected("playlist:" + item.id, item.name, item.icon)
        } else if (item.type === "platformType") {
             root.platformTypeSelected(item.id, item.icon)
        } else {
            root.platformSelected(item.id, item.name, item.icon)
        }
    }

    function nextPlatform() {
        var items = getSidebarItems()
        var idx = findCurrentIndex(items)
        var nextIdx = (idx + 1) % items.length
        selectSidebarItem(items[nextIdx])
    } 

    function prevPlatform() {
        var items = getSidebarItems()
        var idx = findCurrentIndex(items)
        var prevIdx = (idx - 1 + items.length) % items.length
        selectSidebarItem(items[prevIdx])
    }

    function ensureVisible(item) {
        if (!item || root.collapsed) return
        
        // Map item coordinates to scroll view content area
        var pos = item.mapToItem(scrollView.contentItem, 0, 0)
        var itemHeight = item.height
        
        // Calculate visible range
        var viewTop = scrollView.contentY
        var viewBottom = viewTop + scrollView.height
        
        // Scroll if out of view
        if (pos.y < viewTop) {
            scrollView.contentY = Math.max(0, pos.y - 10)
        } else if (pos.y + itemHeight > viewBottom) {
            scrollView.contentY = Math.min(scrollView.contentHeight - scrollView.height, pos.y + itemHeight - scrollView.height + 10)
        }
    }

    function selectPlatform(pid) {
        var items = getSidebarItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === pid) {
                selectSidebarItem(items[i])
                return
            }
        }
        // Fallback to All Games if not found
        if (items.length > 0) selectSidebarItem(items[0])
    }

    function selectPlaylist(pid) {
        var items = getSidebarItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].type === "playlist" && items[i].id === pid) {
                selectSidebarItem(items[i])
                return
            }
        }
    }

    function refresh() { platformModel.refresh(); playlistModel.refresh(); }
    function updateSystem(id, name, ext, cmd, emuId, pType, icon, pcConfig) { platformModel.updateSystem(id, name, ext, cmd, emuId, pType, icon, pcConfig) }

    property var platformTypes: []
    function setPlatformTypes(types) { platformTypes = types }

    // Models
    AppInfo { id: appInfo }
    
    PlatformListModel {
        id: platformModel
        Component.onCompleted: init(appInfo.getDataPath() + "/games.db")

        onDeleteProgress: (pid, progress, status) => {
            var d = JSON.parse(JSON.stringify(root.deletingIds))
            d[pid] = true
            root.deletingIds = d
        }

        onDeleteFinished: (pid, success, message) => {
            var d = root.deletingIds
            delete d[pid]
            root.deletingIds = Object.assign({}, d)

            if (root.activeViewType === "platform" && root.activeId == pid) {
                 root.activeViewType = "all"
                 root.activeId = ""
                 root.platformSelected("", "All Games", "🎮")
            }
        }
    }

    // Helper Component for Collapsable Sections
    component CollapsableSection : ColumnLayout {
        id: sectionRoot
        property string title
        property bool collapsed: false
        property bool isSidebarCollapsed: false
        property string headerActionIcon: ""
        property bool headerActionVisible: false
        property string headerActionTooltip: ""
        signal headerActionClicked()
        
        // Define where the children should go
        default property alias contentData: content.data
        
        spacing: 0
        Layout.fillWidth: true

        Item {
            id: headerContainer
            Layout.fillWidth: true
            Layout.preferredHeight: sectionRoot.isSidebarCollapsed ? 1 : 30
            Layout.leftMargin: 15
            Layout.rightMargin: 10
            visible: !sectionRoot.isSidebarCollapsed

            // Collapse toggle area (arrow + title only)
            MouseArea {
                id: collapseToggle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width - (actionButton.visible ? actionButton.width + 10 : 0)
                cursorShape: Qt.PointingHandCursor
                onClicked: sectionRoot.collapsed = !sectionRoot.collapsed
                
                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    Text {
                        text: sectionRoot.collapsed ? "▶\ufe0e" : "▼\ufe0e"
                        color: Theme.secondaryText
                        font.pixelSize: 8
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text { 
                        text: sectionRoot.title
                        color: Theme.secondaryText
                        font.pixelSize: 10
                        font.bold: true
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            // Action button ('+') - completely separate from toggle
            Text {
                id: actionButton
                visible: sectionRoot.headerActionVisible
                text: sectionRoot.headerActionIcon
                color: Theme.accent
                font.pixelSize: 14
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                
                MouseArea {
                    id: actionMa
                    anchors.fill: parent
                    anchors.margins: -8 // Larger hit area
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: sectionRoot.headerActionClicked()
                    
                    TheophanyTooltip {
                        visible: actionMa.containsMouse && sectionRoot.headerActionTooltip !== ""
                        text: sectionRoot.headerActionTooltip
                    }
                }
            }
        }

        ColumnLayout {
            id: content
            width: parent.width
            Layout.fillWidth: true
            clip: true
            spacing: 2
            
            Layout.preferredHeight: sectionRoot.collapsed && !sectionRoot.isSidebarCollapsed ? 0 : content.implicitHeight
            
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
            }
        }
    }

    // Helper Component for Sidebar Items
    component SidebarItem : Rectangle {
        id: sidebarItemRoot
        property string text
        property string count: ""
        property string icon: ""
        property string iconSource: ""
        property bool isActive: false
        property bool isCollapsed: false
        property bool isProcessing: false
        signal clicked()

        onIsActiveChanged: {
            if (isActive) {
                // Check if this was triggered by a cycle action (hotkey)
                // We pulse it slightly or just ensure visible
                root.ensureVisible(this)
            }
        }

        Layout.fillWidth: true
        Layout.preferredHeight: 36
        color: isActive ? Theme.accent : (ma.containsMouse ? Theme.hover : "transparent")
        radius: 4

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: sidebarItemRoot.isCollapsed ? 0 : 10
            anchors.rightMargin: sidebarItemRoot.isCollapsed ? 0 : 10
            spacing: sidebarItemRoot.isCollapsed ? 0 : 10
            
            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignHCenter

                TheophanySpinner {
                    anchors.centerIn: parent
                    running: sidebarItemRoot.isProcessing
                    visible: running
                    size: 24
                }

                Text { 
                    anchors.centerIn: parent
                    visible: icon !== "" && !sidebarItemRoot.isProcessing
                    text: icon
                    color: isActive ? Theme.text : Theme.secondaryText
                    font.pixelSize: 16
                }
                Image {
                    anchors.centerIn: parent
                    visible: iconSource !== "" && !sidebarItemRoot.isProcessing
                    source: iconSource
                    width: 20
                    height: 20
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }
            }
            
            Text {
                id: labelText
                visible: !sidebarItemRoot.isCollapsed
                text: sidebarItemRoot.text
                color: isActive ? Theme.text : Theme.secondaryText
                font.bold: isActive
                font.pixelSize: 14
                Layout.fillWidth: true
                elide: Text.ElideRight
                opacity: sidebarItemRoot.isProcessing ? 0.5 : 1.0
            }
            Text {
                visible: !sidebarItemRoot.isCollapsed && sidebarItemRoot.count !== "" && !sidebarItemRoot.isProcessing
                text: sidebarItemRoot.count
                color: isActive ? Theme.text : (Theme.secondaryText)
                opacity: 0.7
                font.pixelSize: 12
                Layout.alignment: Qt.AlignVCenter
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
            
            TheophanyTooltip {
                visible: (ma.containsMouse && sidebarItemRoot.isCollapsed) || (ma.containsMouse && labelText.truncated)
                text: sidebarItemRoot.text
            }
        }
    }

    PlaylistModel {
        id: playlistModel
        Component.onCompleted: init(appInfo.getDataPath() + "/games.db")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.collapsed ? 5 : 10
        spacing: 15

        // Top Bar
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.collapsed ? 0 : 5
            spacing: 10
            
            Item {
                Layout.fillWidth: root.collapsed
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                
                Item {
                    id: burgerWrapper
                    width: 36; height: 36
                    anchors.centerIn: root.collapsed ? parent : undefined
                    anchors.left: root.collapsed ? undefined : parent.left
                    
                    Rectangle {
                        anchors.fill: parent
                        color: burgerMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15) : "transparent"
                        radius: 8
                        border.color: burgerMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Rectangle { width: 18; height: 2; color: Theme.text; radius: 1; opacity: 0.9 }
                        Rectangle { width: 14; height: 2; color: Theme.text; radius: 1; opacity: 0.9; anchors.horizontalCenter: parent.horizontalCenter }
                        Rectangle { width: 18; height: 2; color: Theme.text; radius: 1; opacity: 0.9 }
                    }

                    MouseArea {
                        id: burgerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: appMenu.popup()
                        
                        TheophanyTooltip {
                            visible: burgerMouse.containsMouse
                            text: "Main Menu"
                        }
                    }

                    TheophanyMenu {
                        id: appMenu
                        y: parent.height + 5
                        TheophanyMenuItem {
                            text: "Import Content..."
                            iconSource: "📥"
                            onTriggered: root.addContentRequested()
                        }
                        TheophanyMenuItem { 
                            text: "Flatpak Store"
                            iconSource: "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/assets/systems/flatpak.png"
                            onTriggered: window.openFlatpakStore()
                        }
                        TheophanyMenuSeparator {}
                        TheophanyMenuItem { 
                            text: "Manage Collections"
                            iconSource: "📚"
                            onTriggered: root.addSystemClicked()
                        }
                        TheophanyMenuItem { 
                            text: "Manage Emulators"
                            iconSource: "🛠️"
                            onTriggered: root.manageEmulatorsClicked() 
                        }
                        TheophanyMenuItem { 
                            text: "Manage Playlists"
                            iconSource: "📜"
                            onTriggered: root.managePlaylistsRequested() 
                        }
                        TheophanyMenuSeparator {}
                        TheophanyMenuItem { 
                            text: "Settings"
                            iconSource: "⚙️"
                            onTriggered: root.settingsRequested() 
                        }
                        TheophanyMenuItem { 
                            text: "About"
                            iconSource: "ℹ️"
                            onTriggered: aboutDialog.open() 
                        }
                        TheophanyMenuSeparator {}
                        TheophanyMenuItem { 
                            text: "Quit"
                            iconSource: "🚪"
                            onTriggered: window.tryQuit(true)
                        }
                    }
                }
            }
            TheophanyLogo { 
                Layout.fillWidth: true; 
                Layout.rightMargin: 15
                visible: !root.collapsed && root.width >= 200
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }

        Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; visible: !root.collapsed }

        // Scrollable Content
        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: root.collapsed ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded

            ColumnLayout {
                width: scrollView.availableWidth // Ensure it fits the scroll view
                spacing: 5

                // --- Library Section ---
                CollapsableSection {
                    title: "LIBRARY"
                    collapsed: root.libraryCollapsed || root.collapsed
                    isSidebarCollapsed: root.collapsed
                    onCollapsedChanged: if (!root.collapsed) root.libraryCollapsed = collapsed
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        SidebarItem {
                            text: "All Games"
                            count: root.allGamesCount > 0 ? root.allGamesCount : ""
                            icon: "🎮"
                            isActive: root.activeViewType === "all"
                            isCollapsed: root.collapsed
                            onClicked: {
                                root.activeViewType = "all"
                                root.activeId = ""
                                root.platformSelected("", "All Games", "🎮") 
                            }
                        }
                        SidebarItem {
                            text: "Favorites"
                            icon: "⭐"
                            isActive: root.activeViewType === "favorites"
                            isCollapsed: root.collapsed
                            onClicked: {
                                root.activeViewType = "favorites"
                                root.activeId = "favorites"
                                root.platformSelected("favorites", "Favorites", "⭐") 
                            }
                        }
                        SidebarItem {
                            text: "Recently Played"
                            icon: "🕒"
                            isActive: root.activeViewType === "recent"
                            isCollapsed: root.collapsed
                            onClicked: {
                                root.activeViewType = "recent"
                                root.activeId = "recent"
                                root.platformSelected("recent", "Recently Played", "🕒")
                            }
                        }
                    }
                }

                Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; Layout.margins: 10; visible: !root.collapsed }

                // --- Collections Section ---
                CollapsableSection {
                    title: "COLLECTIONS"
                    collapsed: root.collectionsCollapsed || root.collapsed
                    isSidebarCollapsed: root.collapsed
                    onCollapsedChanged: if (!root.collapsed) root.collectionsCollapsed = collapsed
                    headerActionIcon: "+"
                    headerActionVisible: !root.collapsed
                    headerActionTooltip: "Add Collection"
                    onHeaderActionClicked: root.addSystemClicked()
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            id: platformRepeater
                            model: platformModel
                            delegate: SidebarItem {
                                text: platformName
                                isCollapsed: root.collapsed
                                isProcessing: !!root.deletingIds[platformId]
                                iconSource: {
                                    if (!platformIcon) return ""
                                    if (platformIcon.startsWith("http") || platformIcon.startsWith("file://") || platformIcon.startsWith("qrc:/") || platformIcon.startsWith("/")) {
                                        return (platformIcon.startsWith("/") ? "file://" + platformIcon : platformIcon) + "?t=" + platformModel.cache_buster
                                    }
                                    if (platformIcon.startsWith("assets/")) {
                                        return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + platformIcon + "?t=" + platformModel.cache_buster
                                    }
                                    return "file://" + platformIcon + "?t=" + platformModel.cache_buster
                                }
                                isActive: root.activeViewType === "platform" && root.activeId === platformId
                                
                                // Right Click Context Menu
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        contextMenu.platformId = platformId
                                        contextMenu.platformName = platformName
                                        contextMenu.platformExtensions = platformExtensions
                                        contextMenu.platformCommand = platformCommand
                                        contextMenu.platformEmulatorId = platformEmulatorId
                                        contextMenu.platformType = platformType
                                        contextMenu.platformIcon = platformIcon
                                        contextMenu.pcConfig = pcConfig
                                        contextMenu.popup()
                                    }
                                }

                                onClicked: {
                                    root.activeViewType = "platform"
                                    root.activeId = platformId
                                    root.platformSelected(platformId, platformName, platformIcon)
                                }
                            }
                        }
                    }
                }

                Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; Layout.margins: 10; visible: !root.collapsed }

                // --- Platforms Section ---
                CollapsableSection {
                    title: "PLATFORMS"
                    visible: !root.collapsed && !appSettings.hidePlatformsSidebar
                    collapsed: root.platformsCollapsed || root.collapsed
                    isSidebarCollapsed: root.collapsed
                    onCollapsedChanged: if (!root.collapsed) root.platformsCollapsed = collapsed
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: root.platformTypes
                            delegate: SidebarItem {
                                text: modelData.name || modelData
                                isCollapsed: root.collapsed
                                iconSource: {
                                    var iconPath = modelData.icon || ""
                                    if (!iconPath || iconPath === "🏷️") return ""
                                    
                                    if (iconPath.startsWith("http") || iconPath.startsWith("file://") || iconPath.startsWith("qrc:/") || iconPath.startsWith("/")) {
                                        return (iconPath.startsWith("/") ? "file://" + iconPath : iconPath)
                                    }
                                    if (iconPath.startsWith("assets/")) {
                                        return "file://" + appInfo.getAssetsDir().replace("/assets", "") + "/" + iconPath
                                    }
                                    return "file://" + iconPath
                                }
                                icon: (modelData.icon === "🏷️" || !modelData.icon) ? "🏷️" : ""
                                
                                isActive: root.activeViewType === "platformType" && root.activeId === (modelData.name || modelData)
                                onClicked: {
                                    root.activeViewType = "platformType"
                                    root.activeId = modelData.name || modelData
                                    root.platformTypeSelected(modelData.name || modelData, modelData.icon || "")
                                }
                            }
                        }
                    }
                }

                Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; Layout.margins: 10; visible: !root.collapsed && !appSettings.hidePlatformsSidebar }

                // --- Playlists Section ---
                CollapsableSection {
                    title: "PLAYLISTS"
                    collapsed: root.playlistsCollapsed || root.collapsed
                    isSidebarCollapsed: root.collapsed
                    onCollapsedChanged: if (!root.collapsed) root.playlistsCollapsed = collapsed
                    headerActionIcon: "+"
                    headerActionVisible: !root.collapsed
                    headerActionTooltip: "Manage Playlists"
                    onHeaderActionClicked: root.managePlaylistsRequested()

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            id: playlistRepeater
                            model: playlistModel
                            delegate: SidebarItem {
                                text: playlistName
                                icon: "📜"
                                isCollapsed: root.collapsed
                                isActive: root.activeViewType === "playlist" && root.activeId === playlistId
                                 // Right Click Context Menu for Playlist
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        playlistContextMenu.playlistId = playlistId
                                        playlistContextMenu.playlistName = playlistName
                                        playlistContextMenu.popup()
                                    }
                                }
                                onClicked: {
                                    root.activeViewType = "playlist"
                                    root.activeId = playlistId
                                    root.platformSelected("playlist:" + playlistId, playlistName, "📜")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // RA profile indicator at the bottom
        Rectangle {
            id: raProfileSection
            Layout.fillWidth: true
            Layout.preferredHeight: root.collapsed ? 50 : 60
            Layout.topMargin: 5
            color: "transparent"
            visible: appSettings.retroAchievementsEnabled
            
            Rectangle {
                anchors.fill: parent
                color: Theme.hover
                opacity: profileMa.containsMouse ? 0.3 : 0.1
                radius: root.collapsed ? 25 : 8
                Behavior on opacity { ColorAnimation { duration: 200 } }
                Behavior on radius { NumberAnimation { duration: 200 } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: root.collapsed ? 5 : 10
                spacing: root.collapsed ? 0 : 12

                // Profile Pic
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    Layout.alignment: root.collapsed ? Qt.AlignHCenter : Qt.AlignLeft
                    radius: 20
                    color: Theme.background
                    clip: true
                    border.color: Theme.accent
                    border.width: window.raUserSummary ? 2 : 1

                    Image {
                        anchors.fill: parent
                        source: window.raProfilePic
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "RA"
                        color: Theme.secondaryText
                        font.bold: true
                        visible: window.raProfilePic === ""
                    }
                }

                // Info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    visible: !root.collapsed
                    Text {
                        text: appSettings.retroAchievementsUser
                        color: Theme.text
                        font.bold: true
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: {
                            if (window.raSummaryError) return "Error"
                            if (!window.raUserSummary) return "Connecting..."
                            var hc = window.raUserSummary.TotalPoints || 0
                            var sc = window.raUserSummary.TotalSoftcorePoints || 0
                            return (hc + sc) + " Points"
                        }
                        color: Theme.secondaryText
                        font.pixelSize: 11
                    }
                }
            }

            MouseArea {
                id: profileMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: window.openRaDashboard()
            }
        }
    }


    TheophanyMenu {
        id: playlistContextMenu
        property string playlistId: ""
        property string playlistName: ""
        TheophanyMenuItem {
            text: "Delete Playlist"
            iconSource: "🗑️"
            onTriggered: playlistModel.deletePlaylist(playlistContextMenu.playlistId)
        }
    }
    
    TheophanyMenu {
        id: contextMenu
        property string platformId: ""
        property string platformName: ""
        property string platformExtensions: ""
        property string platformCommand: ""
        property string platformEmulatorId: ""
        property string platformType: ""
        property string platformIcon: ""
        property string pcConfig: ""

        TheophanyMenuItem {
            text: "Edit Collection"
            iconSource: "📝"
            onTriggered: {
                root.editSystemRequested(contextMenu.platformId, contextMenu.platformName, contextMenu.platformExtensions, contextMenu.platformCommand, contextMenu.platformEmulatorId, contextMenu.platformType, contextMenu.platformIcon, contextMenu.pcConfig) 
            }
        }
        TheophanyMenuItem {
            text: "Rescan Collection"
            iconSource: "🔄"
            onTriggered: root.rescanRequested(contextMenu.platformId)
        }
        TheophanyMenuSeparator {
            visible: contextMenu.platformType === "PC (Linux)"
        }
        TheophanyMenuItem {
            text: "Add from Flatpak Store"
            iconSource: "📦"
            visible: contextMenu.platformType === "PC (Linux)"
            onTriggered: window.openFlatpakStore(contextMenu.platformId)
        }
        TheophanyMenuSeparator {
            visible: contextMenu.platformName !== "Flatpak Games"
        }
        TheophanyMenuItem {
            text: "Import Content"
            iconSource: "📥"
            visible: contextMenu.platformName !== "Flatpak Games"
            onTriggered: {
                root.addContentToCollectionRequested(contextMenu.platformId)
            }
        }
        TheophanyMenuSeparator {}
        TheophanyMenuItem {
            text: "Delete Collection"
            iconSource: "🗑️"
            onTriggered: {
                root.deleteCollectionRequested(contextMenu.platformId, contextMenu.platformName)
            }
        }
    }

}
