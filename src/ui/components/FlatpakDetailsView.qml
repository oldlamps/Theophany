import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../style"

Item {
    id: root
    
    // Data properties
    property string appId: ""
    property var details: null
    property bool loading: false
    
    // Signals
    signal backClicked()
    signal installClicked(string appId, string name, string summary, string iconUrl, string description, string screenshotsJson, string developer)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // -- Top Bar (Back Button + Minimal Header) --
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 15
                
                TheophanyButton {
                    text: "← Back"
                    flat: true
                    onClicked: root.backClicked()
                }
                
                Item { Layout.fillWidth: true }
            }
            
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
                opacity: 0.3
            }
        }

        // -- Main Content Scroller --
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth // Ensure content fits width
            
            ColumnLayout {
                width: parent.width - 40 // Padding
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 30
                
                // Spacing top
                Item { height: 20; Layout.fillWidth: true }

                // -- Header Section (Icon + Title + Install) --
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 25
                    
                    // Large Icon
                    Rectangle {
                        Layout.preferredWidth: 128
                        Layout.preferredHeight: 128
                        color: "transparent"
                        
                        Image {
                            anchors.fill: parent
                            source: (root.details && root.details.icon) ? root.details.icon : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }
                    }
                    
                    // Info Column
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        Text {
                            text: (root.details && root.details.name) ? root.details.name : "Loading..."
                            color: Theme.text
                            font.pixelSize: 32
                            font.bold: true
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                        
                        Text {
                            text: (root.details && root.details.developerName) ? root.details.developerName : ""
                            color: Theme.accent
                            font.pixelSize: 16
                            visible: text !== ""
                        }
                        
                        Text {
                            text: (root.details && root.details.summary) ? root.details.summary : ""
                            color: Theme.secondaryText
                            font.pixelSize: 18
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                        
                        Item { height: 10; Layout.fillWidth: true }
                        
                        TheophanyButton {
                            text: "Install"
                            primary: true
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: 40
                            onClicked: {
                                if (root.details) {
                                    var screenshotsJson = JSON.stringify(root.details.screenshots || []);
                                    root.installClicked(
                                        root.details.appId, 
                                        root.details.name, 
                                        root.details.summary, 
                                        root.details.icon || "",
                                        root.details.description || "",
                                        screenshotsJson,
                                        root.details.developerName || ""
                                    )
                                }
                            }
                        }
                    }
                }

                // -- Screenshots Section --
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.details && root.details.screenshots && root.details.screenshots.length > 0
                    spacing: 10
                    
                    Text {
                        text: "Screenshots"
                        color: Theme.text
                        font.pixelSize: 20
                        font.bold: true
                    }
                    
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 260 // Increased slightly for scrollbar
                        
                        ListView {
                            id: screenshotList
                            anchors.fill: parent
                            anchors.bottomMargin: 10 // Space for scrollbar
                            orientation: ListView.Horizontal
                            spacing: 15
                            clip: true
                            snapMode: ListView.SnapToItem
                            
                            ScrollBar.horizontal: TheophanyScrollBar {
                                policy: ScrollBar.AsNeeded
                                parent: screenshotList.parent
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                            }
                            
                            model: (root.details && root.details.screenshots) ? root.details.screenshots : []
                            
                            delegate: Rectangle {
                                height: 250
                                // Dynamic width based on aspect ratio with max bounds
                                width: (img.status === Image.Ready && img.sourceSize.height > 0) 
                                       ? Math.min((img.sourceSize.width / img.sourceSize.height) * 250, 600)
                                       : 444
                                color: Theme.secondaryBackground
                                radius: 8
                                border.color: Theme.border
                                border.width: 1
                                
                                Image {
                                    id: img
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: modelData.src
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // Could have lightbox here later
                                }
                            }
                        }

                        // Left Navigation Button
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -5
                            width: 32; height: 64
                            color: Theme.background
                            radius: 8
                            opacity: screenshotList.contentX > 0 ? 0.8 : 0
                            visible: opacity > 0
                            
                            Text {
                                anchors.centerIn: parent
                                text: "❮"
                                color: Theme.text
                                font.pixelSize: 20
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    screenshotList.flick(1500, 0) // Flick right (scroll left)
                                }
                            }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Right Navigation Button
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -5
                            width: 32; height: 64
                            color: Theme.background
                            radius: 8
                            opacity: (screenshotList.contentX + screenshotList.width < screenshotList.contentWidth) ? 0.8 : 0
                            visible: opacity > 0
                            
                            Text {
                                anchors.centerIn: parent
                                text: "❯"
                                color: Theme.text
                                font.pixelSize: 20
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    screenshotList.flick(-1500, 0) // Flick left (scroll right)
                                }
                            }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }
                }

                // -- Description Section --
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: root.details && root.details.description !== ""
                    
                    Text {
                        text: "About"
                        color: Theme.text
                        font.pixelSize: 20
                        font.bold: true
                    }
                    
                    Text {
                        text: (root.details && root.details.description) ? root.details.description : ""
                        color: Theme.secondaryText
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                        textFormat: Text.RichText
                        Layout.fillWidth: true
                        lineHeight: 1.4
                    }
                }
                
                // -- Meta Info --
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    visible: root.details
                    
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.3 }
                    
                    Text {
                        text: "Additional Information"
                        color: Theme.text
                        font.pixelSize: 16
                        font.bold: true
                        Layout.topMargin: 10
                    }
                    
                    Text {
                        text: "License: " + ((root.details && root.details.projectLicense) ? root.details.projectLicense : "Unknown")
                        color: Theme.secondaryText
                        font.pixelSize: 13
                    }
                     Text {
                        text: "App ID: " + ((root.details && root.details.appId) ? root.details.appId : "")
                        color: Theme.secondaryText
                        font.pixelSize: 13
                    }
                }

                // Spacing bottom
                Item { height: 50; Layout.fillWidth: true }
            }
        }
    }
    
    // Loading State
    BusyIndicator {
        anchors.centerIn: parent
        running: root.loading
        visible: root.loading
    }
}
