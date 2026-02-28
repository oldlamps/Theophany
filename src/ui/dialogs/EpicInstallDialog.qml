import "../components"
import "../style"
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Theophany.Bridge 1.0

Dialog {
    id: root
    
    property string pendingAppId: ""
    property var appSettings
    property var platformModel
    property var storeBridge
    property string defaultPrefixDir: appSettings ? (appSettings.defaultProtonPrefix || "~/Games/theophany/default") : "~/Games/theophany/default"
    
    // New Properties for UI mapping
    property string gameTitleStr: pendingAppId
    property string installSizeStr: "Calculating..."
    property string cloudSavesStr: "Unknown"
    property var dlcsOwned: []
    property bool hasDlcs: dlcsOwned.length > 0
    property string defaultRunner: ""
    property bool loading: true

    title: "Install Epic Game"
    modal: true
    width: 650
    height: mainLayout.implicitHeight + 60
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null
    // Reset when opened
    onOpened: {
        loading = true;
        gameTitleStr = "";
        installPathInput.text = "";
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
            console.log("LegendaryAppInfoReceived output length: " + json.length);
            try {
                // The output might have log lines before the JSON, so let's try to extract just the JSON part
                var jsonStr = json;
                if (json.indexOf("{") > 0) {
                    jsonStr = json.substring(json.indexOf("{"));
                }
                var info = JSON.parse(jsonStr);
                
                if (info.error) {
                    console.log("legendary error:", info.error);
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
                console.log("EpicInstallDialog JSON parse error:", e);
                console.log("Raw output was:", jsonStr);
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

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        Text {
            text: "Install Epic Game"
            color: Theme.text
            font.pixelSize: 22
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 10
        }

        // Game Info Section
        GroupBox {
            title: "Game Information"
            Layout.fillWidth: true
            font.pixelSize: 14
            palette.windowText: Theme.text

            ColumnLayout {
                width: parent.width
                spacing: 5

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
                    text: "Title: " + root.gameTitleStr
                    color: Theme.text
                    font.pixelSize: 16
                    font.bold: true
                    visible: !root.loading
                }

                Text {
                    text: "Estimated Size: " + root.installSizeStr
                    color: Theme.text
                    font.pixelSize: 14
                    visible: !root.loading
                }

                Text {
                    text: "Cloud Saves: " + root.cloudSavesStr
                    color: Theme.text
                    font.pixelSize: 14
                    visible: !root.loading
                }
                
                Text {
                    text: "Owned DLCs: " + root.dlcsOwned.length
                    color: Theme.text
                    font.pixelSize: 14
                    visible: !root.loading && root.hasDlcs
                }
            }
        }

        // Configuration Section
        GroupBox {
            title: "Installation Configuration"
            Layout.fillWidth: true
            font.pixelSize: 14
            palette.windowText: Theme.text

            GridLayout {
                columns: 3
                rowSpacing: 10
                columnSpacing: 10
                Layout.fillWidth: true

                // Install Path
                Text {
                    text: "Install Location:"
                    color: Theme.text
                    font.pixelSize: 14
                }

                TextField {
                    id: installPathInput

                    placeholderText: "Default location"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100
                    Layout.preferredWidth: 250
                    Layout.maximumWidth: 400
                    clip: true
                    color: Theme.text

                    background: Rectangle {
                        color: Theme.background
                        border.color: Theme.border
                        radius: 4
                    }
                }

                Button {
                    text: "Browse..."
                    onClicked: installPathDialog.open()
                }

                // Runner
                Text {
                    text: "Runner (Proton/Wine):"
                    color: Theme.text
                    font.pixelSize: 14
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
                Text {
                    text: "Wine Prefix:"
                    color: Theme.text
                    font.pixelSize: 14
                }

                TextField {
                    id: prefixInput

                    placeholderText: "Wine prefix path"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100
                    Layout.preferredWidth: 250
                    Layout.maximumWidth: 400
                    clip: true
                    color: Theme.text

                    background: Rectangle {
                        color: Theme.background
                        border.color: Theme.border
                        radius: 4
                    }
                }

                Button {
                    text: "Browse..."
                    onClicked: prefixPathDialog.open()
                }

            }

        }

        CheckBox {
            id: dlcCheckbox
            text: "Install All Owned DLCs (" + root.dlcsOwned.length + ")"
            visible: root.hasDlcs
            checked: false
        }

        // Spacer
        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                text: "Import Game"
                Layout.preferredWidth: 100
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

            Button {
                text: "Cancel"
                Layout.preferredWidth: 100
                onClicked: root.close()
            }

            Button {
                text: "Install"
                highlighted: true
                Layout.preferredWidth: 100
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

                background: Rectangle {
                    color: Theme.accent
                    radius: 4
                }

            }

        }

    }

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        radius: 12
    }

}
