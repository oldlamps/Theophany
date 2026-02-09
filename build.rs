fn main() {
    let mut config = cpp_build::Config::new();
    
    // Qt 6 requires C++17
    config.flag("-std=c++17");
    
    // Try to find Qt6 via pkg-config
    let mut libs = vec!["Qt6Core"];
    if pkg_config::Config::new().atleast_version("6.0").probe("Qt6Gui").is_ok() {
        libs.push("Qt6Gui");
    }
    if pkg_config::Config::new().atleast_version("6.0").probe("Qt6Quick").is_ok() {
        libs.push("Qt6Quick");
    }

    let mut found = false;
    for lib in &libs {
        if let Ok(library) = pkg_config::Config::new().atleast_version("6.0").probe(lib) {
            found = true;
            for path in library.include_paths {
                config.include(&path);
            }
        }
    }

    if !found {
        // Fallback to Qt5
        let libs5 = vec!["Qt5Core", "Qt5Gui", "Qt5Quick"];
        for lib in &libs5 {
            if let Ok(library) = pkg_config::Config::new().atleast_version("5.0").probe(lib) {
                for path in library.include_paths {
                    config.include(&path);
                }
            }
        }
    }
    
    config.build("src/main.rs");
}
