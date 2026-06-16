use std::{mem::{self, take}, path::PathBuf, sync::{Arc, Mutex}, time::{Duration, Instant}};

use egui_macroquad::egui::{self, Context, Ui};
use macroquad::window::screen_height;
use savefile::savefile_derive::Savefile;
use ureq::Error::RedirectFailed;

use crate::{adb::{self, AdbManager}, flash::FlashSettings, log_data::{LogDataState, LogDataType::Memory}, util::check_modal};

pub fn now_savefile_default_fn() -> Instant {
    Instant::now()
}

pub const GLOBAL_VERSION:u32 = 1;

#[derive(Savefile)]
pub struct AppState {
    tasks: Vec<LogDataState>,
    aval_tasks: Vec<LogDataState>,
    adb: AdbManager,
    flash_settings: FlashSettings,
    #[savefile_ignore]
    #[savefile_default_fn="now_savefile_default_fn"]
    update_timer: Instant,
}


impl AppState {

    pub fn save_secrets(&mut self) {
        self.adb.save_secrets();
        self.flash_settings.save_secrets();
    }

    pub fn home_dir() -> PathBuf {
        // make sure the home directory exists
        let mut path = std::env::home_dir().unwrap_or_default();
        path.push(".non-root-android-iot");
        std::fs::create_dir_all(&path).ok();
        path
    }

    pub fn new() -> AppState {
        let adb = AdbManager::new();
        AppState {
            tasks: vec![],
            aval_tasks: LogDataState::get_array(&adb),
            adb,
            flash_settings: FlashSettings::new(),
            update_timer: Instant::now(),
        }
    }

    pub fn save(&mut self, path: PathBuf) -> anyhow::Result<()> {
        self.save_secrets();
        savefile::save_file(path, GLOBAL_VERSION, self)?;
        Ok(())
    }

    pub fn load(path: PathBuf) -> AppState {
        match savefile::load_file(&path, GLOBAL_VERSION) {
            Ok(state) => state,
            Err(e) => {
                eprintln!("Save File Path: {:?}", &path);
                eprintln!("Failed to load state: {}", e);
                AppState::new()},
        }
    }

    pub fn update(&mut self) -> anyhow::Result<()> {

        if self.flash_settings.download_current_settings {
            self.flash_settings.download_current_settings = false;
            let download_dir = dirs::download_dir().ok_or(anyhow::anyhow!("no downloads directory"))?.join(format!("android-iot-settings-{}.bin", chrono::Utc::now().format("%Y%m%d%H%M%S")));
            open::that(&dirs::download_dir().ok_or(anyhow::anyhow!("no downloads directory"))?)?;
            self.save(download_dir);
        }

        if self.flash_settings.load_from_file {
            self.flash_settings.load_from_file = false;
            let path = rfd::FileDialog::new().pick_file();
            if let Some(path) = path {
                mem::replace(self, AppState::load(path));
            }
        }

        if self.update_timer.elapsed() > Duration::from_secs(3) {
            self.update_timer = Instant::now();
        }else {
            return Ok(());
        }
        self.aval_tasks = LogDataState::get_array(&self.adb);
        self.save(AppState::home_dir().join("last_state"))?;
        Ok(())
    }

    pub fn render_top(&mut self, ui:&mut Ui) {
        self.adb.render(ui);
    }
    pub fn render_bottom(&mut self, ui:&mut Ui, cxt: &Context) {
        ui.columns(2, |ui| {
            self.flash_settings.render_settings(&mut ui[0]);

            self.flash_settings.render_actions(&mut ui[1], cxt, &mut self.adb, &self.tasks);

        });
    }

    pub fn render_modals(&mut self, cxt: &Context) {
        self.adb.render_test_results(cxt);
        check_modal(cxt, "error_in_flash");
    }

    pub fn render_center(&mut self, ui:&mut Ui, cxt: &egui_macroquad::egui::Context) {
        let mut new_tasks = vec![];
        let mut remove_indexes = vec![];
        ui.horizontal(|ui| {
            ui.strong(format!("Current Instructions ({})", self.tasks.len()));
            ui.menu_button("Add Instruction", |ui| {
                egui::ScrollArea::vertical()
                    .max_height(screen_height() * 0.8)
                    .show(ui, |ui| {
                        for t in &self.aval_tasks {
                            if ui.small_button(t.t.name()).clicked() {
                                new_tasks.push(t.clone());
                                ui.close_menu();
                            }
                        }
                    });
            });
        });
        ui.separator();
        let available_width = ui.available_width();
        let col_width = (available_width - 40.0) / 4.0;
        egui::ScrollArea::vertical()
            .max_height(ui.available_height())
            .show(ui, |ui| {
        egui::Grid::new("tasks_grid")
            .num_columns(4)
            .min_col_width(col_width)
            .striped(true)         // Optional: adds alternating row backgrounds
            .show(ui, |ui| {
                // 1. Render Table Headers
                ui.strong("Instruction");
                ui.strong("Settings");
                ui.strong("Interval");
                ui.strong(""); // Empty header for the remove column
                ui.end_row();

                // 2. Render Table Rows
                for (i, task) in self.tasks.iter_mut().enumerate() {
                    // Column 0: Instruction Name
                    ui.label(task.t.name());

                    // Column 1: Settings Checkboxes
                    ui.vertical(|ui| {
                    ui.horizontal(|ui| {
                        ui.label("save to: ");
                        ui.checkbox(&mut task.upload, "cloud");
                        ui.label("/");
                        ui.checkbox(&mut task.write_to_disk, "device");
                    });

                    ui.horizontal_wrapped(|ui| {
                        task.render_settings(ui, &cxt);
                    });
                    });

                    task.freq.render(ui);

                    // Column 3: Remove Button
                    if ui.small_button("Remove").clicked() {
                        remove_indexes.push(i);
                    }
                    ui.end_row();
                }
        });
        });

        remove_indexes.sort();
        for index in remove_indexes.iter().rev() {
            self.tasks.remove(*index);
        }
        self.tasks.append(&mut new_tasks);

    }
}
