import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../style"
import "../components"
import Theophany.Bridge 1.0

Dialog {
    id: root
    width: Math.min(1000, parent.width * 0.9)
    height: Math.min(800, parent.height * 0.85)
    modal: true
    anchors.centerIn: parent
    background: null
    closePolicy: Popup.NoAutoClose
    
    property int currentStep: 0
    property int totalSteps: 4 // Appearance, RetroAchievements, Getting Started, Finalizing
    
    // Bridge instances
    property var raBridge: null
    property var appSettings: null
    
    property bool ytdlpFound: false
    property string ytdlpVersion: ""
    property string ytdlpPath: ""

    AppInfo { id: appInfo }

    function checkYtdlp() {
        var customPath = appSettings && appSettings.useCustomYtdlp ? appSettings.customYtdlpPath : ""
        var result = JSON.parse(appInfo.checkYtdlp(customPath))
        ytdlpFound = result.found
        if (ytdlpFound) {
            ytdlpVersion = result.version
            ytdlpPath = result.path
        } else {
            ytdlpVersion = ""
            ytdlpPath = ""
        }
    }

    Component.onCompleted: {
        checkYtdlp()
    }
    
    signal loginRequested(string username, string key)

    contentItem: Rectangle {
        id: mainRect
        color: Theme.background
        radius: 12
        border.color: Theme.border
        border.width: 1
        clip: true

        // Header
        Rectangle {
            id: header
            width: parent.width
            height: 70
            color: Theme.secondaryBackground
            radius: 12
            
            // Mask upper corners
            Rectangle {
                width: parent.width
                height: 12
                color: parent.color
                anchors.bottom: parent.bottom
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 30
                spacing: 15

                Text {
                    text: "Welcome to"
                    visible: root.currentStep === 0
                    color: Theme.text
                    font.pixelSize: 24
                    font.bold: true
                }

                TheophanyLogo {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 40
                    Layout.topMargin: 4
                }

                Text {
                    text: root.currentStep === 1 ? "Connect Linked Accounts" : 
                          root.currentStep === 2 ? "Getting Started Guide" :
                          root.currentStep === 3 ? "You're All Set!" : ""
                    visible: root.currentStep > 0
                    color: Theme.text
                    font.pixelSize: 24
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Item { 
                    visible: root.currentStep === 0
                    Layout.fillWidth: true 
                }
                
                Text {
                    text: (root.currentStep + 1) + " / " + root.totalSteps
                    color: Theme.secondaryText
                    font.pixelSize: 16
                    font.bold: true
                }
            }
        }

        // Content Area (Stack-like)
        Item {
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 0 // Reset margins for full width scrolling

            // Step 0: Appearance
            ScrollView {
                visible: root.currentStep === 0
                anchors.fill: parent
                anchors.margins: 40 // Apply margins inside scroll view
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 30

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 15
                        
                        Text {
                            text: "Choose Your Style"
                            color: Theme.text
                            font.pixelSize: 24
                            font.bold: true
                        }

                        Text {
                            text: "Select a theme and your preferred default view mode to get started."
                            color: Theme.secondaryText
                            font.pixelSize: 16
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 15
                        
                        Text {
                            text: "Themes"
                            color: Theme.text
                            font.pixelSize: 18
                            font.bold: true
                        }

                        Flow {
                            id: themeFlow
                            Layout.fillWidth: true
                            spacing: 15

                            Repeater {
                                model: ["System", "Default", "Nord", "Latte", "Frost", "Pearl", "Tokyo Night", "Catppuccin", "Dracula", "One Dark Pro", "Gruvbox Dark", "That 70's Theme", "That 70's Theme Light", "That 80's Theme", "That 80's Theme Light", "That 90's Theme", "That 90's Theme Light"]
                                
                                delegate: Rectangle {
                                    width: 140
                                    height: 80
                                    color: (Theme.themes[modelData] ? Theme.themes[modelData].background : "#000")
                                    radius: 8
                                    border.color: appSettings && appSettings.themeName === modelData ? Theme.accent : Theme.border
                                    border.width: appSettings && appSettings.themeName === modelData ? 3 : 1
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (appSettings) appSettings.themeName = modelData
                                            Theme.setTheme(modelData)
                                        }
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        
                                        Rectangle {
                                            width: 40
                                            height: 4
                                            color: (Theme.themes[modelData] ? Theme.themes[modelData].accent : "#000")
                                            radius: 2
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Text {
                                            text: modelData
                                            color: (Theme.themes[modelData] ? Theme.themes[modelData].text : "#fff")
                                            font.pixelSize: 11
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            width: 120
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 40

                        ColumnLayout {
                            spacing: 12
                            Text { text: "Default View"; color: Theme.text; font.bold: true }
                            RowLayout {
                                spacing: 15
                                ViewToggle {
                                    currentViewMode: appSettings ? appSettings.defaultView : 0
                                    onViewChanged: (mode) => { if(appSettings) appSettings.defaultView = mode }
                                }
                                Text { 
                                    text: appSettings && appSettings.defaultView === 0 ? "Grid View" : "List View"
                                    color: Theme.text 
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 12
                            Text { text: "System Options"; color: Theme.text; font.bold: true }
                            TheophanySwitch {
                                text: "Show Tray Icon"
                                checked: appSettings ? appSettings.showTrayIcon : false
                                onToggled: {
                                    if (appSettings) {
                                        appSettings.showTrayIcon = checked
                                    }
                                }
                            }
                            TheophanySwitch {
                                text: "Close to Tray"
                                checked: appSettings ? appSettings.closeToTray : false
                                onToggled: {
                                    if (appSettings) {
                                        appSettings.closeToTray = checked
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { height: 1; Layout.fillWidth: true; color: Theme.border; opacity: 0.3 }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 15
                        
                        Text {
                            text: "Media Tools"
                            color: Theme.text
                            font.pixelSize: 18
                            font.bold: true
                        }

                        RowLayout {
                            spacing: 15
                            Layout.fillWidth: true
                            
                            Rectangle {
                                width: 12
                                height: 12
                                radius: 6
                                color: root.ytdlpFound ? "#00ff88" : "#ff4444"
                            }
                            
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "yt-dlp " + (root.ytdlpFound ? "(Detected)" : "(Not Found)")
                                    color: Theme.text
                                    font.bold: true
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: root.ytdlpFound ? "Version: " + root.ytdlpVersion : "Required for video trailer downloads."
                                    color: Theme.secondaryText
                                    font.pixelSize: 12
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 10
                            Layout.fillWidth: true
                            
                            TheophanySwitch {
                                text: "Use custom yt-dlp binary"
                                checked: appSettings ? appSettings.useCustomYtdlp : false
                                onToggled: {
                                    if (appSettings) {
                                        appSettings.useCustomYtdlp = checked
                                        root.checkYtdlp()
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 10
                                Layout.fillWidth: true
                                visible: appSettings && appSettings.useCustomYtdlp
                                
                                TheophanyTextField {
                                    Layout.fillWidth: true
                                    placeholderText: "/usr/bin/yt-dlp"
                                    text: appSettings ? appSettings.customYtdlpPath : ""
                                    onTextChanged: {
                                        if (appSettings) {
                                            appSettings.customYtdlpPath = text
                                            root.checkYtdlp()
                                        }
                                    }
                                }
                                
                                TheophanyButton {
                                    text: "Check"
                                    Layout.preferredHeight: 36
                                    onClicked: root.checkYtdlp()
                                }
                            }
                        }
                    }
                    
                    Item { Layout.preferredHeight: 20 } // Bottom padding
                }
            }

            // Step 1: RetroAchievements (The "Card")
            ColumnLayout {
                visible: root.currentStep === 1
                anchors.fill: parent
                anchors.margins: 40
                spacing: 20

                // Premium Card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.secondaryBackground
                    radius: 16
                    border.color: Theme.border
                    clip: true

                    // Gradient Background
                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(0, 0)
                        end: Qt.point(width, height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.1) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 40
                        spacing: 40

                        // Left: Info
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 20

                            Image {
                                source: "qrc:/ui/assets/RA.png"
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 80
                                smooth: true
                            }

                            Text {
                                text: "Level Up Your Library"
                                color: Theme.text
                                font.pixelSize: 28
                                font.bold: true
                            }

                            Text {
                                text: "Connect to RetroAchievements to track progress, earn badges, and compete on global leaderboards. It's also a preferred source for high-quality game art and metadata."
                                color: Theme.secondaryText
                                font.pixelSize: 16
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                lineHeight: 1.4
                            }

                            ColumnLayout {
                                spacing: 12
                                Layout.topMargin: 10
                                RowLayout {
                                    spacing: 10
                                    Rectangle { width: 8; height: 8; radius: 4; color: Theme.accent }
                                    Text { text: "Earn achievements & points"; color: Theme.secondaryText; font.pixelSize: 15 }
                                }
                                RowLayout {
                                    spacing: 10
                                    Rectangle { width: 8; height: 8; radius: 4; color: Theme.accent }
                                    Text { text: "Compete on Leaderboards"; color: Theme.secondaryText; font.pixelSize: 15 }
                                }
                                RowLayout {
                                    spacing: 10
                                    Rectangle { width: 8; height: 8; radius: 4; color: Theme.accent }
                                    Text { text: "Automatic media & metadata fetching"; color: Theme.secondaryText; font.pixelSize: 15 }
                                }
                            }
                            
                            Item { Layout.fillHeight: true }

                            RowLayout {
                                spacing: 20
                                Text {
                                    text: "Don't have an account?"
                                    color: Theme.secondaryText
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: "Sign Up Here"
                                    color: Theme.accent
                                    font.pixelSize: 14
                                    font.underline: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://retroachievements.org/createaccount.php")
                                    }
                                }
                            }
                        }

                        // Right: Login Box
                        Rectangle {
                            Layout.preferredWidth: 350
                            Layout.fillHeight: true
                            color: Theme.background
                            radius: 12
                            border.color: Theme.border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 30
                                spacing: 25

                                Text {
                                    text: "Connect Account"
                                    color: Theme.text
                                    font.pixelSize: 20
                                    font.bold: true
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text { text: "Username"; color: Theme.secondaryText; font.pixelSize: 13 }
                                    TheophanyTextField {
                                        id: raUserField
                                        Layout.fillWidth: true
                                        placeholderText: "Enter username"
                                        text: appSettings ? appSettings.retroAchievementsUser : ""
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Web API Key"; color: Theme.secondaryText; font.pixelSize: 13 }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "Get Key"; color: Theme.accent; font.pixelSize: 13
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Qt.openUrlExternally("https://retroachievements.org/settings")
                                            }
                                        }
                                    }
                                    TheophanyTextField {
                                        id: raPassField
                                        Layout.fillWidth: true
                                        placeholderText: "••••••••••••••••"
                                        echoMode: TextField.Password
                                        text: appSettings ? appSettings.retroAchievementsToken : ""
                                    }
                                }

                                Text {
                                    id: raErrorText
                                    visible: text !== ""
                                    text: ""
                                    color: "#ff4444"
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                TheophanyButton {
                                    id: raLoginBtn
                                    Layout.fillWidth: true
                                    text: "Login & Connect"
                                    Layout.preferredHeight: 40
                                    iconSource: "qrc:/ui/assets/RA.png"
                                    enabled: raUserField.text !== "" && raPassField.text !== ""
                                    onClicked: {
                                        raErrorText.text = ""
                                        // Emit signal for Main.qml to handle
                                        root.loginRequested(raUserField.text, raPassField.text)
                                    }
                                }

                                RowLayout {
                                    visible: appSettings && appSettings.retroAchievementsEnabled
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#00ff88" }
                                    Text { text: "Connected as " + (appSettings ? appSettings.retroAchievementsUser : ""); color: "#00ff88"; font.pixelSize: 13; font.bold: true }
                                }
                                
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // Step 2: Getting Started Guide
            ColumnLayout {
                visible: root.currentStep === 2
                anchors.fill: parent
                anchors.margins: 40
                spacing: 30

                Text {
                    text: "How to use Theophany"
                    color: Theme.text
                    font.pixelSize: 28
                    font.bold: true
                }

                // Alpha Disclaimer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    color: Qt.alpha(Theme.accent, 0.1)
                    radius: 8
                    border.color: Theme.accent
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 15
                        Text {
                            text: "⚠️"
                            font.pixelSize: 20
                        }
                        Text {
                            text: "Theophany is currently in Alpha. Your feedback is vital to our growth! Please report bugs or suggest features on our community channels."
                            color: Theme.text
                            font.pixelSize: 14
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                GridLayout {
                   columns: 2
                   Layout.fillWidth: true
                   Layout.fillHeight: true
                   columnSpacing: 30
                   rowSpacing: 20

                   Repeater {
                       model: [
                           { step: "1", title: "Import & Create Collections", desc: "Click the + button in the sidebar to add new systems, or drag-and-drop your ROM folders and files directly into the window." },
                           { step: "2", title: "Configure Emulators", desc: "Set up your preferred emulators in the Emulator Manager and link them to your collections for seamless launching." },
                           { step: "3", title: "Enrich Library", desc: "Use Shift+A to automatically fetch high-quality metadata and box art. You can also bulk-edit games to keep your library organized." },
                           { step: "4", title: "Connect with the Community", desc: "Join our community on Reddit (/r/theophanyGG) and GitHub to stay updated, report bugs, or request new features!" }
                       ]

                       delegate: RowLayout {
                           Layout.fillWidth: true
                           Layout.preferredHeight: 80
                           spacing: 20

                           Rectangle {
                               width: 50
                               height: 50
                               radius: 25
                               color: Theme.accent
                               Text {
                                   anchors.centerIn: parent
                                   text: modelData.step
                                   font.pixelSize: 24
                                   font.bold: true
                                   color: "white"
                               }
                           }

                           ColumnLayout {
                               spacing: 5
                               Layout.fillWidth: true
                               Text {
                                   text: modelData.title
                                   color: Theme.text
                                   font.pixelSize: 18
                                   font.bold: true
                               }
                               Text {
                                   text: modelData.desc
                                   color: Theme.secondaryText
                                   font.pixelSize: 14
                                   wrapMode: Text.WordWrap
                                   Layout.fillWidth: true
                               }
                           }
                       }
                   }
                }
            }

            // Step 3: Finalizing
            ColumnLayout {
                visible: root.currentStep === 3
                anchors.fill: parent
                spacing: 30

                TheophanyLogo {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 160
                    Layout.alignment: Qt.AlignCenter
                }

                Text {
                    text: "You're All Set!"
                    color: Theme.text
                    font.pixelSize: 32
                    font.bold: true
                    Layout.alignment: Qt.AlignCenter
                }

                Text {
                    text: "You can always change these settings and many more later in the settings menu."
                    color: Theme.secondaryText
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.preferredWidth: 600
                    Layout.alignment: Qt.AlignCenter
                }

                Text {
                    text: "Press 'Let's Go' to begin"
                    color: Theme.secondaryText
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignCenter
                }
                
                Item { Layout.fillHeight: true }
            }
        }

        // Footer
        Rectangle {
            id: footer
            width: parent.width
            height: 90
            color: Theme.secondaryBackground
            radius: 12
            anchors.bottom: parent.bottom
            
            // Mask lower corners
            Rectangle {
                width: parent.width
                height: 12
                color: parent.color
                anchors.top: parent.top
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                spacing: 20

                TheophanyButton {
                    text: "Previous"
                    visible: root.currentStep > 0
                    width: 120
                    Layout.preferredHeight: 45
                    onClicked: root.currentStep--
                }

                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: root.currentStep === 3 ? "Let's Go!" : "Next"
                    width: 160
                    Layout.preferredHeight: 45
                    primary: true
                    onClicked: {
                        if (root.currentStep < 3) {
                            root.currentStep++
                        } else {
                            if (appSettings) {
                                appSettings.firstRunCompleted = true
                                if (appSettings.retroAchievementsEnabled) {
                                    // Ensure user/token are saved one last time
                                    appSettings.retroAchievementsUser = raUserField.text
                                    appSettings.retroAchievementsToken = raPassField.text
                                }
                                appSettings.save()
                            }
                            root.close()
                        }
                    }
                }
            }
        }
    }
    
    Connections {
        target: raBridge
        function onLoginSuccess(u) {
            raErrorText.text = ""
            // Persistence is now handled by Main.qml before login is even attempted
        }
        function onLoginError(m) {
            raErrorText.text = m
            if (appSettings) {
                appSettings.retroAchievementsEnabled = false
            }
        }
    }
}
