use std::time::{Duration, Instant};

use chrono::{Datelike, TimeZone, Timelike, Utc};
use egui_macroquad::egui::{self, ComboBox, Context, DragValue, Ui, UiKind::Popup};
use savefile::savefile_derive::Savefile;

use crate::{adb::AdbManager, tailscale::TailscaleSettings, util::{self, check_modal, start_modal}, web_endpoint::{UPLOAD_OPTIONS, UploadOptions}};


#[derive(Clone, Savefile)]
pub struct FlashSettings {
    pub start_date: chrono::DateTime<Utc>,
    pub collection_duration: Duration,
    pub upload_options: UploadOptions,
    pub destructive_optimization: bool,
    pub tailscale_settings: TailscaleSettings,
    pub download_current_settings: bool,
    pub load_from_file: bool,
}


impl FlashSettings {
    pub fn new() -> FlashSettings {
        FlashSettings { start_date: Utc::now(),
            collection_duration: Duration::from_hours(24*7),
            upload_options: UploadOptions::None,
            destructive_optimization: false,
            tailscale_settings: TailscaleSettings::new(),
            download_current_settings: false,
            load_from_file: false,
        }
    }

    pub fn generate_settings_file(&self) -> anyhow::Result<String> {
        Ok(format!("START={}\nEND={}\nTAILSCALE={}\nTAILSCALE_AUTH_TOKEN={}",
            self.start_date.timestamp(),
            self.start_date.timestamp() + self.collection_duration.as_secs() as i64,
            self.tailscale_settings.use_tailscale,
            self.tailscale_settings.generate_auth_key()?,
        ))
    }

    pub fn save_secrets(&mut self) {
        self.tailscale_settings.save_secrets();
    }

    pub fn render_actions(&mut self, ui: &mut Ui, ctx: &Context, adb: &mut AdbManager,  tasks: &Vec<crate::log_data::LogDataState>) {

        if ui.button("Download Current Settings").clicked() {
            self.download_current_settings = true;
        }
        if ui.button("Load from File").clicked() {
            self.load_from_file = true;
        }

        ui.separator();

        let folder_size = adb.device_files
            .iter()
            .map(|a| a.1);
        let total_size: u64 = folder_size.sum();



        if ui.button(
            format!("Download Device Data ({})",
                util::human_readable_size(total_size)
            )).clicked() {
                adb.download_data();
        }



        if ui.button(
            format!("Delete Device Data ({})",
                util::human_readable_size(total_size)
            )).clicked() {
                start_modal("delete_files", "Are you sure?", "This will delete all log data on device", true);
        }

        ui.separator();

        if ui.button("Run Tests").clicked() {
            start_modal("run_tests", "Run Tests?", "Warning! Running these tests will delete existing logged data", true);
        }

        ui.separator();

        if ui.button("Flash").clicked() {
            start_modal("flash_device", "Flash Device?", "Confirm you would like to flash device", true);
        }


        if check_modal(ctx, "delete_files") {
            // Yes was clicked, do the action
            adb.delete_data();
        }


        if check_modal(ctx, "flash_device") {
            // Yes was clicked, do the action
            adb.flash_device(tasks, &self);
        }

        if check_modal(ctx, "run_tests") {
            adb.run_all_tests(self);
        }
    }


