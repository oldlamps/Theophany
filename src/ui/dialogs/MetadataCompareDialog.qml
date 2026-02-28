import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    width: 700
    height: 600
    title: "Review Scraped Metadata"
    modal: true
    header: null
    standardButtons: Dialog.NoButton

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
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }

    property var currentData: ({})
    property var scrapedData: ({})
    property string gameId: ""
    
    // Result object containing only selected fields
    property var finalData: ({})

    // Signals
    signal metadataApplied(var data)

    function init(current, scraped) {
        currentData = current
        scrapedData = scraped
        compareModel.clear()
        
        var fields = [
            { key: "title", label: "Title" },
            { key: "description", label: "Description" },
            { key: "developer", label: "Developer" },
            { key: "publisher", label: "Publisher" },
            { key: "genre", label: "Genre" },
            { key: "region", label: "Region" },
            { key: "release_year", label: "Release Year" },
            { key: "rating", label: "Rating" },
            { key: "resources", label: "Resources" },
            { key: "assets", label: "Images" }
        ]
        
        for (var i = 0; i < fields.length; i++) {
            var key = fields[i].key
            var curVal = currentData[key]
            var newVal = scrapedData[key]
            
            var displayCur = ""
            var displayNew = ""
            var isDifferent = false
            
            if (key === "resources") {
                var curList = (curVal && Array.isArray(curVal)) ? curVal : []
                var newList = (newVal && Array.isArray(newVal)) ? newVal : []
                
                displayCur = curList.length + " Links"
                if (curList.length > 0) {
                    displayCur += ": " + curList.map(function(r) { return r.label || r.type }).join(", ")
                }
                
                displayNew = "Append " + newList.length + " Link" + (newList.length !== 1 ? "s" : "")
                if (newList.length > 0) {
                    displayNew += ": " + newList.map(function(r) { return r.label || r.type }).join(", ")
                }
                
                isDifferent = newList.length > 0
                if (newList.length === 0) displayNew = "None"
            } else if (key === "assets") {
                var curCount = 0
                if (currentData.assets) {
                    for (var k in currentData.assets) curCount += currentData.assets[k].length
                }
                var newCount = 0
                if (newVal) {
                    for (var k in newVal) newCount += newVal[k].length
                }
                displayCur = curCount + " Images"
                displayNew = newCount + " Images"
                isDifferent = newCount > 0
                if (newCount === 0) displayNew = "None"
            } else {
                if (curVal === undefined || curVal === null) curVal = ""
                if (newVal === undefined || newVal === null) newVal = ""
                
                // For numbers
                if (key === "rating" || key === "release_year") {
                    if (curVal !== "" && curVal !== 0 && curVal !== "0") curVal = curVal.toString()
                    else curVal = ""
                    
                    if (newVal !== "" && newVal !== 0 && newVal !== "0") newVal = newVal.toString()
                    else newVal = ""
                }
                displayCur = curVal
                displayNew = newVal
                isDifferent = newVal !== "" && newVal.toString() !== curVal.toString()
            }
            
            // Only add if relevant (different or non-empty new value)
            if ((key === "resources" || key === "assets") && !isDifferent) continue; // Skip if no new items
             
            compareModel.append({
                key: key,
                label: fields[i].label,
                currentValue: displayCur,
                checkState: isDifferent,
                newValue: displayNew
            })
        }
    }
    
    onAccepted: {

        var result = {}
        for (var i = 0; i < compareModel.count; i++) {
            var item = compareModel.get(i)
            if (item.checkState) {

                if (item.key === "resources") {
                    // Use the raw array from scrapedData
                    result["resources"] = scrapedData["resources"]
                } else if (item.key === "assets") {
                    result["assets"] = scrapedData["assets"]

                } else if (item.key === "rating") {
                    result["rating"] = parseFloat(scrapedData["rating"]) || 0
                } else if (item.key === "release_year") {
                    result["release_date"] = parseInt(scrapedData["release_year"]).toString()
                } else {
                    result[item.key] = scrapedData[item.key]
                }
            }
        }
        root.metadataApplied(result)
    }

    ListModel { id: compareModel }

    contentItem: ColumnLayout {
        spacing: 0
        anchors.fill: parent
        anchors.margins: 0
        
        // Custom Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 70
            color: "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 25
                anchors.rightMargin: 25
                spacing: 15
                
                Text {
                    text: "Review Scraped Metadata"
                    color: Theme.text
                    font.pixelSize: 22
                    font.bold: true
                    Layout.fillWidth: true
                }
                
                TheophanyButton {
                    text: "✕"
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    flat: true
                    onClicked: root.reject()
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.3 }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 25
            spacing: 20

            Label {
                text: "Select the metadata fields you want to update:"
                color: Theme.secondaryText
                font.pixelSize: 14
            }
            
            RowLayout {
                spacing: 12
                TheophanyButton { text: "Select All"; onClicked: setAll(true) }
                TheophanyButton { text: "Select None"; onClicked: setAll(false) }
            }
            
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: compareModel
                
                delegate: Rectangle {
                    width: listView.width
                    height: 80
                    color: index % 2 === 0 ? Theme.secondaryBackground : Theme.background
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 15
                        
                        CheckBox {
                            id: cb
                            checked: model.checkState
                            onToggled: compareModel.setProperty(index, "checkState", checked)
                            Layout.alignment: Qt.AlignVCenter
                            palette.windowText: Theme.text
                            indicator: Rectangle {
                                implicitWidth: 20; implicitHeight: 20
                                x: cb.leftPadding
                                y: parent.height / 2 - height / 2
                                radius: 4
                                border.color: cb.checked ? Theme.accent : Theme.secondaryText
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Theme.accent
                                    visible: cb.checked
                                    font.bold: true
                                    font.pixelSize: 16
                                }
                            }
                        }
                        
                        ColumnLayout {
                            Layout.preferredWidth: 100
                            Text { text: model.label; color: Theme.secondaryText; font.bold: true }
                        }
                        
                        // Current
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1 // flexible
                            Text { text: "Current"; color: Theme.secondaryText; font.pixelSize: 10 }
                            Text { 
                                text: model.currentValue || "--"
                                color: Theme.text
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        
                        // Arrow
                        Text { text: "→"; color: Theme.secondaryText; font.pixelSize: 20 }
                        
                        // New
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1 // flexible
                            Text { text: "New"; color: Theme.accent; font.pixelSize: 10; font.bold: true }
                            Text { 
                                text: model.newValue || "--"
                                color: Theme.text
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
                ScrollBar.vertical: TheophanyScrollBar { }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.3 }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            Layout.leftMargin: 25
            Layout.rightMargin: 25
            spacing: 15
            
            Item { Layout.fillWidth: true }

            TheophanyButton {
                text: "Cancel"
                onClicked: root.reject()
                Layout.preferredWidth: 100
            }
            
            TheophanyButton {
                text: "Apply Metadata"
                primary: true
                onClicked: root.accept()
                Layout.preferredWidth: 150
            }
        }
    }
    
    function setAll(checked) {
        for (var i = 0; i < compareModel.count; i++) {
            compareModel.setProperty(i, "checkState", checked)
        }
    }
}
