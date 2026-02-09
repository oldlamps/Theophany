import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"
import "../components"

Dialog {
    id: root
    title: "Preview ROM Import"
    modal: true
    width: parent.width * 0.9
    height: parent.height * 0.9
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null

    property var roms: []
    property string systemName: ""
    property string emulatorName: ""
    property int selectedCount: 0
    property bool autoScrape: false

    property var allGenres: []
    property var allTags: []
    property var allDevelopers: []
    property var allPublishers: []
    property var allRegions: []
    property var allYears: []

    onOpened: {
        autoScrape = false // Reset default
        allGenres = gameModel.getAllGenres()
        allTags = gameModel.getAllTags()
        allDevelopers = gameModel.getAllDevelopers()
        allPublishers = gameModel.getAllPublishers()
        allRegions = gameModel.getAllRegions()
        allYears = gameModel.getAllYears()
    }

    signal importRequested(var selectedRoms)

    onRomsChanged: {
        updateSelectedCount()
    }

    function updateSelectedCount() {
        var count = 0
        for (var i = 0; i < romListModel.count; i++) {
            if (romListModel.get(i).selected) count++
        }
        selectedCount = count
    }

    ListModel {
        id: romListModel
    }

    function setRoms(romArray) {
        romListModel.clear()
        for (var i = 0; i < romArray.length; i++) {
            var item = romArray[i]
            item.selected = true
            romListModel.append(item)
        }
        updateSelectedCount()
    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 30
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 15
            
            ColumnLayout {
                spacing: 4
                Text {
                    text: "Review Discovered ROMs"
                    color: Theme.text
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: "Found " + romListModel.count + " files. " + selectedCount + " selected for import."
                    color: Theme.secondaryText
                    font.pixelSize: 14
                }
            }

            Item { Layout.fillWidth: true }

            TheophanyButton {
                text: "Deselect All"
                onClicked: {
                    for (var i = 0; i < romListModel.count; i++) romListModel.setProperty(i, "selected", false)
                    updateSelectedCount()
                }
            }

            TheophanyButton {
                text: "Select All"
                onClicked: {
                    for (var i = 0; i < romListModel.count; i++) romListModel.setProperty(i, "selected", true)
                    updateSelectedCount()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background
            border.color: Theme.border
            radius: 8
            clip: true

            // Horizontal Scroll Wrapper
            Flickable {
                id: horizontalFlick
                anchors.fill: parent
                contentWidth: 1830
                contentHeight: parent.height
                clip: true
                
                ScrollBar.horizontal: TheophanyScrollBar { 
                    policy: ScrollBar.AlwaysOn
                    height: 12
                    anchors.bottom: parent.bottom
                }

                Column {
                    width: horizontalFlick.contentWidth
                    height: parent.height

                    // Header
                    Rectangle {
                        width: parent.width
                        height: 40
                        color: Theme.sidebar
                        border.color: Theme.border
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 15
                            spacing: 10

                            Item { width: 30 } // Checkbox
                            Text { text: "Title"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 300 }
                            Text { text: "Filename"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 300 }
                            Text { text: "Region"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 120 } // Left aligned by default
                            Text { text: "Genre"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 150 }
                            Text { text: "Developer"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 150 }
                            Text { text: "Publisher"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 150 }
                            Text { text: "Year"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 80 }
                            Text { text: "Rating"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 60 }
                            Text { text: "Tags"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 200 }
                            Text { text: "System"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 150 }
                            Text { text: "Emulator"; color: Theme.secondaryText; font.bold: true; Layout.preferredWidth: 150 } // End
                        }
                    }

                    // List
                    ListView {
                        id: listView
                        width: parent.width
                        height: parent.height - 40 // Minus header
                        clip: true
                        model: romListModel
                        interactive: true // Vertical scrolling handled here
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: listView.width
                            height: 50
                            color: index % 2 === 0 ? "transparent" : Qt.rgba(1,1,1,0.03)

                            property string discoveredRegion: model.region
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 15
                                anchors.rightMargin: 15
                                spacing: 10

                                CheckBox {
                                    id: itemSelectCheck
                                    checked: model.selected
                                    onClicked: {
                                        romListModel.setProperty(index, "selected", checked)
                                        root.updateSelectedCount()
                                    }
                                    palette.windowText: Theme.text
                                    Layout.preferredWidth: 30
                                    indicator: Rectangle {
                                        implicitWidth: 18; implicitHeight: 18
                                        x: itemSelectCheck.leftPadding
                                        y: parent.height / 2 - height / 2
                                        radius: 3
                                        border.color: itemSelectCheck.checked ? Theme.accent : Theme.secondaryText
                                        color: "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: Theme.accent
                                            visible: itemSelectCheck.checked
                                            font.bold: true
                                            font.pixelSize: 14
                                        }
                                    }
                                }

                                TheophanyTextField {
                                    text: model.title
                                    Layout.preferredWidth: 300
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "title", text)
                                }

                                Text { 
                                    text: model.filename
                                    color: Theme.secondaryText
                                    Layout.preferredWidth: 300
                                    elide: Text.ElideMiddle
                                }

                                TheophanySuggestField {
                                    id: regionField
                                    text: model.region
                                    Layout.preferredWidth: 120
                                    fullModel: root.allRegions
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "region", text)
                                }

                                TheophanySuggestField {
                                    text: model.genre || ""
                                    Layout.preferredWidth: 150
                                    placeholderText: "Genre"
                                    fullModel: root.allGenres
                                    isCommaSeparated: true
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "genre", text)
                                }

                                TheophanySuggestField {
                                    text: model.developer || ""
                                    Layout.preferredWidth: 150
                                    placeholderText: "Developer"
                                    fullModel: root.allDevelopers
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "developer", text)
                                }

                                TheophanySuggestField {
                                    text: model.publisher || ""
                                    Layout.preferredWidth: 150
                                    placeholderText: "Publisher"
                                    fullModel: root.allPublishers
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "publisher", text)
                                }

                                TheophanySuggestField {
                                    text: model.year || ""
                                    Layout.preferredWidth: 80
                                    placeholderText: "YYYY"
                                    fullModel: root.allYears
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "year", text)
                                }

                                TheophanyTextField {
                                    text: model.rating || ""
                                    Layout.preferredWidth: 60
                                    placeholderText: "0.0"
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "rating", text)
                                }

                                TheophanySuggestField {
                                    text: model.tags || ""
                                    Layout.preferredWidth: 200
                                    placeholderText: "Tag1, Tag2..."
                                    fullModel: root.allTags
                                    isCommaSeparated: true
                                    onTextChanged: if (activeFocus) romListModel.setProperty(index, "tags", text)
                                }

                                Text { 
                                    text: model.system
                                    color: Theme.secondaryText
                                    Layout.preferredWidth: 150
                                    elide: Text.ElideRight
                                }

                                Text { 
                                    text: model.emulator
                                    color: Theme.secondaryText
                                    Layout.preferredWidth: 150
                                    elide: Text.ElideRight
                                }
                            }
                            
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Theme.border
                                opacity: 0.3
                            }
                        }
                    }
                }
            }
            
            // External Vertical ScrollBar anchored to right of container
            TheophanyScrollBar {
                id: vBar
                anchors.top: parent.top
                anchors.bottom: parent.bottom // Overlaps horizontal bar slightly at corner but acceptable
                anchors.right: parent.right
                anchors.topMargin: 40 // Below header
                anchors.bottomMargin: 12 // Above horizontal bar
                
                // Binding to ListView contentY
                policy: ScrollBar.AsNeeded
                size: listView.visibleArea.heightRatio
                position: listView.visibleArea.yPosition
                active: listView.moving || listView.flicking
                orientation: Qt.Vertical

                // We need to sync position back to listview too if dragged? 
                // TheophanyScrollBar inherits ScrollBar, so we can't bind directly to listView.contentY easily without a Flickable binding.
                // Actually ScrollBar.vertical attached property on ListView is easiest if we can re-parent it.
                // But attached property is painted *inside* the item.
                // Let's rely on standard binding:
            }
            
            // Connecting external scrollbar to list view
            // Since TheophanyScrollBar is a custom component wrapping ScrollBar or inheriting?
            // Let's check TheophanyScrollBar. It probably inherits ScrollBar.
            // If so:
            Connections {
               target: vBar
               function onPositionChanged() { 
                   if (vBar.pressed) listView.contentY = vBar.position * listView.contentHeight 
               }
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 15
            
            TheophanyButton {
                text: "Cancel"
                onClicked: root.close()
            }

            Item { Layout.fillWidth: true }
            
            CheckBox {
                id: autoScrapeCheck
                text: "Automatically fetch metadata"
                checked: root.autoScrape
                onCheckedChanged: root.autoScrape = checked
                palette.windowText: Theme.text
                font.pixelSize: 13
                indicator: Rectangle {
                    implicitWidth: 18; implicitHeight: 18
                    x: autoScrapeCheck.leftPadding
                    y: parent.height / 2 - height / 2
                    radius: 3
                    border.color: autoScrapeCheck.checked ? Theme.accent : Theme.secondaryText
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.accent
                        visible: autoScrapeCheck.checked
                        font.bold: true
                        font.pixelSize: 14
                    }
                }
            }

            TheophanyButton {
                text: "Import " + selectedCount + " Games"
                primary: true
                enabled: selectedCount > 0
                onClicked: {
                    var selected = []
                    for (var i = 0; i < romListModel.count; i++) {
                        var item = romListModel.get(i)
                        if (item.selected) {
                            selected.push({
                                "id": item.id,
                                "path": item.path,
                                "filename": item.filename,
                                "title": item.title,
                                "region": item.region,
                                "genre": item.genre,
                                "developer": item.developer,
                                "publisher": item.publisher,
                                "year": item.year,
                                "rating": item.rating,
                                "tags": item.tags
                            })
                        }
                    }
                    root.importRequested(selected)
                    root.close()
                }
            }
        }
    }
}
