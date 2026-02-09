import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "Import Local Apps"
    modal: true
    width: Overlay.overlay ? Math.min(Overlay.overlay.width * 0.7, 800) : 700
    height: Overlay.overlay ? Math.min(Overlay.overlay.height * 0.8, 700) : 600
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
        onLocalAppsFinished: (resultsJson) => {

            var results = JSON.parse(resultsJson)
            localModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                var sanitized = {
                    "id": item.id || "",
                    "title": item.title || "Unknown",
                    "path": item.path || "",
                    "filename": item.filename || "",
                    "icon_path": item.icon_path || ""
                }
                localModel.append(sanitized)
            }
            loading = false

        }
        onInstallFinished: (appName, success, message) => {

            if (success) {
                gameModel.refresh()
            } else {
                errorDialog.text = "Failed to import " + appName + ":\n" + message
                errorDialog.open()
            }
        }
    }

    Connections {
        target: addSystemDialog
        function onSystemConfigured() {
            if (root.visible) refreshFilteredPlatforms()
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: storeBridge.poll()
    }

    property bool loading: false
    ListModel { id: localModel }
    ListModel { id: filteredPlatforms }

    function refreshFilteredPlatforms() {
        filteredPlatforms.clear()
        if (!sidebar || !sidebar.platformModel) return;
        
        for (var i = 0; i < sidebar.platformModel.rowCount(); i++) {
            var idx = sidebar.platformModel.index(i, 0)
            var name = sidebar.platformModel.data(idx, 257) || ""
            var type = sidebar.platformModel.data(idx, 261) || ""
            filteredPlatforms.append({
                "name": name,
                "id": sidebar.platformModel.data(idx, 256)
            })
        }
        
        for (var j = 0; j < filteredPlatforms.count; j++) {
            if (filteredPlatforms.get(j).name.indexOf("PC (Linux)") !== -1 || filteredPlatforms.get(j).name.indexOf("PC (Windows)") !== -1) {
                platformSelector.currentIndex = j
                break
            }
        }
    }

    function openImport() {

        loading = true
        storeBridge.refresh_local_apps()
        refreshFilteredPlatforms()
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
                text: "Import Local Apps"
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
            }

            Rectangle { 
                Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.5 
            }

            Text {
                text: "Select a collection and games to add to your library."
                color: Theme.secondaryText
                font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "Import to:"; color: Theme.text; font.pixelSize: 13 }
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
                        addSystemDialog.openAddWithType("linux", "Local Apps")
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.3 }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    model: localModel
                    spacing: 8
                    clip: true
                    visible: !root.loading && localModel.count > 0

                    ScrollBar.vertical: TheophanyScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        width: list.width; height: 64
                        color: ma.containsMouse ? Theme.hover : Theme.sidebar
                        radius: 8
                        border.color: Theme.border
                        border.width: 1

                        MouseArea {
                            id: ma; anchors.fill: parent; hoverEnabled: true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 15

                            Rectangle {
                                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignVCenter
                                color: "transparent"
                                
                                Image {
                                    id: iconImg
                                    anchors.fill: parent
                                    source: icon_path ? "file://" + storeBridge.find_icon_path(icon_path) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "🎮"
                                    font.pixelSize: 20
                                    visible: iconImg.status !== Image.Ready
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                Text {
                                    text: title
                                    color: Theme.text
                                    font.bold: true
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: path
                                    color: Theme.secondaryText
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            TheophanyButton {
                                text: "Import"
                                primary: true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredHeight: 32
                                onClicked: {
                                    var idx = platformSelector.currentIndex
                                    if (idx < 0) return
                                    
                                    var platformId = filteredPlatforms.get(idx).id
                                    var rom = {
                                        id: id,
                                        platform_id: platformId,
                                        path: path,
                                        filename: filename,
                                        file_size: 0,
                                        title: title,
                                        icon_path: icon_path || ""
                                    }
                                    storeBridge.import_local_app(JSON.stringify(rom), platformId)
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "No local games found in standard directories."
                    color: Theme.secondaryText
                    visible: !root.loading && localModel.count === 0
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    running: root.loading
                    visible: running
                }
            }
            
            TheophanyButton {
                text: "Close"
                Layout.alignment: Qt.AlignRight
                onClicked: root.close()
            }
        }
    }

    TheophanyMessageDialog {
        id: errorDialog
        title: "Import Error"
        // buttons: Dialog.Ok // Default
    }
}
