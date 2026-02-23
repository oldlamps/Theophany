use std::ffi::CStr;
use qmetaobject::prelude::*;
use cpp::cpp;

cpp!{{
    #include <QtCore/QCoreApplication>
    #include <QtCore/QString>
    #include <QtGui/QIcon>
    #include <QtGui/QGuiApplication>
}}

mod core;
mod bridge;

qrc!(my_resources,
    "ui" {
        "src/ui/Main.qml" as "Main.qml",
        "src/ui/qmldir" as "qmldir",
        "src/ui/components/Sidebar.qml" as "components/Sidebar.qml",
        "src/ui/components/DetailsPanel.qml" as "components/DetailsPanel.qml",
        "src/ui/components/FilterBar.qml" as "components/FilterBar.qml",
        "src/ui/components/TheophanyLogo.qml" as "components/TheophanyLogo.qml",
        "src/ui/components/TheophanyMenu.qml" as "components/TheophanyMenu.qml",
        "src/ui/components/TheophanyMenuItem.qml" as "components/TheophanyMenuItem.qml",
        "src/ui/components/TheophanyMenuSeparator.qml" as "components/TheophanyMenuSeparator.qml",
        "src/ui/components/ViewToggle.qml" as "components/ViewToggle.qml",
        "src/ui/components/TheophanyButton.qml" as "components/TheophanyButton.qml",
        "src/ui/components/TheophanyComboBox.qml" as "components/TheophanyComboBox.qml",
        "src/ui/components/TheophanyTextField.qml" as "components/TheophanyTextField.qml",
        "src/ui/components/TheophanyScrollBar.qml" as "components/TheophanyScrollBar.qml",
        "src/ui/components/TheophanySwitch.qml" as "components/TheophanySwitch.qml",
        "src/ui/components/TheophanySpinBox.qml" as "components/TheophanySpinBox.qml",
        "src/ui/components/TheophanyTextArea.qml" as "components/TheophanyTextArea.qml",
        "src/ui/components/FlatpakDetailsView.qml" as "components/FlatpakDetailsView.qml",
        "src/ui/components/AddSystemDialog.qml" as "components/AddSystemDialog.qml",
        "src/ui/components/EmulatorManager.qml" as "components/EmulatorManager.qml",
        "src/ui/components/TheophanyCheckBox.qml" as "components/TheophanyCheckBox.qml",
        "src/ui/components/TheophanySuggestField.qml" as "components/TheophanySuggestField.qml",
        "src/ui/components/TheophanyTooltip.qml" as "components/TheophanyTooltip.qml",
        "src/ui/components/TheophanyMessageDialog.qml" as "components/TheophanyMessageDialog.qml",
        "src/ui/views/GameList.qml" as "views/GameList.qml",
        "src/ui/views/EmptyStateView.qml" as "views/EmptyStateView.qml",
        "src/ui/style/qmldir" as "style/qmldir",
        "src/ui/style/Theme.qml" as "style/Theme.qml",
        "src/ui/dialogs/GameEditDialog.qml" as "dialogs/GameEditDialog.qml",
        "src/ui/dialogs/MetadataCompareDialog.qml" as "dialogs/MetadataCompareDialog.qml",
        "src/ui/dialogs/ImageScrapeDialog.qml" as "dialogs/ImageScrapeDialog.qml",
        "src/ui/dialogs/VideoDownloadDialog.qml" as "dialogs/VideoDownloadDialog.qml",
        "src/ui/dialogs/ScrapeSearchDialog.qml" as "dialogs/ScrapeSearchDialog.qml",
        "src/ui/dialogs/SettingsDialog.qml" as "dialogs/SettingsDialog.qml",
        "src/ui/dialogs/SystemIconSearchDialog.qml" as "dialogs/SystemIconSearchDialog.qml",
        "src/ui/dialogs/RetroAchievementsDashboard.qml" as "dialogs/RetroAchievementsDashboard.qml",
        "src/ui/dialogs/ROMImportPreviewDialog.qml" as "dialogs/ROMImportPreviewDialog.qml",
        "src/ui/dialogs/FlatpakStoreDialog.qml" as "dialogs/FlatpakStoreDialog.qml",
        "src/ui/dialogs/LocalAppImportDialog.qml" as "dialogs/LocalAppImportDialog.qml",
        "src/ui/dialogs/ImportProgressDialog.qml" as "dialogs/ImportProgressDialog.qml",
        "src/ui/dialogs/AboutDialog.qml" as "dialogs/AboutDialog.qml",
        "src/ui/dialogs/PlaylistManagerDialog.qml" as "dialogs/PlaylistManagerDialog.qml",
        "src/ui/dialogs/AddContentDialog.qml" as "dialogs/AddContentDialog.qml",
        "src/ui/dialogs/MassEditDialog.qml" as "dialogs/MassEditDialog.qml",
        "src/ui/dialogs/SteamImportDialog.qml" as "dialogs/SteamImportDialog.qml",
        "src/ui/dialogs/ResourceManagerDialog.qml" as "dialogs/ResourceManagerDialog.qml",
        "src/ui/dialogs/BulkScrapeDialog.qml" as "dialogs/BulkScrapeDialog.qml",
        "src/ui/dialogs/WebAssetSearchDialog.qml" as "dialogs/WebAssetSearchDialog.qml",
        "src/ui/dialogs/HeroicImportDialog.qml" as "dialogs/HeroicImportDialog.qml",
        "src/ui/dialogs/LutrisImportDialog.qml" as "dialogs/LutrisImportDialog.qml",
        "src/ui/dialogs/GlobalSearchDialog.qml" as "dialogs/GlobalSearchDialog.qml",
        "src/ui/dialogs/QuitConfirmDialog.qml" as "dialogs/QuitConfirmDialog.qml",
        "src/ui/dialogs/ImageSearchDialog.qml" as "dialogs/ImageSearchDialog.qml",
        "src/ui/dialogs/FirstRunWizard.qml" as "dialogs/FirstRunWizard.qml",
        "src/ui/dialogs/UpdateNotificationDialog.qml" as "dialogs/UpdateNotificationDialog.qml",
        "assets/tray_icon.png" as "tray_icon.png",
        "assets/logo.png" as "assets/logo.png",
        "assets/RA.png" as "assets/RA.png",
    }
);

