use std::{mem::take, sync::{Arc, Mutex}, time::{Duration, Instant}};

use egui_macroquad::egui::{self, Context, Ui};

use crate::{adb::AdbManager, flash::FlashSettings, log_data::LogDataState};




pub struct AppState {
    tasks: Vec<LogDataState>,
    aval_tasks: Vec<LogDataState>,
    adb: AdbManager,
    flash_settings: FlashSettings,
}


impl AppState {

    pub fn new() -> AppState {
        AppState {
            tasks: vec![],
            aval_tasks: LogDataState::get_array(),
            adb: AdbManager::new(),
            flash_settings: FlashSettings::new(),
        }
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
    pub fn render_center(&mut self, ui:&mut Ui) {
        let mut new_tasks = vec![];
        let mut remove_indexes = vec![];
        ui.horizontal(|ui| {
            ui.strong(format!("Current Instructions ({})", self.tasks.len()));
            ui.menu_button("Add Instruction", |ui| {
                for t in &self.aval_tasks {
                    if ui.small_button(t.t.name()).clicked() {
                        new_tasks.push(t.clone());
                        ui.close_menu();
                    }
                }
            });
        });
        ui.separator();
        let available_width = ui.available_width();
        let col_width = (available_width - 40.0) / 4.0;
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
                        task.render_settings(ui);
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

        remove_indexes.sort();
        for index in remove_indexes.iter().rev() {
            self.tasks.remove(*index);
        }
        self.tasks.append(&mut new_tasks);

    }
}
