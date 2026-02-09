import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../components"
import "../style"

Item {
    id: root
    
    signal addFileRequested()
    signal addFolderRequested()
    signal createCollectionRequested()
    signal clearFiltersRequested()

    property bool isSearching: false
    property string platformName: ""

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 30
        width: Math.min(600, parent.width * 0.8)

        // Illustration/Icon Area
        Item {
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200
            Layout.alignment: Qt.AlignHCenter
            
            Text {
                anchors.centerIn: parent
                text: root.isSearching ? "🔍" : "🎮"
                font.pixelSize: 120
                
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    color: Qt.alpha(Theme.accent, 0.3)
                    radius: 20
                    samples: 17
                }
            }
        }

        // Text Content
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            
            Text {
                text: root.isSearching ? "No Games Found" : (root.platformName !== "" ? "No Games in " + root.platformName : "Your Library is Empty")
                color: Theme.text
                font.pixelSize: 28
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: root.isSearching ? "Try adjusting your filters or search query." : "Let's get your collection started! Import your games to begin."
                color: Theme.secondaryText
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Action Buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 15
            visible: !root.isSearching

            TheophanyButton {
                text: "Add File(s)"
                Layout.preferredWidth: 140
                onClicked: root.addFileRequested()
            }

            TheophanyButton {
                text: "Add Folder"
                Layout.preferredWidth: 140
                onClicked: root.addFolderRequested()
            }

            TheophanyButton {
                text: "New Collection"
                primary: true
                Layout.preferredWidth: 160
                onClicked: root.createCollectionRequested()
            }
        }
        
        // Search fallback
        TheophanyButton {
            text: "Clear All Filters"
            visible: root.isSearching
            Layout.alignment: Qt.AlignHCenter
            onClicked: {
                // This signal should be handled by Main.qml
                root.clearFiltersRequested()
            }
        }
    }
}
