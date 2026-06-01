#[cfg(target_os = "windows")]
use std::process::Command;

use egui_macroquad::egui;

pub fn human_readable_size(bytes: u64) -> String {
    const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];

    if bytes == 0 {
        return "0 B".to_string();
    }

    let i = (bytes as f64).log(1024.0).floor() as usize;
    let i = i.min(UNITS.len() - 1);
    let value = bytes as f64 / 1024_f64.powi(i as i32);

    if i == 0 {
        format!("{} {}", bytes, UNITS[i])  // No decimal for bytes
    } else {
        format!("{:.2} {}", value, UNITS[i])
    }
}

pub fn open_folder(path: &str) {
    #[cfg(target_os = "windows")]
    Command::new("explorer").arg(path).spawn().ok();

    #[cfg(target_os = "macos")]
    Command::new("open").arg(path).spawn().ok();

    #[cfg(target_os = "linux")]
    Command::new("xdg-open").arg(path).spawn().ok();
}


use std::sync::Mutex;

static MODAL: Mutex<Option<ModalState>> = Mutex::new(None);

struct ModalState {
    id: String,
    title: String,
    message: String,
}

pub fn start_modal(id: &str, title: &str, message: &str) {
    *MODAL.lock().unwrap() = Some(ModalState {
        id: id.to_string(),
        title: title.to_string(),
        message: message.to_string(),
    });
}

/// Renders the modal if the id matches. Returns true if Yes was clicked.
pub fn check_modal(ctx: &egui::Context, id: &str) -> bool {
    let state = MODAL.lock().unwrap();

    // Only render if this id matches the active modal
    if state.as_ref().map(|s| s.id.as_str()) != Some(id) {
        return false;
    }

    let title = state.as_ref().unwrap().title.clone();
    let message = state.as_ref().unwrap().message.clone();
    drop(state); // Release lock before rendering

    let mut result = false;

    let modal = egui::Modal::new(egui::Id::new("global_modal")).show(ctx, |ui| {
        ui.set_min_width(200.0);
        ui.heading(&title);
        ui.label(&message);
        ui.separator();
        ui.horizontal(|ui| {
            if ui.button("Yes").clicked() {
                result = true;
                *MODAL.lock().unwrap() = None;
            }
            if ui.button("No").clicked() {
                *MODAL.lock().unwrap() = None;
            }
        });
    });

    if modal.should_close() {
        *MODAL.lock().unwrap() = None;
    }

    result
}