    pub fn render_settings(&mut self, ui: &mut Ui) {
        ui.strong("Start Date/Time");
        // start time editor
        ui.horizontal_wrapped(|ui| {
                    // 1. Extract current values
                    let mut year = self.start_date.year();
                    let mut month = self.start_date.month();
                    let mut day = self.start_date.day();
                    let mut hour = self.start_date.hour();

                    let mut changed = false;

                    // 2. Year Editor (DragValue)
                    changed |= ui.add(
                        DragValue::new(&mut year)
                            .speed(1.0)
                            .range(1970..=2100) // Adjust range as needed
                    ).changed();
                    ui.label("/");
                    let month_names = [
                        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
                    ];

                    ComboBox::from_id_source("month_combo")
                        .selected_text(month_names[(month - 1) as usize])
                        .show_ui(ui, |ui| {
                            for (i, &name) in month_names.iter().enumerate() {
                                let month_num = (i + 1) as u32;
                                changed |= ui.selectable_value(&mut month, month_num, name).changed();
                            }
                        });

                    let max_days = match month {
                        4 | 6 | 9 | 11 => 30,
                        2 => {
                            if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) { 29 } else { 28 }
                        },
                        _ => 31,
                    };
                    if day > max_days {
                        day = max_days;
                        changed = true;
                    }
                    ui.label("/");
                    changed |= ui.add(
                        egui::DragValue::new(&mut day)
                            .speed(1.0)
                            .range(1..=max_days)
                    ).changed();
                    ui.label("at");
                    changed |= ui.add(
                        DragValue::new(&mut hour)
                            .speed(1.0)
                            .range(0..=23)
                    ).changed();
                    ui.label("o'clock, UTC");
                    if changed {
                        if let chrono::LocalResult::Single(new_date) = Utc.with_ymd_and_hms(year, month, day, hour, 0, 0) {
                            self.start_date = new_date;
                        }
                    }
                });
        ui.separator();
        ui.strong("Collection period duration");
        ui.horizontal_wrapped(|ui| {
            // Constants for seconds per unit
            const SECS_PER_HOUR: f64 = 60.0 * 60.0;
            const SECS_PER_DAY: f64 = 24.0 * SECS_PER_HOUR;
            const SECS_PER_WEEK: f64 = 7.0 * SECS_PER_DAY;
            const SECS_PER_MONTH: f64 = 30.0 * SECS_PER_DAY; // Standard 30-day approx

            // 1. Breakdown the total duration into distinct buckets
            let total_secs = self.collection_duration.as_secs_f64();

            let mut months = (total_secs / SECS_PER_MONTH).floor() as u32;
            let mut remainder = total_secs % SECS_PER_MONTH;

            let mut weeks = (remainder / SECS_PER_WEEK).floor() as u32;
            remainder %= SECS_PER_WEEK;

            let mut days = (remainder / SECS_PER_DAY).floor() as u32;
            remainder %= SECS_PER_DAY;

            // We keep hours as an f64 just in case there are sub-hour minutes/seconds
            // preserved in the duration that we don't want to accidentally truncate away.
            let mut hours = remainder / SECS_PER_HOUR;

            let mut changed = false;

            // 2. Render UI elements
            changed |= ui.add(egui::DragValue::new(&mut months)
                .speed(0.1)
                .range(0..=u32::MAX)
                .suffix(" mos")
            ).changed();

            changed |= ui.add(egui::DragValue::new(&mut weeks)
                .speed(0.1)
                .range(0..=u32::MAX)
                .suffix(" wks")
            ).changed();

            changed |= ui.add(egui::DragValue::new(&mut days)
                .speed(0.1)
                .range(0..=u32::MAX)
                .suffix(" days")
            ).changed();

            changed |= ui.add(egui::DragValue::new(&mut hours)
                .speed(1.0)
                .range(0.0..=f64::MAX)
                .suffix(" hrs")
            ).changed();

            // 3. Recombine if edited
            if changed {
                let new_total_secs = (months as f64 * SECS_PER_MONTH)
                    + (weeks as f64 * SECS_PER_WEEK)
                    + (days as f64 * SECS_PER_DAY)
                    + (hours * SECS_PER_HOUR);

                self.collection_duration = std::time::Duration::from_secs_f64(new_total_secs);
            }
        });

        let mut upload_option_index = UPLOAD_OPTIONS.iter().position(|opt| opt.name() == self.upload_options.name()).unwrap_or(0);

        ui.separator();
        ui.strong("Upload Settings");
        egui::ComboBox::from_label("Upload Options")
            .selected_text(self.upload_options.name())
            .show_ui(ui, |ui| {
                for (i, opt) in UPLOAD_OPTIONS.iter().enumerate() {
                    ui.selectable_value(&mut upload_option_index, i, opt.name());
                }
            }
        );

        if self.upload_options.name() != UPLOAD_OPTIONS[upload_option_index].name() {
            self.upload_options = UPLOAD_OPTIONS[upload_option_index].clone();
        }

        self.upload_options.render(ui, &mut self.tailscale_settings);

        ui.separator();

        ui.strong("Tailscale Settings");
        self.tailscale_settings.render(ui, self.start_date, self.collection_duration);

    }
}
