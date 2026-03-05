import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import "../style"

Item {
    id: root
    
    property alias text: textField.text
    property alias placeholderText: textField.placeholderText
    property var fullModel: []
    property var filteredModel: []
    property bool isCommaSeparated: false
    property string lastWord: ""

    implicitHeight: 35
    implicitWidth: 200

    function updateFilteredModel() {
        var input = textField.text
        var searchTerm = input
        
        if (isCommaSeparated) {
            var parts = input.split(',')
            searchTerm = parts[parts.length - 1].trim()
            lastWord = searchTerm
        }

        if (searchTerm.length === 0) {
            filteredModel = []
            popup.close()
            return
        }

        var results = []
        for (var i = 0; i < fullModel.length; i++) {
            if (fullModel[i].toLowerCase().includes(searchTerm.toLowerCase())) {
                results.push(fullModel[i])
            }
            if (results.length >= 10) break // Limit suggestions
        }
        
        filteredModel = results
        if (results.length > 0) {
            popup.open()
        } else {
            popup.close()
        }
    }

    TheophanyTextField {
        id: textField
        anchors.fill: parent
        onTextEdited: {
            updateFilteredModel()
        }
        onActiveFocusChanged: {
            if (!activeFocus) popup.close()
        }

        Keys.onPressed: (event) => {
            if (popup.opened) {
                if (event.key === Qt.Key_Down) {
                    if (listView.currentIndex < listView.count - 1) {
                        listView.currentIndex++
                    } else {
                        listView.currentIndex = 0
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    if (listView.currentIndex > 0) {
                        listView.currentIndex--
                    } else {
                        listView.currentIndex = listView.count - 1
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (listView.currentIndex >= 0) {
                        var selectedValue = filteredModel[listView.currentIndex]
                        applySelection(selectedValue)
                        event.accepted = true
                    }
                } else if (event.key === Qt.Key_Escape) {
                    popup.close()
                    event.accepted = true
                }
            }
        }
    }

    function applySelection(selectedValue) {
        textField.forceActiveFocus()
        if (root.isCommaSeparated) {
            var parts = textField.text.split(',')
            parts[parts.length - 1] = " " + selectedValue
            textField.text = parts.join(',').trim() + ", "
        } else {
            textField.text = selectedValue
        }
        popup.close()
    }

    Popup {
        id: popup
        y: parent.height + 4
        width: parent.width
        implicitHeight: Math.min(listView.contentHeight + 10, 200)
        padding: 5
        focus: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            color: Theme.secondaryBackground
            border.color: Theme.border
            radius: 8
            
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 12
                samples: 17
                color: "#aa000000"
            }
        }

        contentItem: ListView {
            id: listView
            clip: true
            model: root.filteredModel
            delegate: ItemDelegate {
                width: parent.width
                height: 35
                
                contentItem: Label {
                    text: modelData
                    color: highlighted ? Theme.text : Theme.secondaryText
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                
                background: Rectangle {
                    color: highlighted ? Theme.accent : "transparent"
                    radius: 4
                }
                
                highlighted: ListView.isCurrentItem
                
                onClicked: {
                    root.applySelection(modelData)
                }
            }
            
            highlightMoveDuration: 150
            highlightResizeDuration: 150
            currentIndex: 0
        }
    }
}
