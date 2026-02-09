import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"
import Theophany.Bridge 1.0

Dialog {
    id: root
    width: Math.max(650, window.width * 0.6)
    height: Math.max(500, window.height * 0.6)
    title: "Mass Edit Games"
    modal: true
    header: null
    
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2



    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12
        
        // Premium subtle glow
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: Qt.rgba(0, 0, 0, 0.25)
            radius: 20
            samples: 41
        }
    }

    property var gameIds: [] // List of IDs to edit
    property var allGenres: []
    property var allTags: []
    property var allDevelopers: []
    property var allPublishers: []
    property var allRegions: []
    property var allYears: []

    function openFor(ids) {

        gameIds = ids
        // Reset fields
        regionCheck.checked = false
        genreCheck.checked = false
        devCheck.checked = false
        pubCheck.checked = false
        yearCheck.checked = false
        ratingCheck.checked = false
        tagsCheck.checked = false
        favCb.checked = false
        
        regionField.text = ""
        genreField.text = ""
        devField.text = ""
        pubField.text = ""
        yearField.text = ""
        ratingField.value = 0
        tagsField.text = ""
        favSwitch.checked = false
        
        allGenres = gameModel.getAllGenres()
        allTags = gameModel.getAllTags()
        allDevelopers = gameModel.getAllDevelopers()
        allPublishers = gameModel.getAllPublishers()
        allRegions = gameModel.getAllRegions()
        allYears = gameModel.getAllYears()

        open()
    }

    contentItem: Item {
        implicitHeight: mainCol.implicitHeight
        
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15

            // Standard Modal Header
            Text {
                text: "Mass Edit (" + root.gameIds.length + " games)"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            // Scrollable Content
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: -1
                clip: true
                
                ColumnLayout {
                    width: parent.width * 0.95
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Label { 
                        text: "Select fields to update for all selected games.\nWarning: This will overwrite existing data for checked fields."
                        color: Theme.secondaryText
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Fields Helper
                    component EditRow: RowLayout {
                        property alias checked: cb.checked
                        property string label
                        property alias editor: editorContainer.data

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        spacing: 10

                        TheophanyCheckBox { 
                            id: cb
                            checked: false 
                        }
                        Label { 
                            text: label 
                            font.bold: true
                            color: cb.checked ? Theme.text : Theme.secondaryText
                            Layout.preferredWidth: 100
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cb.toggle()
                            }
                        }
                        Item {
                            id: editorContainer
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            enabled: cb.checked
                            opacity: cb.checked ? 1.0 : 0.5
                        }
                    }

                    EditRow {
                        id: genreCheck
                        label: "Genre"
                        editor: [ TheophanySuggestField { id: genreField; anchors.fill: parent; fullModel: root.allGenres; isCommaSeparated: true } ]
                    }
                    
                    EditRow {
                        id: devCheck
                        label: "Developer"
                        editor: [ TheophanySuggestField { id: devField; anchors.fill: parent; fullModel: root.allDevelopers } ]
                    }
                    
                    EditRow {
                        id: pubCheck
                        label: "Publisher"
                        editor: [ TheophanySuggestField { id: pubField; anchors.fill: parent; fullModel: root.allPublishers } ]
                    }
                    
                    EditRow {
                        id: regionCheck
                        label: "Region"
                        editor: [ TheophanySuggestField { id: regionField; anchors.fill: parent; fullModel: root.allRegions } ]
                    }
                    
                    EditRow {
                        id: yearCheck
                        label: "Release Year"
                        editor: [ TheophanySuggestField { id: yearField; anchors.fill: parent; fullModel: root.allYears } ]
                    }

                    EditRow {
                        id: tagsCheck
                        label: "Tags"
                        editor: [ TheophanySuggestField { id: tagsField; anchors.fill: parent; placeholderText: "Action, RPG..."; fullModel: root.allTags; isCommaSeparated: true } ]
                    }
                    
                    EditRow {
                        id: ratingCheck
                        label: "Rating (1-10)"
                        editor: [ 
                            TheophanySpinBox { 
                                id: ratingField 
                                anchors.fill: parent
                                from: 10; to: 100; stepSize: 5
                                property real realValue: value / 10.0
                                validator: DoubleValidator { bottom: 1; top: 10; decimals: 1 }
                                textFromValue: function(value, locale) { return Number(value / 10.0).toLocaleString(locale, 'f', 1) }
                                valueFromText: function(text, locale) { return Number.fromLocaleString(locale, text) * 10 }
                            }
                        ]
                    }

                    // Manual Row for Favorite properties to ensure ID access
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        spacing: 10

                        TheophanyCheckBox { 
                            id: favCb
                            checked: false 
                        }
                        Label { 
                            text: "Favorite" 
                            font.bold: true
                            color: favCb.checked ? Theme.text : Theme.secondaryText
                            Layout.preferredWidth: 100

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: favCb.toggle()
                            }
                        }
                        TheophanySwitch {
                            id: favSwitch
                            enabled: favCb.checked
                            checked: false
                            text: checked ? "Yes" : "No"
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // Footer Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                Layout.topMargin: 5

                TheophanyButton {
                    text: "Cancel"
                    onClicked: {

                        root.reject()
                    }
                }
                
                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: "Apply Changes"
                    primary: true
                    Layout.preferredWidth: 160
                    onClicked: {

                        var data = {}
                        if (genreCheck.checked) data["genre"] = genreField.text.replace(/[,;\s]+$/, "")
                        if (devCheck.checked) data["developer"] = devField.text.replace(/[,;\s]+$/, "")
                        if (pubCheck.checked) data["publisher"] = pubField.text.replace(/[,;\s]+$/, "")
                        if (regionCheck.checked) data["region"] = regionField.text
                        if (tagsCheck.checked) data["tags"] = tagsField.text.replace(/[,;\s]+$/, "")
                        if (yearCheck.checked) data["release_date"] = yearField.text
                        if (ratingCheck.checked) data["rating"] = ratingField.realValue
                        if (favCb.checked) data["is_favorite"] = favSwitch.checked


                        gameModel.bulkUpdateMetadata(JSON.stringify(root.gameIds), JSON.stringify(data))
                        root.accept()
                    }
                }
            }
        }
    }
}
