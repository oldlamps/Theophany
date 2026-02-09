use crate::core::db::DbManager;
use crate::core::models::Playlist;
use qmetaobject::prelude::*;
use std::cell::RefCell;

#[derive(QObject, Default)]
pub struct PlaylistModel {
    // Parent class: QAbstractListModel
    base: qt_base_class!(trait QAbstractListModel),

    // Internal data storage
    playlists: RefCell<Vec<Playlist>>,
    
    // DB Access
    db_path: RefCell<String>,

    // Methods exposed to QML
    init: qt_method!(fn(&mut self, db_path: String)),
    refresh: qt_method!(fn(&mut self)),
    createPlaylist: qt_method!(fn(&mut self, name: String) -> String),
    deletePlaylist: qt_method!(fn(&mut self, id: String)),
    renamePlaylist: qt_method!(fn(&mut self, id: String, new_name: String)),
    addToPlaylist: qt_method!(fn(&mut self, playlist_id: String, rom_id: String)),
    removeFromPlaylist: qt_method!(fn(&mut self, playlist_id: String, rom_id: String)),
    getId: qt_method!(fn(&self, index: i32) -> String),
    getName: qt_method!(fn(&self, index: i32) -> String),
}

impl QAbstractListModel for PlaylistModel {
    fn row_count(&self) -> i32 {
        self.playlists.borrow().len() as i32
    }

    fn data(&self, index: QModelIndex, role: i32) -> QVariant {
        let playlists = self.playlists.borrow();
        let idx = index.row() as usize;

        if idx >= playlists.len() {
            return QVariant::default();
        }

        let playlist = &playlists[idx];

        match role {
            // Qt::DisplayRole = 0
            0 => QVariant::from(QString::from(playlist.name.as_str())), 
            
            // Custom Roles
            256 => QVariant::from(QString::from(playlist.id.as_str())),   // idRole
            257 => QVariant::from(QString::from(playlist.name.as_str())), // nameRole
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        let mut roles = std::collections::HashMap::new();
        roles.insert(256, QByteArray::from("playlistId"));
        roles.insert(257, QByteArray::from("playlistName"));
        roles
    }
}

impl PlaylistModel {
    fn init(&mut self, db_path: String) {
        *self.db_path.borrow_mut() = db_path;
        self.refresh();
    }

    fn refresh(&mut self) {
        let path = self.db_path.borrow().clone();
        if path.is_empty() {
            return;
        }

        // Access DB
        if let Ok(db) = DbManager::open(&path) {
            if let Ok(new_list) = db.get_playlists() {
                self.begin_reset_model();
                *self.playlists.borrow_mut() = new_list;
                self.end_reset_model();
            }
        }
    }

    #[allow(non_snake_case)]
    fn createPlaylist(&mut self, name: String) -> String {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            if let Ok(id) = db.create_playlist(&name) {
                self.refresh();
                return id;
            }
        }
        String::new()
    }

    #[allow(non_snake_case)]
    fn deletePlaylist(&mut self, id: String) {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            let _ = db.delete_playlist(&id);
            self.refresh();
        }
    }

    #[allow(non_snake_case)]
    fn renamePlaylist(&mut self, id: String, new_name: String) {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            let _ = db.rename_playlist(&id, &new_name);
            self.refresh();
        }
    }

    #[allow(non_snake_case)]
    fn addToPlaylist(&mut self, playlist_id: String, rom_id: String) {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            let _ = db.add_to_playlist(&playlist_id, &rom_id);
            self.refresh();
        }
    }

    #[allow(non_snake_case)]
    fn removeFromPlaylist(&mut self, playlist_id: String, rom_id: String) {
        let path = self.db_path.borrow().clone();
        if let Ok(db) = DbManager::open(&path) {
            let _ = db.remove_from_playlist(&playlist_id, &rom_id);
            self.refresh();
        }
    }

    #[allow(non_snake_case)]
    fn getId(&self, index: i32) -> String {
        self.playlists.borrow().get(index as usize).map(|p| p.id.clone()).unwrap_or_default()
    }

    #[allow(non_snake_case)]
    fn getName(&self, index: i32) -> String {
        self.playlists.borrow().get(index as usize).map(|p| p.name.clone()).unwrap_or_default()
    }
}
