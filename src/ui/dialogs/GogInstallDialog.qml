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

    property string defaultInstallDir: appSettings
        ? (appSettings.defaultInstallLocation || (Qt.resolvedUrl("~/Games").toString()))
        : "~/Games"
    property string defaultPrefixDir: appSettings
        ? (appSettings.defaultProtonPrefix || "~/Games/theophany/default")
        : "~/Games/theophany/default"

    property bool isInstalling: false

    modal: true
    width: 620
    height: contentItem.implicitHeight + headerRect.height
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: Dialog.NoButton
    header: null

    onOpened: {
        isInstalling = false
        installPathInput.text = defaultInstallDir
        var safeTitle = root.gameTitle.replace(/[^a-zA-Z0-9]/g, "")
        prefixInput.text = defaultPrefixDir.replace(/\/default$/, "/") + (safeTitle || root.slug)
        platformCombo.currentIndex = 0
        noDepsCheck.checked = false
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

    ListModel { id: platformModel }
    Component.onCompleted: {
        platformModel.append({ "name": "Windows (Galaxy)",  "value": "windows" })
        platformModel.append({ "name": "Linux (Galaxy)",    "value": "linux"   })
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
                    height: 70
                    color: Theme.background
                    radius: 10
                    border.color: Theme.border
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: root.gameTitle || root.slug
                            color: Theme.text
                            font.pixelSize: 18
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            text: "GOG · DRM Free"
                            color: Theme.accent
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
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
                        model: platformModel
                        textRole: "name"
                        valueRole: "value"
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
                    text: "Install Now"
                    primary: true
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 45
                    enabled: !root.isInstalling
                    onClicked: {
                        var path = installPathInput.text.trim()
                        if (path === "") path = defaultInstallDir

                        var platform = platformModel.get(platformCombo.currentIndex).value

                        // Save prefix to pc_config for this ROM if Windows
                        if (platformCombo.currentIndex === 0) {
                            var prefix = prefixInput.text.trim()
                            if (prefix !== "") {
                                // Reuse store_bridge's save_epic_config pattern
                                var romId = "gog-" + root.slug
                                if (typeof storeBridge !== "undefined")
                                    storeBridge.save_epic_config(romId, "", prefix)
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

