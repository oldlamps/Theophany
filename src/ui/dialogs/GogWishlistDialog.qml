import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Theophany.Bridge 1.0
import "../components"
import "../style"

Dialog {
    id: root
    title: "GOG Wishlist"
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
        
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            color: "#40000000"
            radius: 20
            samples: 41
        }
    }

    AppInfo { id: appInfo }

    StoreBridge {
        id: storeBridge
        onGogWishlistFinished: (resultsJson) => {
            var results = JSON.parse(resultsJson)
            wishlistModel.clear()
            for (var i = 0; i < results.length; i++) {
                var item = results[i]
                // Fix price format: "24.99$" -> "$24.99", "-4.50$" -> "-$4.50"
                if (item.price) {
                    item.price = item.price.replace(/([\d.]+)\$/g, "$$$1")
                }
                wishlistModel.append(item)
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
    ListModel { id: wishlistModel }

    function openWishlist() {
        loading = true
        storeBridge.refresh_gog_wishlist()
        open()
    }

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 25
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 15
                
                Text {
                    text: "GOG Wishlist"
                    color: Theme.text
                    font.pixelSize: 24
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                TheophanyButton {
                    text: "Refresh"
                    loading: root.loading
                    onClicked: {
                        root.loading = true
                        storeBridge.refresh_gog_wishlist()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
                opacity: 0.3
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.sidebar
                radius: 10
                border.color: Theme.border
                border.width: 1
                clip: true

                ListView {
                    id: wishlistView
                    anchors.fill: parent
                    anchors.margins: 2
                    model: wishlistModel
                    spacing: 0
                    clip: true
                    
                    ScrollBar.vertical: TheophanyScrollBar { }

                    delegate: Rectangle {
                        width: wishlistView.width
                        height: 90
                        color: itemMa.containsMouse ? Theme.hover : "transparent"
                        radius: 4

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 15

                            // Icon/Placeholder
                            Rectangle {
                                width: 60; height: 60
                                radius: 8
                                color: "transparent"
                                border.color: "transparent"
                                
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + appInfo.getAssetsDir() + "/systems/gog.png"
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    spacing: 8
                                    Text {
                                        text: model.title
                                        color: Theme.text
                                        font.bold: true
                                        font.pixelSize: 16
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    
                                    // Price Info
                                    Text {
                                        text: model.price
                                        color: model.has_discount ? Theme.accent : Theme.secondaryText
                                        font.pixelSize: 14
                                        font.bold: model.has_discount
                                    }

                                    Rectangle {
                                        visible: model.has_discount
                                        color: Theme.accent
                                        radius: 4
                                        width: discountText.implicitWidth + 10
                                        height: 18
                                        Text {
                                            id: discountText
                                            anchors.centerIn: parent
                                            text: "OFFER"
                                            color: "white"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }
                                }

                            }

                            TheophanyButton {
                                text: "View on GOG"
                                onClicked: Qt.openUrlExternally(model.url)
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 30
                            height: 1
                            color: Theme.border
                            opacity: 0.2
                        }
                    }
                }

                TheophanySpinner {
                    anchors.centerIn: parent
                    running: root.loading
                    visible: running
                }

                Text {
                    anchors.centerIn: parent
                    text: "Your GOG Wishlist is empty."
                    color: Theme.secondaryText
                    visible: !root.loading && wishlistModel.count === 0
                }
            }

            RowLayout {
                Layout.fillWidth: true
                TheophanyButton {
                    text: "Close"
                    onClicked: root.close()
                }
            }
        }
    }
}
