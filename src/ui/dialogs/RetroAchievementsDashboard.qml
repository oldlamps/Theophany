import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Dialog {
    id: root
    width: Math.min(800, window.width * 0.9)
    height: Math.min(700, window.height * 0.9)
    modal: true
    title: "RetroAchievements Dashboard"

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    background: Rectangle {
        color: Theme.secondaryBackground
        border.color: Theme.border
        border.width: 1
        radius: 12
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
        }
    }

    header: Item { height: 0 } // Custom header

    contentItem: ColumnLayout {
        spacing: 0
        
        // Header / Profile Section
        Rectangle {
            id: profileHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            color: "transparent"
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 25

                // Big Profile Pic
                Rectangle {
                    Layout.preferredWidth: 120; Layout.preferredHeight: 120
                    radius: 60
                    color: Theme.background
                    border.color: Theme.accent
                    border.width: 3
                    clip: true
                    
                    Image {
                        anchors.fill: parent
                        source: window.raProfilePic
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    Text {
                        text: window.raUserSummary ? window.raUserSummary.User : "User"
                        color: Theme.text
                        font.bold: true
                        font.pixelSize: 32
                    }
                    
                    Text {
                        text: (window.raUserSummary && window.raUserSummary.Motto) ? window.raUserSummary.Motto : ""
                        color: Theme.secondaryText
                        font.italic: true
                        font.pixelSize: 14
                        visible: text !== ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }


                    RowLayout {
                        spacing: 20
                        Text {
                            text: "Rank: #" + (window.raUserSummary && window.raUserSummary.Rank !== null ? window.raUserSummary.Rank : "---")
                            color: Theme.accent
                            font.bold: true
                            font.pixelSize: 18
                        }
                        Text {
                            text: "Hardcore: " + (window.raUserSummary && window.raUserSummary.TotalPoints !== null ? window.raUserSummary.TotalPoints : "0")
                            color: Theme.accent
                            font.bold: true
                            font.pixelSize: 18
                        }
                        Text {
                            text: "Softcore: " + (window.raUserSummary && window.raUserSummary.TotalSoftcorePoints !== null ? window.raUserSummary.TotalSoftcorePoints : "0")
                            color: Theme.secondaryText
                            font.bold: true
                            font.pixelSize: 18
                        }
                        Text {
                            text: "Ranked: " + (window.raUserSummary && window.raUserSummary.TotalRanked !== null ? window.raUserSummary.TotalRanked : "0")
                            color: Theme.accent
                            font.bold: true
                            font.pixelSize: 18
                        }
                    }
                }
            }
            
            TheophanyButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                text: "✕"
                Layout.preferredWidth: 40
                onClicked: root.close()
            }
        }

        // Stats Row
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: Theme.hover
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 40
                Layout.alignment: Qt.AlignHCenter

                Column {
                    Label { text: "MEMBER SINCE"; font.pixelSize: 10; color: Theme.secondaryText; font.bold: true }
                    Label { 
                        text: (window.raUserSummary && window.raUserSummary.MemberSince) ? window.raUserSummary.MemberSince.split(' ')[0] : "---"
                        color: Theme.text
                        font.bold: true 
                    }
                }
                Column {
                    Label { text: "STATUS"; font.pixelSize: 10; color: Theme.secondaryText; font.bold: true }
                    Label { 
                        text: window.raUserSummary ? "Online" : "---"
                        color: Theme.accent
                        font.bold: true 
                    }
                }
                Column {
                    Label { text: "TRUE POINTS"; font.pixelSize: 10; color: Theme.secondaryText; font.bold: true }
                    Label { 
                        text: (window.raUserSummary && window.raUserSummary.TotalTruePoints !== null) ? window.raUserSummary.TotalTruePoints : "---"
                        color: Theme.text
                        font.bold: true 
                    }
                }
            }
        }

        // Main Content Area (Recent Games)
        Label {
            text: "RECENTLY PLAYED"
            font.bold: true
            font.pixelSize: 14
            color: Theme.secondaryText
            Layout.margins: 20
            Layout.topMargin: 20
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: -1
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ListView {
                id: recentGamesList
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12
                model: window.raUserSummary ? window.raUserSummary.RecentlyPlayed : []
                delegate: Rectangle {
                    id: delegateRoot
                    width: recentGamesList.width - 20
                    height: (index === 0 && window.raUserSummary && window.raUserSummary.RichPresenceMsg) ? 160 : 120
                    color: Theme.background
                    radius: 8
                    border.color: Theme.border
                    border.width: 1

                    property var awardedData: (window.raUserSummary && window.raUserSummary.Awarded) ? window.raUserSummary.Awarded[modelData.GameID.toString()] : null
                    property var gameAchievements: (window.raUserSummary && window.raUserSummary.RecentAchievements) ? window.raUserSummary.RecentAchievements[modelData.GameID.toString()] : null
                    property var latestAch: {
                        if (!gameAchievements) return null
                        var keys = Object.keys(gameAchievements)
                        if (keys.length === 0) return null
                        return gameAchievements[keys[keys.length - 1]]
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 20

                        Image {
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 80
                            source: "https://media.retroachievements.org" + modelData.ImageIcon
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            // Rich Presence for first item
                            Text {
                                text: (index === 0 && window.raUserSummary && window.raUserSummary.RichPresenceMsg) ? window.raUserSummary.RichPresenceMsg : ""
                                color: Theme.accent
                                font.pixelSize: 13
                                font.bold: true
                                visible: text !== ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    color: Theme.accent
                                    opacity: 0.1
                                    radius: 4
                                    z: -1
                                }
                            }

                            Text {
                                text: modelData.Title
                                color: Theme.text
                                font.bold: true
                                font.pixelSize: 18
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            
                            RowLayout {
                                spacing: 10
                                Text {
                                    text: modelData.ConsoleName
                                    color: Theme.secondaryText
                                    font.pixelSize: 12
                                }
                                
                                // Progress Bar
                                Item {
                                    Layout.preferredWidth: 150
                                    Layout.preferredHeight: 14
                                    visible: delegateRoot.awardedData !== null && delegateRoot.awardedData.NumPossibleAchievements > 0
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Theme.hover
                                        radius: 7
                                        
                                        Rectangle {
                                            width: parent.width * (delegateRoot.awardedData ? (delegateRoot.awardedData.NumAchieved / delegateRoot.awardedData.NumPossibleAchievements) : 0)
                                            height: parent.height
                                            color: Theme.accent
                                            radius: 7
                                        }
                                    }
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: delegateRoot.awardedData ? (delegateRoot.awardedData.NumAchieved + "/" + delegateRoot.awardedData.NumPossibleAchievements) : ""
                                        color: "white"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }

                                RowLayout {
                                    visible: delegateRoot.awardedData && delegateRoot.awardedData.NumAchievedHardcore > 0
                                    spacing: 4
                                    Text {
                                        text: "🔥"
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        text: (delegateRoot.awardedData ? delegateRoot.awardedData.NumAchievedHardcore : 0) + " Hardcore"
                                        color: Theme.accent
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }
                            }
                            
                            // Latest Achievement Section
                            RowLayout {
                                visible: delegateRoot.latestAch !== null
                                spacing: 8
                                Layout.topMargin: 2
                                
                                Image {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    source: delegateRoot.latestAch ? ("https://media.retroachievements.org/Badge/" + delegateRoot.latestAch.BadgeName + ".png") : ""
                                    fillMode: Image.PreserveAspectFit
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: "Latest: " + (delegateRoot.latestAch ? delegateRoot.latestAch.Title : "")
                                        color: Theme.accent
                                        font.bold: true
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: (delegateRoot.latestAch && delegateRoot.latestAch.Description) ? delegateRoot.latestAch.Description : ""
                                        color: Theme.secondaryText
                                        font.pixelSize: 10
                                        font.italic: true
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.rightMargin: 10
                            Layout.alignment: Qt.AlignTop
                            Label { text: "LAST PLAYED"; font.pixelSize: 10; color: Theme.secondaryText; font.bold: true; Layout.alignment: Qt.AlignRight }
                            Label { text: modelData.LastPlayed.split(' ')[0]; color: Theme.text; font.pixelSize: 12; Layout.alignment: Qt.AlignRight }
                        }
                    }
                }
            }
        }
        
        Item { Layout.preferredHeight: 20 } // Bottom padding
    }
}
