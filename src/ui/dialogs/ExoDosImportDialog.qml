import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import ExoDOS"
    modal: true
    width: Overlay.overlay ? Math.min(Overlay.overlay.width * 0.75, 850) : 800
    height: Overlay.overlay ? Math.min(Overlay.overlay.height * 0.85, 750) : 650
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null
    
    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

    StoreBridge {
        id: storeBridge
        
        onExodosLibraryFinished: (resultsJson) => {
            var results = JSON.parse(resultsJson)
            results.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })

            exodosModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                exodosModel.append({
                    "checked": true,
                    "gameId": item.id || "",
                    "title": item.title || "Unknown Game",
                    "path": item.path || "",
                    "filename": item.filename || "",
                    "icon_path": "",
                    "platform_id": "DOS",
                    "platform_name": "exoDOS",
                    "tags": item.tags || "exoDOS",
                    "is_installed": true
                })
            }
            loading = false
        }


    }



    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: storeBridge.poll()
    }

    property bool loading: false
    property string selectedPath: ""
    ListModel { id: exodosModel }
    ListModel { id: filteredPlatforms }

    property int selectedCount: {
        var count = 0
        for (var i = 0; i < exodosModel.count; i++) {
            if (exodosModel.get(i).checked) count++
        }
        return count
    }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) return
        
        var selectedIdx = 0
        var hasDos = false

        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = (sidebar.platformModel.data(idx, 261) || "").toLowerCase()
            if (type === "dos" || name.toLowerCase().indexOf("dos") !== -1) {
                filteredPlatforms.append({
                    "name": name,
                    "id": sidebar.platformModel.data(idx, 256)
                })
                hasDos = true
            }
        }
        
        if (!hasDos) {
             filteredPlatforms.insert(0, {
                 "name": "exoDOS (Default)",
                 "id": "virtual_dos"
             })
             selectedIdx = 0
        } else {
            for (var j = 0; j < filteredPlatforms.count; j++) {
                if (filteredPlatforms.get(j).name.toLowerCase().indexOf("exodos") !== -1) {
                    selectedIdx = j
                    break
                }
            }
        }
        
        platformSelector.currentIndex = selectedIdx
    }

    function openImport() {
        refreshFilteredPlatforms()
        open()
    }

    FolderDialog {
        id: folderDialog
        title: "Select ExoDOS Directory (The parent of 'eXo')"
        onAccepted: {
            var path = selectedFolder.toString()
            if (path.startsWith("file://")) {
                path = path.substring(7)
            }
            selectedPath = path
            // Don't auto-scan immediately, let the user click "Scan" if they want, 
            // or we can keep it. User said "when I select a directory it doesn't populate in the text field".
            // Updating selectedPath should update the text field.
        }
    }

    contentItem: Item {
        implicitHeight: mainCol.implicitHeight
        
        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15

            Text {
                text: "Import ExoDOS Games"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                TheophanyTextField {
                    id: pathField
                    Layout.fillWidth: true
                    placeholderText: "Select ExoDOS installation directory..."
                    text: selectedPath
                    onTextChanged: {
                        if (selectedPath !== text) {
                            selectedPath = text
                        }
                    }
                }

                TheophanyButton {
                    text: "Browse..."
                    onClicked: folderDialog.open()
                }
                
                TheophanyButton {
                    text: "Scan"
                    primary: true
                    enabled: selectedPath !== "" && !loading
                    onClicked: {
                        loading = true
                        storeBridge.refresh_exodos_library(selectedPath)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15
                visible: selectedPath !== ""

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true
                        Text { text: "Import to Collection:"; color: Theme.accent; font.pixelSize: 11; font.bold: true }
                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true
                            TheophanyComboBox {
                                id: platformSelector
                                Layout.fillWidth: true
                                model: filteredPlatforms
                                textRole: "name"
                            }
                            
                            TheophanyButton {
                                text: "+"
                                primary: true
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: 32
                                onClicked: {
                                    addSystemDialog.openAddWithType("DOS", "exoDOS")
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15
                    visible: exodosModel.count > 0 && !root.loading

                    TheophanyButton {
                        text: "Select All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            for (var i = 0; i < exodosModel.count; i++) exodosModel.setProperty(i, "checked", true)
                        }
                    }

                    TheophanyButton {
                        text: "Deselect All"
                        flat: true
                        font.pixelSize: 12
                        onClicked: {
                            for (var i = 0; i < exodosModel.count; i++) exodosModel.setProperty(i, "checked", false)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: selectedCount + " of " + exodosModel.count + " games found"
                        color: Theme.secondaryText
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.sidebar
                    radius: 8
                    clip: true
                    border.color: Theme.border
                    border.width: 1

                    ListView {
                        id: list
                        anchors.fill: parent
                        anchors.margins: 1
                        model: exodosModel
                        spacing: 0
                        visible: !root.loading && exodosModel.count > 0
                        clip: true

                        ScrollBar.vertical: ScrollBar { }

                        delegate: Rectangle {
                            width: list.width; height: 50
                            color: ma.containsMouse ? Theme.hover : "transparent"
                            
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 20
                                height: 1
                                color: Theme.border
                                opacity: 0.1
                            }

                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true
                                onClicked: model.checked = !model.checked
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 15

                                TheophanyCheckBox {
                                    checked: model.checked
                                    onToggled: model.checked = checked
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        text: model.title
                                        color: Theme.text
                                        font.bold: true
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "No games found in the specified ExoDOS directory.\nMake sure you selected the parent of the 'eXo' folder."
                        color: Theme.secondaryText
                        horizontalAlignment: Text.AlignHCenter
                        visible: !root.loading && exodosModel.count === 0 && selectedPath !== ""
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: root.loading
                        visible: running
                    }
                }
            }
            
            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                Layout.topMargin: 5

                TheophanyButton {
                    text: "Close"
                    onClicked: root.close()
                }

                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: "Import Selected (" + selectedCount + ")"
                    primary: true
                    visible: exodosModel.count > 0
                    enabled: selectedCount > 0 && !root.loading
                    onClicked: {
                        var idx = platformSelector.currentIndex
                        if (idx < 0 || filteredPlatforms.count === 0) {
                            return
                        }
                        
                        var platformId = filteredPlatforms.get(idx).id
                        
                        if (platformId === "virtual_dos") {
                                var newId = "platform-" + Math.random().toString(36).substr(2, 9)
                                sidebar.platformModel.updateSystem(
                                    newId, "exoDOS", "", "", "", "DOS", "assets/systems/linux", ""
                                )
                                platformId = newId
                        }

                        var selectedRoms = []
                        for (var i = 0; i < exodosModel.count; i++) {
                            var item = exodosModel.get(i)
                            if (item.checked) {
                                selectedRoms.push({
                                    id: item.gameId,
                                    platform_id: platformId,
                                    path: item.path,
                                    filename: item.filename,
                                    file_size: 0,
                                    title: item.title,
                                    tags: item.tags || "exoDOS",
                                    is_installed: true
                                })
                            }
                        }
                        
                        if (selectedRoms.length > 0) {
                            // Initiation is enough, Main.qml handles the rest
                            root.close()
                            storeBridge.import_exodos_games(JSON.stringify(selectedRoms), platformId, selectedPath)
                        }
                    }
                }
            }
        }
    }
}