fn main() {
    // Force Basic style to avoid platform-specific QML bugs (like KDE's ComboBox positionToRectangle error)
    std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");

    // Enable logging with default level 'info' if RUST_LOG is not set
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    // Register struct with QML
    qml_register_type::<crate::bridge::game_model::GameListModel>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"GameListModel\0").unwrap(),
    );

    qml_register_type::<crate::bridge::platform_model::PlatformListModel>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"PlatformListModel\0").unwrap(),
    );

    qml_register_type::<crate::bridge::emulator_model::EmulatorListModel>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"EmulatorListModel\0").unwrap(),
    );

    qml_register_type::<crate::bridge::app_info::AppInfo>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"AppInfo\0").unwrap(),
    );

    qml_register_type::<crate::bridge::video_proxy::VideoProxy>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"VideoProxy\0").unwrap(),
    );

    qml_register_type::<crate::bridge::settings::AppSettings>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"AppSettings\0").unwrap(),
    );

    qml_register_type::<crate::bridge::retroachievements::RetroAchievementsBridge>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"RetroAchievements\0").unwrap(),
    );

    qml_register_type::<crate::bridge::ai_bridge::AiAssistantBridge>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"AiAssistant\0").unwrap(),
    );

    qml_register_type::<crate::bridge::playlist_model::PlaylistModel>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"PlaylistModel\0").unwrap(),
    );
    
    qml_register_type::<crate::bridge::store_bridge::StoreBridge>(
        CStr::from_bytes_with_nul(b"Theophany.Bridge\0").unwrap(),
        1,
        0,
        CStr::from_bytes_with_nul(b"StoreBridge\0").unwrap(),
    );

    let mut engine = QmlEngine::new();

    // Register embedded resources early so C++ can use them
    my_resources();

    let name = "theophany";
    let name_ptr = name.as_ptr();
    let name_len = name.len();
    
    let org = "theophany";
    let org_ptr = org.as_ptr();
    let org_len = org.len();
    
    let domain = "theophany.org";
    let domain_ptr = domain.as_ptr();
    let domain_len = domain.len();
    
    cpp!(unsafe [
        name_ptr as "const char*", name_len as "size_t",
        org_ptr as "const char*", org_len as "size_t",
        domain_ptr as "const char*", domain_len as "size_t"
    ] {
        QCoreApplication::setApplicationName(QString::fromUtf8(name_ptr, (int)name_len));
        QCoreApplication::setOrganizationName(QString::fromUtf8(org_ptr, (int)org_len));
        QCoreApplication::setOrganizationDomain(QString::fromUtf8(domain_ptr, (int)domain_len));
        
        QGuiApplication::setWindowIcon(QIcon(":/ui/assets/logo.png"));
    });

    // Setup XDG assets
    setup_assets();

    // Create and initialize the model
    // let mut game_model = crate::bridge::game_model::GameListModel::default();
    
    // In a real app, use XDG paths. For dev, use local.
    // let db_path = concat!(env!("CARGO_MANIFEST_DIR"), "/games.db").to_string();
    
    // engine.set_object_property("appDbPath".into(), QString::from(db_path)); // Removed due to type mismatch

    // Load the QML file
    // In a release build, load from the embedded resources.
    // In debug builds, load from the filesystem for faster development.
    if cfg!(debug_assertions) {
        let qml_path = concat!(env!("CARGO_MANIFEST_DIR"), "/src/ui/Main.qml");
        engine.load_file(qml_path.into());
    } else {
        engine.load_file("qrc:/ui/Main.qml".into());
    }

    // Run the application
    engine.exec();
}

fn setup_assets() {
    let assets_dir = crate::core::paths::get_assets_dir();
    let systems_dir = assets_dir.join("systems");
    
    // Ensure directories exist
    let _ = std::fs::create_dir_all(&systems_dir);

    // 1. Tray Icon
    let tray_icon_path = assets_dir.join("tray_icon.png");
    let tray_icon_bytes = include_bytes!("../assets/tray_icon.png");
    let _ = std::fs::write(tray_icon_path, tray_icon_bytes);

    // 2. System Icons
    let systems = [
        ("flatpak.png", include_bytes!("../assets/systems/flatpak.png").as_slice()),
        ("linux.png", include_bytes!("../assets/systems/linux.png").as_slice()),
        ("windows.png", include_bytes!("../assets/systems/windows.png").as_slice()),
        ("heroic.png", include_bytes!("../assets/systems/heroic.png").as_slice()),
        ("steam.png", include_bytes!("../assets/systems/steam.png").as_slice()),
        ("lutris.png", include_bytes!("../assets/systems/lutris.png").as_slice()),
    ];

    for (name, bytes) in systems {
        let p = systems_dir.join(name);
        let _ = std::fs::write(p, bytes);
    }

    // 3. RetroAchievements Icon
    let ra_icon_path = assets_dir.join("RA.png");
    let ra_icon_bytes = include_bytes!("../assets/RA.png");
    let _ = std::fs::write(ra_icon_path, ra_icon_bytes);
}