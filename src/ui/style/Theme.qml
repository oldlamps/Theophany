pragma Singleton
import QtQuick

Item {
    id: theme

    property string currentTheme: "System"

    // Theme Properties
    property color background: "#1e1e24"
    property color secondaryBackground: "#2b2b36"
    property color sidebar: "#15151a"
    property color accent: "#ba00e0"
    property color text: "#ffffff"
    property color secondaryText: "#b8b8b8"
    property color border: "#333333"
    property color hover: "#22ffffff"
    property color buttonBackground: "#2a2a2a"
    property color buttonText: "#ffffff"
    property color bodyText: "#cccccc"

    // Theme Palettes
    readonly property var themes: {
        "Theophany Midnight": {
            background: "#1e1e24",
            secondaryBackground: "#2b2b36",
            sidebar: "#15151a",
            accent: "#ba00e0",
            text: "#ffffff",
            secondaryText: "#b8b8b8",
            border: "#333333",
            hover: "#22ffffff",
            buttonBackground: "#2a2a2a",
            buttonText: "#ffffff",
            bodyText: "#cccccc"
        },
        "Nord": {
            background: "#2e3440",
            secondaryBackground: "#3b4252",
            sidebar: "#242933",
            accent: "#88c0d0",
            text: "#eceff4",
            secondaryText: "#d8dee9",
            border: "#4c566a",
            hover: "#22eceff4",
            buttonBackground: "#3b4252",
            buttonText: "#eceff4",
            bodyText: "#d8dee9"
        },
        "Dracula": {
            background: "#282a36",
            secondaryBackground: "#44475a",
            sidebar: "#1e1f29",
            accent: "#ff79c6",
            text: "#f8f8f2",
            secondaryText: "#9ba8db",
            border: "#44475a",
            hover: "#22f8f8f2",
            buttonBackground: "#44475a",
            buttonText: "#f8f8f2",
            bodyText: "#f8f8f2"
        },
        "Catppuccin": {
            background: "#1e1e2e",
            secondaryBackground: "#313244",
            sidebar: "#181825",
            accent: "#cba6f7",
            text: "#cdd6f4",
            secondaryText: "#bac2de",
            border: "#45475a",
            hover: "#22cdd6f4",
            buttonBackground: "#313244",
            buttonText: "#cdd6f4",
            bodyText: "#bac2de"
        },
        "Tokyo Night": {
            background: "#1a1b26",
            secondaryBackground: "#24283b",
            sidebar: "#16161e",
            accent: "#bb9af7",
            text: "#c0caf5",
            secondaryText: "#a9b4de",
            border: "#414868",
            hover: "#22c0caf5",
            buttonBackground: "#24283b",
            buttonText: "#c0caf5",
            bodyText: "#c0caf5"
        },
        "Gruvbox Dark": {
            background: "#282828",
            secondaryBackground: "#3c3836",
            sidebar: "#1d2021",
            accent: "#d79921",
            text: "#ebdbb2",
            secondaryText: "#a89984",
            border: "#504945",
            hover: "#22ebdbb2",
            buttonBackground: "#3c3836",
            buttonText: "#ebdbb2",
            bodyText: "#d5c4a1"
        },
        "One Dark Pro": {
            background: "#282c34",
            secondaryBackground: "#21252b",
            sidebar: "#1e2227",
            accent: "#61afef",
            text: "#abb2bf",
            secondaryText: "#9ca4b2",
            border: "#3e4451",
            hover: "#22abb2bf",
            buttonBackground: "#2c313a",
            buttonText: "#abb2bf",
            bodyText: "#abb2bf"
        },
        "Latte": {
            background: "#eff1f5",
            secondaryBackground: "#e6e9ef",
            sidebar: "#dce0e8",
            accent: "#8839ef",
            text: "#4c4f69",
            secondaryText: "#6c6f85",
            border: "#bcc0cc",
            hover: "#224c4f69",
            buttonBackground: "#dce0e8",
            buttonText: "#4c4f69",
            bodyText: "#4c4f69"
        },
        "Frost": {
            background: "#eceff4",
            secondaryBackground: "#e5e9f0",
            sidebar: "#d8dee9",
            accent: "#5e81ac",
            text: "#2e3440",
            secondaryText: "#4c566a",
            border: "#d8dee9",
            hover: "#222e3440",
            buttonBackground: "#d8dee9",
            buttonText: "#2e3440",
            bodyText: "#2e3440"
        },
        "Pearl": {
            background: "#fafafa",
            secondaryBackground: "#f5f5f5",
            sidebar: "#eeeeee",
            accent: "#6200ea",
            text: "#212121",
            secondaryText: "#757575",
            border: "#e0e0e0",
            hover: "#22212121",
            buttonBackground: "#e0e0e0",
            buttonText: "#212121",
            bodyText: "#424242"
        },
        "That 70's Theme": {
            background: "#3a2f1f",
            secondaryBackground: "#4a3f2a",
            sidebar: "#2a1f0f",
            accent: "#d87c1f",
            text: "#f5deb3",
            secondaryText: "#d4b896",
            border: "#6b5636",
            hover: "#22f5deb3",
            buttonBackground: "#6b4423",
            buttonText: "#f5deb3",
            bodyText: "#e8d4a8"
        },
        "That 70's Theme Light": {
            background: "#f4e8d8",
            secondaryBackground: "#e8dcc8",
            sidebar: "#dcc8b0",
            accent: "#d87c1f",
            text: "#3a2f1f",
            secondaryText: "#5a4f3f",
            border: "#b89968",
            hover: "#223a2f1f",
            buttonBackground: "#c8b490",
            buttonText: "#3a2f1f",
            bodyText: "#4a3f2a"
        },
        "That 80's Theme": {
            background: "#1a0a2e",
            secondaryBackground: "#2d1b4e",
            sidebar: "#0f0520",
            accent: "#ff006e",
            text: "#00f5ff",
            secondaryText: "#b8a9ff",
            border: "#5a3d8a",
            hover: "#2200f5ff",
            buttonBackground: "#3d2667",
            buttonText: "#00f5ff",
            bodyText: "#a8d8ff"
        },
        "That 80's Theme Light": {
            background: "#f0e5ff",
            secondaryBackground: "#e5d5ff",
            sidebar: "#d8c5f5",
            accent: "#ff006e",
            text: "#1a0a2e",
            secondaryText: "#4a3a6e",
            border: "#b89ed8",
            hover: "#221a0a2e",
            buttonBackground: "#d0b8f0",
            buttonText: "#1a0a2e",
            bodyText: "#2d1b4e"
        },
        "That 90's Theme": {
            background: "#1e2835",
            secondaryBackground: "#2a3847",
            sidebar: "#141e28",
            accent: "#00ffcc",
            text: "#ffffff",
            secondaryText: "#b8c9e0",
            border: "#3d4e5f",
            hover: "#22ffffff",
            buttonBackground: "#2a3847",
            buttonText: "#ffffff",
            bodyText: "#d4e0f0"
        },
        "That 90's Theme Light": {
            background: "#e0f5ff",
            secondaryBackground: "#cceeff",
            sidebar: "#b8e0f5",
            accent: "#00aa88",
            text: "#1e2835",
            secondaryText: "#3e4855",
            border: "#88c8d8",
            hover: "#221e2835",
            buttonBackground: "#a8d8e8",
            buttonText: "#1e2835",
            bodyText: "#2a3847"
        }
    }

    function setTheme(name) {
        if (name === "System") {
            currentTheme = name
            return
        }
        if (themes[name]) {
            currentTheme = name
            var t = themes[name]
            background = t.background
            secondaryBackground = t.secondaryBackground
            sidebar = t.sidebar
            accent = t.accent
            text = t.text
            secondaryText = t.secondaryText
            border = t.border
            hover = t.hover
            buttonBackground = t.buttonBackground
            buttonText = t.buttonText
            bodyText = t.bodyText
        }
    }

    SystemPalette { id: sysPalette; colorGroup: SystemPalette.Active }

    Binding { target: theme; property: "background"; value: sysPalette.window; when: currentTheme === "System" }
    Binding { target: theme; property: "secondaryBackground"; value: sysPalette.base; when: currentTheme === "System" }
    Binding { target: theme; property: "sidebar"; value: sysPalette.alternateBase; when: currentTheme === "System" }
    Binding { target: theme; property: "accent"; value: sysPalette.highlight; when: currentTheme === "System" }
    Binding { target: theme; property: "text"; value: sysPalette.windowText; when: currentTheme === "System" }
    Binding { target: theme; property: "secondaryText"; value: Qt.hsla(sysPalette.windowText.hslHue, sysPalette.windowText.hslSaturation, sysPalette.windowText.hslLightness, 0.7); when: currentTheme === "System" }
    Binding { target: theme; property: "border"; value: sysPalette.mid; when: currentTheme === "System" }
    Binding { target: theme; property: "hover"; value: Qt.hsla(sysPalette.highlight.hslHue, sysPalette.highlight.hslSaturation, sysPalette.highlight.hslLightness, 0.2); when: currentTheme === "System" }
    Binding { target: theme; property: "buttonBackground"; value: sysPalette.button; when: currentTheme === "System" }
    Binding { target: theme; property: "buttonText"; value: sysPalette.buttonText; when: currentTheme === "System" }
    Binding { target: theme; property: "bodyText"; value: sysPalette.text; when: currentTheme === "System" }
}
