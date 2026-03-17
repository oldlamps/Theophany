import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    width: 900
    height: 750
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
            var itemData = []
            
            if (key === "resources") {
                var curList = (curVal && Array.isArray(curVal)) ? curVal : []
                var newList = (newVal && Array.isArray(newVal)) ? newVal : []
                
                displayCur = curList.length + " Links"
                displayNew = newList.length + " New Links"
                isDifferent = newList.length > 0
                
                // For resources, we store the full list of new ones for granular selection
                for (var j = 0; j < newList.length; j++) {
                    itemData.push({
                        label: newList[j].label || newList[j].type || "Link",
                        url: newList[j].url,
                        type: newList[j].type,
                        selected: true
                    })
                }
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
                
                // For assets, store them categorized
                if (newVal) {
                    for (var cat in newVal) {
                        for (var m = 0; m < newVal[cat].length; m++) {
                            itemData.push({
                                label: cat,
                                url: newVal[cat][m],
                                selected: true
                            })
                        }
                    }
                }
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
            if ((key === "resources" || key === "assets") && !isDifferent) continue;
             
            compareModel.append({
                key: key,
                label: fields[i].label,
                currentValue: displayCur,
                checkState: isDifferent,
                newValue: displayNew,
                expanded: false,
                granularData: itemData // Use granularData for sub-selections
            })
        }
    }
    
    onAccepted: {
        var result = {}
        for (var i = 0; i < compareModel.count; i++) {
            var item = compareModel.get(i)
            if (item.checkState) {
                if (item.key === "resources") {
                    var selectedRes = []
                    var gData = item.granularData
                    for (var j = 0; j < gData.count; j++) {
                        if (gData.get(j).selected) {
                            selectedRes.push({
                                label: gData.get(j).label,
                                url: gData.get(j).url,
                                type: gData.get(j).type
                            })
                        }
                    }
                    if (selectedRes.length > 0) result["resources"] = selectedRes
                } else if (item.key === "assets") {
                    var selectedAssets = {}
                    var gDataA = item.granularData
                    for (var k = 0; k < gDataA.count; k++) {
                        var assetItem = gDataA.get(k)
                        if (assetItem.selected) {
                            if (!selectedAssets[assetItem.label]) selectedAssets[assetItem.label] = []
                            selectedAssets[assetItem.label].push(assetItem.url)
                        }
                    }
                    if (Object.keys(selectedAssets).length > 0) result["assets"] = selectedAssets
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
                spacing: 8
                
                delegate: Rectangle {
                    id: delegateRoot
                    width: listView.width
                    height: contentCol.implicitHeight + 20
                    color: index % 2 === 0 ? Qt.rgba(1,1,1,0.02) : "transparent"
                    border.color: Theme.border
                    border.width: 1
                    radius: 8
                    
                    ColumnLayout {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 15
                            
                            CheckBox {
                                id: cb
                                checked: model.checkState
                                onToggled: compareModel.setProperty(index, "checkState", checked)
                                Layout.alignment: Qt.AlignVCenter
                                palette.windowText: Theme.text
                                indicator: Rectangle {
                                    implicitWidth: 20; implicitHeight: 20
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
                            
                            Text { 
                                text: model.label
                                color: Theme.accent
                                font.bold: true
                                Layout.preferredWidth: 100
                            }
                            
                            // Current values
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                visible: model.key !== "resources" && model.key !== "assets"
                                
                                Text { 
                                    text: "CURRENT"
                                    color: Theme.secondaryText
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                }

                                // Scrollable current description
                                ScrollView {
                                    id: scrollCur
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: model.key === "description" ? Math.min(Math.max(descTextCur.implicitHeight, 40), 150) : 0
                                    visible: model.key === "description"
                                    clip: true
                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                                    contentWidth: availableWidth
                                    
                                    Text {
                                        id: descTextCur
                                        width: scrollCur.availableWidth
                                        text: model.currentValue || "--"
                                        color: Theme.text
                                        opacity: 0.6
                                        wrapMode: Text.Wrap
                                        font.pixelSize: 13
                                        lineHeight: 1.2
                                    }
                                }
                                
                                Text { 
                                    text: model.currentValue || "--"
                                    color: Theme.text
                                    opacity: 0.6
                                    elide: Text.ElideRight
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                    visible: model.key !== "description"
                                }
                            }
                            
                            // Arrow
                            Text { 
                                text: "→"
                                color: Theme.secondaryText
                                font.pixelSize: 20
                                visible: model.key !== "resources" && model.key !== "assets"
                                Layout.alignment: Qt.AlignVCenter
                            }
                            
                            // New values
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                
                                Text { 
                                    text: "NEW"
                                    color: Theme.accent
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                    visible: model.key !== "resources" && model.key !== "assets"
                                }
                                
                                // Scrollable new description
                                ScrollView {
                                    id: scrollNew
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: model.key === "description" ? Math.min(Math.max(descTextNew.implicitHeight, 40), 150) : 0
                                    visible: model.key === "description"
                                    clip: true
                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                                    contentWidth: availableWidth
                                    
                                    Text {
                                        id: descTextNew
                                        width: scrollNew.availableWidth
                                        text: model.newValue || "--"
                                        color: Theme.text
                                        wrapMode: Text.Wrap
                                        font.pixelSize: 13
                                        lineHeight: 1.2
                                        font.bold: true
                                    }
                                }

                                Text { 
                                    text: model.newValue || "--"
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    visible: model.key !== "description" && model.key !== "resources" && model.key !== "assets"
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                // Granular summary
                                RowLayout {
                                    visible: model.key === "resources" || model.key === "assets"
                                    Text {
                                        text: model.newValue
                                        color: Theme.text
                                        font.bold: true
                                    }
                                    TheophanyButton {
                                        text: model.expanded ? "Hide Details" : "Show Details"
                                        flat: true
                                        font.pixelSize: 12
                                        onClicked: compareModel.setProperty(index, "expanded", !model.expanded)
                                    }
                                }
                            }
                        }

                        // Expanded granular view
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: model.expanded && (model.key === "resources" || model.key === "assets")
                            spacing: 5
                            Layout.leftMargin: 40

                            Repeater {
                                model: granularData
                                delegate: RowLayout {
                                    spacing: 10
                                    CheckBox {
                                        id: subCb
                                        checked: model.selected
                                        onToggled: granularData.setProperty(index, "selected", checked)
                                        indicator: Rectangle {
                                            implicitWidth: 16; implicitHeight: 16
                                            radius: 3
                                            border.color: subCb.checked ? Theme.accent : Theme.secondaryText
                                            color: "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: Theme.accent
                                                visible: subCb.checked
                                                font.bold: true
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                    Text { 
                                        text: model.label
                                        color: Theme.text
                                        font.bold: true
                                        Layout.preferredWidth: 120
                                    }
                                    Text { 
                                        text: model.url
                                        color: Theme.secondaryText
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                        font.pixelSize: 11
                                    }
                                }
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

