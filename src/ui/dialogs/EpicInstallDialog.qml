import "../components"
import "../style"
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Theophany.Bridge 1.0

Dialog {
    id: root
    
    property string pendingAppId: ""
    property var appSettings
    property var platformModel
    property var storeBridge
    property string defaultPrefixDir: appSettings ? (appSettings.defaultProtonPrefix || "~/Games/theophany/default") : "~/Games/theophany/default"
    property string defaultInstallDir: appSettings ? (appSettings.defaultInstallLocation || "~/Games") : "~/Games"
    
    // New Properties for UI mapping
    property string gameTitleStr: pendingAppId
    property string installSizeStr: "Calculating..."
    property string cloudSavesStr: "Unknown"
    property var dlcsOwned: []
    property bool hasDlcs: dlcsOwned.length > 0
    property string defaultRunner: ""
    property bool loading: true

    // title: "Install Epic Game" (Removed to avoid duplicate with custom header)
    modal: true
    width: 650
    height: contentItem.implicitHeight + header.height
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: Rectangle {
        color: "transparent"
        height: 60
        Label {
            anchors.centerIn: parent
            text: "INSTALL EPIC GAME"
            font.bold: true
            font.pixelSize: 16
            font.letterSpacing: 1
            color: Theme.accent
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width - 60
            anchors.horizontalCenter: parent.horizontalCenter
            height: 1
            color: Theme.border
            opacity: 0.2
        }
    }
    
    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: Qt.rgba(0, 0, 0, 0.25)
            radius: 20
            samples: 41
        }
    }
    // Reset when opened
    onOpened: {
        loading = true;
        gameTitleStr = "";
        installPathInput.text = defaultInstallDir;
        prefixInput.text = defaultPrefixDir;
        installSizeStr = "";
        cloudSavesStr = "";
        dlcsOwned = [];
        dlcCheckbox.checked = false;
        
        // Fetch existing runner/prefix if already set in Database
        var configStr = storeBridge.get_epic_config("legendary-" + pendingAppId);
        try {
            var conf = JSON.parse(configStr);
            if (conf.prefix) prefixInput.text = conf.prefix;
            if (conf.runner) {
                defaultRunner = conf.runner;
                runnerCombo.currentIndex = runnerCombo.indexOfValue(conf.runner);
            } else {
                 // Try generic app settings
                 if (appSettings && appSettings.defaultProtonRunner) {
                     runnerCombo.currentIndex = runnerCombo.indexOfValue(appSettings.defaultProtonRunner);
                 } else {
                     runnerCombo.currentIndex = 0;
                 }
            }
        } catch(e) { }

        if (pendingAppId !== "")
            storeBridge.get_legendary_app_info(pendingAppId);

    }

    Connections {
        target: storeBridge
        
        function onLegendaryAppInfoReceived(json) {

            try {
                // The output might have log lines before the JSON, so let's try to extract just the JSON part
                var jsonStr = json;
                if (json.indexOf("{") > 0) {
                    jsonStr = json.substring(json.indexOf("{"));
                }
                var info = JSON.parse(jsonStr);
                
                if (info.error) {

                    installSizeStr = "Error fetching info";
                    gameTitleStr = root.pendingAppId;
                    loading = false;
                    return ;
                }
                
                // Set Title
                if (info.game && info.game.title) {
                    gameTitleStr = info.game.title;
                    
                    // Auto-generate a unique prefix folder if still using the fallback default
                    if (prefixInput.text === defaultPrefixDir) {
                        var safeTitle = gameTitleStr.replace(/[^a-zA-Z0-9]/g, "");
                        if (safeTitle.length > 0) {
                            var newPrefix = defaultPrefixDir.replace(/\/default$/, "/" + safeTitle);
                            prefixInput.text = newPrefix;
                        }
                    }
                }
                
                // Cloud Saves
                if (info.game && info.game.cloud_saves_supported !== undefined) {
                    cloudSavesStr = info.game.cloud_saves_supported ? "Yes" : "No";
                }

                // DLCs
                if (info.game && info.game.owned_dlc) {
                    dlcsOwned = info.game.owned_dlc;
                }

                if (info.manifest && info.manifest.disk_size) {
                    var bytes = info.manifest.disk_size;
                    var gb = (bytes / (1024 * 1024 * 1024)).toFixed(2);
                    installSizeStr = gb + " GB";
                } else {
                    installSizeStr = "Unknown";
                }
                loading = false;
            } catch (e) {

                installSizeStr = "Parse Error";
                loading = false;
            }
        }
    }

    ListModel { id: protonVersionsModel }

    Component.onCompleted: {
        protonVersionsModel.clear()
        protonVersionsModel.append({ "name": "Default (umu-run choice)", "path": "" })
        protonVersionsModel.append({ "name": "Auto (GE-Proton)", "path": "GE-Proton" })
        if (platformModel) {
            try {
                var versions = JSON.parse(platformModel.getProtonVersions())
                for (var i = 0; i < versions.length; i++) {
                    protonVersionsModel.append(versions[i])
                }
            } catch(e) {}
        }
    }

    FolderDialog {
        id: installPathDialog

        title: "Select Installation Folder"
        onAccepted: {
            installPathInput.text = installPathDialog.selectedFolder.toString().replace("file://", "");
        }
    }

    FolderDialog {
        id: prefixPathDialog

        title: "Select Wine Prefix Folder"
        onAccepted: {
            prefixInput.text = prefixPathDialog.selectedFolder.toString().replace("file://", "");
        }
    }

    contentItem: Item {
        implicitHeight: mainLayout.implicitHeight + 40
        
        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            // Game Info Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                
                Text {
                    text: "GAME INFORMATION"
                    color: Theme.accent
                    font.pixelSize: 10
                    font.bold: true
                    Layout.leftMargin: 5
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: infoColumn.implicitHeight + 40
                    color: Theme.background
                    radius: 10
                    border.color: Theme.border
                    border.width: 1

                    ColumnLayout {
                        id: infoColumn
                        anchors.centerIn: parent
                        width: parent.width - 40
                        spacing: 12

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 100
                            visible: root.loading

                            BusyIndicator {
                                id: loadSpinner
                                anchors.centerIn: parent
                                running: root.loading
                            }
                            Text {
                                anchors.horizontalCenter: loadSpinner.horizontalCenter
                                anchors.top: loadSpinner.bottom
                                anchors.topMargin: 10
                                text: "Fetching game info..."
                                color: Theme.secondaryText
                            }
                        }

                        Text {
                            text: root.gameTitleStr
                            color: Theme.text
                            font.pixelSize: 18
                            font.bold: true
                            visible: !root.loading
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                        }

                        RowLayout {
                            visible: !root.loading
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 40
                            
                            ColumnLayout {
                                spacing: 4
                                Layout.alignment: Qt.AlignHCenter
                                Text { 
                                    text: "SIZE"
                                    color: Theme.secondaryText
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text { 
                                    text: root.installSizeStr
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                spacing: 4
                                Layout.alignment: Qt.AlignHCenter
                                Text { 
                                    text: "CLOUD SAVES"
                                    color: Theme.secondaryText
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text { 
                                    text: root.cloudSavesStr
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter
                                    font.bold: true
                                }
                            }
                            
                            ColumnLayout {
                                spacing: 4
                                visible: root.hasDlcs
                                Layout.alignment: Qt.AlignHCenter
                                Text { 
                                    text: "OWNED DLCS"
                                    color: Theme.secondaryText
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text { 
                                    text: root.dlcsOwned.length
                                    color: Theme.text
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }

            // Configuration Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.topMargin: 10

                Text {
                    text: "INSTALLATION CONFIGURATION"
                    color: Theme.accent
                    font.pixelSize: 10
                    font.bold: true
                    Layout.leftMargin: 5
                }

                GridLayout {
                    columns: 3
                    rowSpacing: 15
                    columnSpacing: 15
                    Layout.fillWidth: true

                    // Install Path
                    Label {
                        text: "Install Location"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TheophanyTextField {
                        id: installPathInput
                        placeholderText: "Default location"
                        Layout.fillWidth: true
                    }

                    TheophanyButton {
                        text: "Browse"
                        Layout.preferredHeight: 38
                        onClicked: installPathDialog.open()
                    }

                    // Runner
                    Label {
                        text: "Runner"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TheophanyComboBox {
                        id: runnerCombo
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        model: protonVersionsModel
                        textRole: "name"
                        valueRole: "path"
                    }

                    // Prefix
                    Label {
                        text: "Wine Prefix"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TheophanyTextField {
                        id: prefixInput
                        placeholderText: "Wine prefix path"
                        Layout.fillWidth: true
                    }

                    TheophanyButton {
                        text: "Browse"
                        Layout.preferredHeight: 38
                        onClicked: prefixPathDialog.open()
                    }
                }
            }

            TheophanyCheckBox {
                id: dlcCheckbox
                text: "Install All Owned DLCs (" + root.dlcsOwned.length + ")"
                visible: root.hasDlcs
                checked: false
                Layout.topMargin: 5
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                TheophanyButton {
                    text: "Import Game"
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 45
                    onClicked: {
                        var pId = "legendary-" + root.pendingAppId;
                        var runner = runnerCombo.currentValue;
                        if (runner === undefined) runner = "";
                        var prefix = prefixInput.text.trim();
                        
                        if (runner !== "" || prefix !== "" || prefix !== root.defaultPrefixDir) {
                            if (prefix === "")
                                prefix = root.defaultPrefixDir;

                            storeBridge.save_epic_config(pId, runner, prefix);
                        }

                        if (typeof window !== "undefined" && window.importEpicGame) {
                            window.importEpicGame(pId)
                        }
                        root.close()
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                TheophanyButton {
                    text: "Cancel"
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 45
                    onClicked: root.close()
                }

                TheophanyButton {
                    text: "Install Now"
                    primary: true
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 45
                    onClicked: {
                        var pId = "legendary-" + root.pendingAppId;
                        var path = installPathInput.text.trim();
                        var runner = runnerCombo.currentValue;
                        if (runner === undefined) runner = "";
                        var prefix = prefixInput.text.trim();
                        var withDlcs = dlcCheckbox.checked;
                        
                        // Save config if runner or prefix provided
                        if (runner !== "" || prefix !== "" || prefix !== root.defaultPrefixDir) {
                            if (prefix === "")
                                prefix = root.defaultPrefixDir;

                            storeBridge.save_epic_config(pId, runner, prefix);
                        }
                        // Start install
                        storeBridge.install_legendary_game(root.pendingAppId, path, withDlcs);
                        root.close();
                    }
                }
            }
        }
    }
}
