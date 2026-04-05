import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root

    // Set by caller before open()
    property string slug: ""
    property string gameTitle: ""
    property var appSettings
    property var storeBridge
    property var platformModel

    property string defaultInstallDir: appSettings
        ? (appSettings.defaultInstallLocation || (Qt.resolvedUrl("~/Games").toString()))
        : "~/Games"
    property string defaultPrefixDir: appSettings
        ? (appSettings.defaultProtonPrefix || "~/Games/theophany/default")
        : "~/Games/theophany/default"

    property string defaultRunner: ""
    property bool isInstalling: false
    property bool loading: false
    property string installSizeStr: ""

    modal: true
    width: 620
    height: contentItem.implicitHeight + headerRect.height
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null

    onOpened: {
        isInstalling = false
        loading = true
        installSizeStr = ""
        installPathInput.text = defaultInstallDir
        var safeTitle = root.gameTitle.replace(/[^a-zA-Z0-9]/g, "")
        prefixInput.text = defaultPrefixDir.replace(/\/default$/, "/") + (safeTitle || root.slug)
        platformCombo.currentIndex = 0
        noDepsCheck.checked = false

        storeBridge.get_gog_app_info(root.slug);

        // Fetch existing runner/prefix if already set in Database
        var configStr = storeBridge.get_epic_config("gog-" + root.slug);
        try {
            var conf = JSON.parse(configStr);
            if (conf.prefix) prefixInput.text = conf.prefix;
            if (conf.runner) {
                defaultRunner = conf.runner;
                runnerCombo.currentIndex = runnerCombo.indexOfValue(conf.runner);
            } else {
                 if (appSettings && appSettings.defaultProtonRunner) {
                     runnerCombo.currentIndex = runnerCombo.indexOfValue(appSettings.defaultProtonRunner);
                 } else {
                     runnerCombo.currentIndex = 0;
                 }
            }
        } catch(e) { }
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

    Connections {
        target: storeBridge
        
        function onGogAppInfoReceived(text) {
            loading = false;
            // Extract raw byte size e.g. "size: 984612864"
            var sizeMatch = text.match(/size:\s*(\d+)/i);
            if (sizeMatch && sizeMatch.length >= 2) {
                var bytes = parseInt(sizeMatch[1]);
                if (!isNaN(bytes)) {
                    var mb = bytes / (1024 * 1024);
                    if (mb >= 1024) {
                        installSizeStr = (mb / 1024).toFixed(2) + " GB";
                    } else {
                        installSizeStr = mb.toFixed(2) + " MB";
                    }
                } else {
                    installSizeStr = "Unknown";
                }
            } else {
                installSizeStr = "Unknown";
            }
        }
    }

    // ── Header ───────────────────────────────────────────────────────────────
    Rectangle {
        id: headerRect
        width: parent.width
        height: 60
        color: "transparent"

        Label {
            anchors.centerIn: parent
            text: "INSTALL GOG GAME"
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

    ListModel { id: osPlatformModel }
    ListModel { id: protonVersionsModel }
    Component.onCompleted: {
        osPlatformModel.append({ "name": "Windows (Galaxy)",  "value": "windows" })
        osPlatformModel.append({ "name": "Linux (Galaxy)",    "value": "linux"   })
        
        protonVersionsModel.clear()
        protonVersionsModel.append({ "name": "Default (umu-run choice)", "path": "" })
        protonVersionsModel.append({ "name": "Auto (GE-Proton)", "path": "GE-Proton" })
        if (root.platformModel) {
            try {
                var versions = JSON.parse(root.platformModel.getProtonVersions())
                for (var i = 0; i < versions.length; i++) {
                    protonVersionsModel.append(versions[i])
                }
            } catch(e) {}
        }
    }

    FolderDialog {
        id: installPathDialog
        title: "Select Installation Folder"
        onAccepted: installPathInput.text = installPathDialog.selectedFolder.toString().replace("file://", "")
    }

    FolderDialog {
        id: prefixPathDialog
        title: "Select Wine Prefix Folder"
        onAccepted: prefixInput.text = prefixPathDialog.selectedFolder.toString().replace("file://", "")
    }

    FolderDialog {
        id: importPathDialog
        title: "Select Existing GOG Game Folder (containing .info file)"
        onAccepted: {
            var path = importPathDialog.selectedFolder.toString().replace("file://", "")
            storeBridge.import_gog_game(root.slug, path)
            root.close()
        }
    }

    contentItem: Item {
        implicitHeight: mainLayout.implicitHeight + 40

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            // Title block
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "GAME INFORMATION"
                    color: Theme.accent
                    font.pixelSize: 10
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 90
                    color: Theme.background
                    radius: 10
                    border.color: Theme.border
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            visible: root.loading

                            BusyIndicator {
                                anchors.centerIn: parent
                                running: root.loading
                                width: 24
                                height: 24
                            }
                        }

                        Text {
                            text: root.gameTitle || root.slug
                            color: Theme.text
                            font.pixelSize: 18
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            visible: !root.loading
                        }

                        RowLayout {
                            visible: !root.loading
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 30
                            
                            ColumnLayout {
                                spacing: 4
                                Layout.alignment: Qt.AlignHCenter
                                Text { 
                                    text: "STORE"
                                    color: Theme.secondaryText
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text { 
                                    text: "GOG (DRM-Free)"
                                    color: Theme.text
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignHCenter
                                    font.bold: true
                                }
                            }

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
                                    text: root.installSizeStr !== "" ? root.installSizeStr : "..."
                                    color: Theme.text
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignHCenter
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }

            // Configuration
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "INSTALLATION CONFIGURATION"
                    color: Theme.accent
                    font.pixelSize: 10
                    font.bold: true
                }

                GridLayout {
                    columns: 3
                    rowSpacing: 15
                    columnSpacing: 15
                    Layout.fillWidth: true

                    // Install path
                    Label {
                        text: "Install Location"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }
                    TheophanyTextField {
                        id: installPathInput
                        placeholderText: "~/Games/<slug>"
                        Layout.fillWidth: true
                    }
                    TheophanyButton {
                        text: "Browse"
                        Layout.preferredHeight: 38
                        onClicked: installPathDialog.open()
                    }

                    // Platform
                    Label {
                        text: "Platform"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }
                    TheophanyComboBox {
                        id: platformCombo
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        model: osPlatformModel
                        textRole: "name"
                        valueRole: "value"
                    }

                    // Runner (only relevant for Windows builds)
                    Label {
                        text: "Runner"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                        visible: platformCombo.currentIndex === 0
                    }
                    TheophanyComboBox {
                        id: runnerCombo
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        model: protonVersionsModel
                        textRole: "name"
                        valueRole: "path"
                        visible: platformCombo.currentIndex === 0
                    }

                    // Wine Prefix (only relevant for Windows builds)
                    Label {
                        text: "Wine Prefix"
                        color: Theme.secondaryText
                        font.bold: true
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                        visible: platformCombo.currentIndex === 0   // Windows only
                    }
                    TheophanyTextField {
                        id: prefixInput
                        placeholderText: "~/Games/theophany/<game>"
                        Layout.fillWidth: true
                        visible: platformCombo.currentIndex === 0
                    }
                    TheophanyButton {
                        text: "Browse"
                        Layout.preferredHeight: 38
                        onClicked: prefixPathDialog.open()
                        visible: platformCombo.currentIndex === 0
                    }
                }

                TheophanyCheckBox {
                    id: noDepsCheck
                    text: "Skip dependencies (--galaxy-no-dependencies)"
                    checked: false
                }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 10 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                TheophanyButton {
                    text: "Cancel"
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 45
                    onClicked: root.close()
                }

                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: "Import Existing"
                    Layout.preferredHeight: 45
                    enabled: !root.isInstalling
                    onClicked: {
                        // Save prefix and runner to pc_config for this ROM if Windows
                        if (platformCombo.currentIndex === 0) {
                            var runner = runnerCombo.currentValue;
                            if (runner === undefined) runner = "";
                            var prefix = prefixInput.text.trim()
                            if (prefix !== "" || runner !== "") {
                                var romId = "gog-" + root.slug
                                if (typeof storeBridge !== "undefined")
                                    storeBridge.save_epic_config(romId, runner, prefix)
                            }
                        }
                        importPathDialog.open()
                    }
                }

                TheophanyButton {
                    text: "Install Now"
                    primary: true
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 45
                    enabled: !root.isInstalling
                    onClicked: {
                        var path = installPathInput.text.trim()
                        if (path === "") path = defaultInstallDir

                        var platform = osPlatformModel.get(platformCombo.currentIndex).value

                        // Save prefix and runner to pc_config for this ROM if Windows
                        if (platformCombo.currentIndex === 0) {
                            var runner = runnerCombo.currentValue;
                            if (runner === undefined) runner = "";
                            var prefix = prefixInput.text.trim()
                            if (prefix !== "" || runner !== "") {
                                // Reuse store_bridge's save_epic_config pattern
                                var romId = "gog-" + root.slug
                                if (typeof storeBridge !== "undefined")
                                    storeBridge.save_epic_config(romId, runner, prefix)
                            }
                        }

                        root.isInstalling = true

                        storeBridge.install_gog_game(root.slug, path, platform, noDepsCheck.checked)
                        root.close()
                    }
                }
            }
        }
    }
}

