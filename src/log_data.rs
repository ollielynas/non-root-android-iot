use egui_macroquad::egui::{self, Key::L, Ui};

use crate::{adb::AdbManager, device_sensor::DeviceSensor};

#[derive(Clone)]
pub enum Freq {
    PerHour(u32),
    PerDay(u32),
    PerMin(u32),
    /// vec<(hour, min)>
    AtTimes(Vec<(u16, u16)>),
}

impl Freq {
    pub fn to_sec(&self) -> u64 {
        match self {
            Freq::PerHour(n) => 3600 / (*n as u64),
            Freq::PerDay(n) => 24 * 3600 / (*n as u64),
            Freq::PerMin(n) => 60 / (*n as u64),
            Freq::AtTimes(_) => {
                unimplemented!("Conversion not implemented for AtTimes variant");
            }
        }
    }

    pub fn render(&mut self, ui: &mut Ui) {
        ui.horizontal(|ui| {
            // 1. Determine current variant name for the dropdown label
            let current_label = match self {
                Freq::PerHour(_) => "Per Hour",
                Freq::PerDay(_) => "Per Day",
                Freq::PerMin(_) => "Per Minute",
                Freq::AtTimes(_) => "At Specific Times",
            };

            // 2. Dropdown menu to switch variants
            // We use `ui.next_auto_id()` so if you have multiple rows, the dropdown IDs don't clash


            // 3. Render specific controls based on the active variant
            match self {
                Freq::PerHour(val) => {
                    ui.add(egui::DragValue::new(val).speed(0.1).clamp_range(1..=59));
                    ui.label("time/s");
                }
                Freq::PerDay(val) => {
                    ui.add(egui::DragValue::new(val).speed(0.1).clamp_range(1..=23));
                    ui.label("time/s");
                }
                Freq::PerMin(val) => {
                    ui.add(egui::DragValue::new(val).speed(1.0).clamp_range(1..=60));
                    ui.label("time/s");
                }
                Freq::AtTimes(times) => {
                    // Use a vertical layout because this list can grow dynamically
                    ui.vertical(|ui| {
                        let mut remove_idx = None;

                        for (i, (hour, min)) in times.iter_mut().enumerate() {
                            ui.horizontal(|ui| {
                                // Clamp ranges ensure valid 24h time formatting
                                ui.add(egui::DragValue::new(hour).speed(0.1).clamp_range(0..=23).suffix("h"));
                                ui.label(":");
                                ui.add(egui::DragValue::new(min).speed(1.0).clamp_range(0..=59).suffix("m"));

                                if ui.small_button("x").on_hover_text("Remove time").clicked() {
                                    remove_idx = Some(i);
                                }
                            });
                        }

                        // Remove triggered index outside the loop to avoid borrow checker issues
                        if let Some(i) = remove_idx {
                            times.remove(i);
                        }

                        if ui.button("+ Add Time").clicked() {
                            times.push((12, 0));
                        }
                    });
                }
            }
            egui::ComboBox::from_id_source(ui.next_auto_id())
                .selected_text(current_label)
                .show_ui(ui, |ui| {
                    // When switching variants, we overwrite `*self` with a safe default value
                    if ui.selectable_label(matches!(self, Freq::PerHour(_)), "Per Hour").clicked() {
                        *self = Freq::PerHour(1);
                    }
                    if ui.selectable_label(matches!(self, Freq::PerDay(_)), "Per Day").clicked() {
                        *self = Freq::PerDay(1);
                    }
                    if ui.selectable_label(matches!(self, Freq::PerMin(_)), "Per Minute").clicked() {
                        *self = Freq::PerMin(1);
                    }
                    if ui.selectable_label(matches!(self, Freq::AtTimes(_)), "At Specific Times").clicked() {
                        *self = Freq::AtTimes(vec![(12, 0)]); // Default to noon
                    }
                });
        });
    }
}

#[derive(Clone)]
pub enum LogDataType {

    Photo{back_camera: bool},
    PingTime{address: String},
    Location{accurate: bool},
    Battery,
    Bluetooth,
    Elevation,
    DataUsage,
    UpdateNpt,
    Wifi,
    Cell,
    Screen,
    Volume,
    Storage,
    Cpu,
    Memory,
    Processes,
    Dns,
    Http{address: String},
    SerialUsbInterface,
    PublicIp,
    AudioLevel,
    Vpn,
    SensorData{sensor: DeviceSensor},
}

impl LogDataType {
    pub fn name(&self) -> String {
        if matches!(self, LogDataType::SensorData { .. }) {
            return match self {
                LogDataType::SensorData { sensor } => sensor.display_name(),
                _ => {unreachable!()}
            };
        }

        match self {
            LogDataType::Photo{back_camera: _} => "Photo",
            LogDataType::PingTime{address: _} => "Ping Time",
            LogDataType::Battery => "Battery Percent",
            LogDataType::Location{accurate: _} => "Gps Location",
            LogDataType::Bluetooth => "Nearby Bluetooth Devices",
            LogDataType::Elevation => "Elevation",
            LogDataType::DataUsage => "Total Data Usage",
            LogDataType::UpdateNpt => "Update Time Over Network Using Ntp",
            LogDataType::Wifi => "WiFi Signal",
            LogDataType::Cell => "Cell Tower Info",
            LogDataType::Screen => "Screen State",
            LogDataType::Volume => "Volume Levels",
            LogDataType::Storage => "Storage Space",
            LogDataType::Cpu => "CPU Usage",
            LogDataType::Memory => "Memory Usage",
            LogDataType::Processes => "Running Processes Count",
            LogDataType::Dns => "DNS Resolution",
            LogDataType::Http { address:_ } => "HTTP Response",
            LogDataType::PublicIp => "Public IP",
            LogDataType::AudioLevel => "Audio Level",
            LogDataType::SerialUsbInterface => "Serial USB Interface",
            LogDataType::Vpn => "VPN State",
            LogDataType::SensorData { ..} => "",
        }.to_string()
    }

    pub fn log_script_command(&self) -> Vec<String> {
        let mut args = match self {
            LogDataType::Photo { back_camera } => vec![
                "take_photo.sh".into(),
                "-c".into(),
                if *back_camera { "0" } else { "1" }.into(),
            ],
            LogDataType::SerialUsbInterface => vec![
                "log_serial_usb_interface.sh".into(),
            ],
            LogDataType::PingTime { address } => vec![
                "log_ping.sh".into(),
                "--target".into(),
                address.clone(),
            ],
            LogDataType::Location { accurate } => {
                let mut args = vec!["log_gps.sh".into()];
                if *accurate {
                    args.push("--accurate".into());
                }
                args
            }
            LogDataType::SensorData { sensor } => {
                vec![
                    "log_sensor.sh".into(),
                    "--sensor".into(),
                    sensor.id.clone(),
                    "--value-labels".into(),
                    sensor.value_labels.join(",").into(),
                ]
            }

            LogDataType::Battery => vec!["log_battery.sh".into()],
            LogDataType::Bluetooth => vec!["log_bluetooth.sh".into()],
            LogDataType::Elevation => vec!["log_elevation.sh".into()],
            LogDataType::DataUsage => vec!["log_data_usage.sh".into()],
            LogDataType::UpdateNpt => vec!["log_ntp.sh".into()],
            LogDataType::Wifi => vec!["log_wifi.sh".into()],
            LogDataType::Cell => vec!["log_cell.sh".into()],
            LogDataType::Screen => vec!["log_screen.sh".into()],
            LogDataType::Volume => vec!["log_volume.sh".into()],
            LogDataType::Storage => vec!["log_storage.sh".into()],
            LogDataType::Cpu => vec!["log_cpu.sh".into()],
            LogDataType::Memory => vec!["log_memory.sh".into()],
            LogDataType::Processes => vec!["log_processes.sh".into()],
            LogDataType::Dns => vec!["log_dns.sh".into()],
            LogDataType::Http { address} => vec!["log_http.sh".into(), "--address".into(), address.clone()],
            LogDataType::PublicIp => vec!["log_public_ip.sh".into()],
            LogDataType::AudioLevel => vec!["log_audio.sh".into()],
            LogDataType::Vpn => vec!["log_vpn.sh".into()],
        };
        args[0] = format!("/sdcard/AndroidIOT/{}", args[0]);
        args
        }

    pub fn validate_output(&self, output_files: &[String]) -> bool {
        match self {

            LogDataType::SensorData { sensor } => {
                // output_files.iter().any(|f| f.contains(sensor)) || sensor_name == ""
                true
            }

            LogDataType::Photo { back_camera: _ } => {
                output_files.iter().any(|f| f.contains("camera_log.csv"))
            }
            LogDataType::PingTime { address: _ } => {
                output_files
                    .iter()
                    .any(|f| f.contains("ping_") && f.contains("_log.csv"))
            }
            LogDataType::SerialUsbInterface => {
                output_files.iter().any(|f| f.contains("serial_usb_interface_log.csv"))
            }
            LogDataType::Location { accurate: _ } => {
                output_files.iter().any(|f| f.contains("gps_log.csv"))
            }
            LogDataType::Battery => {
                output_files.iter().any(|f| f.contains("battery_log.csv"))
            }
            LogDataType::Bluetooth => {
                output_files.iter().any(|f| f.contains("bluetooth_log.csv"))
            }
            LogDataType::Elevation => {
                output_files.iter().any(|f| f.contains("elevation_log.csv"))
            }
            LogDataType::DataUsage => {
                output_files.iter().any(|f| f.contains("data_usage_log.csv"))
            }
            LogDataType::UpdateNpt => {
                output_files.iter().any(|f| f.contains("ntp_sync_log.csv"))
            }
            LogDataType::Wifi => output_files.iter().any(|f| f.contains("wifi_log.csv")),
            LogDataType::Cell => output_files.iter().any(|f| f.contains("cell_info_log.csv")),
            LogDataType::Screen => output_files.iter().any(|f| f.contains("screen_state_log.csv")),
            LogDataType::Volume => output_files.iter().any(|f| f.contains("volume_log.csv")),
            LogDataType::Storage => output_files.iter().any(|f| f.contains("storage_space_log.csv")),
            LogDataType::Cpu => output_files.iter().any(|f| f.contains("cpu_usage_log.csv")),
            LogDataType::Memory => output_files.iter().any(|f| f.contains("memory_usage_log.csv")),
            LogDataType::Processes => output_files.iter().any(|f| f.contains("process_count_log.csv")),
            LogDataType::Dns => output_files.iter().any(|f| f.contains("dns_resolution_log.csv")),
            LogDataType::Http {  .. } => output_files.iter().any(|f| f.contains("http_response_log.csv")),
            LogDataType::PublicIp => output_files.iter().any(|f| f.contains("public_ip_log.csv")),
            LogDataType::AudioLevel => output_files.iter().any(|f| f.contains("audio_level_log.csv")),
            LogDataType::Vpn => output_files.iter().any(|f| f.contains("vpn_state_log.csv")),
        }
    }
}
#[derive(Clone)]
pub struct LogDataState {
    pub t: LogDataType,
    pub freq: Freq,
    pub write_to_disk: bool,
    pub upload: bool,
}

impl LogDataState {

    pub fn new(t: LogDataType) -> LogDataState {
        LogDataState {
            t,
            freq: Freq::PerHour(1),
            upload: true,
            write_to_disk: true,
        }
    }

    pub fn get_array(adb: &AdbManager) -> Vec<LogDataState> {
        return [vec![
            LogDataState::new(LogDataType::Battery),
            LogDataState::new(LogDataType::Photo{back_camera: false}),
            LogDataState::new(LogDataType::Location{accurate: false}),
            LogDataState::new(LogDataType::PingTime { address: "8.8.8.8".to_string() }),
            LogDataState::new(LogDataType::Bluetooth),
            LogDataState::new(LogDataType::Elevation),
            LogDataState::new(LogDataType::DataUsage),
            LogDataState::new(LogDataType::UpdateNpt),
            LogDataState::new(LogDataType::Wifi),
            LogDataState::new(LogDataType::Cell),
            LogDataState::new(LogDataType::Screen),
            LogDataState::new(LogDataType::Volume),
            LogDataState::new(LogDataType::Storage),
            LogDataState::new(LogDataType::Cpu),
            LogDataState::new(LogDataType::Memory),
            LogDataState::new(LogDataType::Processes),
            LogDataState::new(LogDataType::Dns),
            LogDataState::new(LogDataType::Http {
                address: "https://example.com".into(),
            }),
            LogDataState::new(LogDataType::PublicIp),
            LogDataState::new(LogDataType::AudioLevel),
            LogDataState::new(LogDataType::Vpn),
        ], DeviceSensor::gen_list(adb).unwrap_or_default().into_iter().map(|s| LogDataState::new(LogDataType::SensorData { sensor: s })).collect()].concat()
    }


    pub fn render_settings(&mut self, ui: &mut Ui) {
        match self.t {
            LogDataType::Photo { back_camera } => {
                ui.label(if back_camera { "Back Camera" } else { "Front Camera" });
                if ui.button("Switch Camera").clicked() {
                    self.t = LogDataType::Photo { back_camera: !back_camera };
                }
            },
            LogDataType::Location { accurate } => {
                ui.label(if accurate { "Slow / Accurate" } else { "Fast / Inaccurate" });
                if ui.button("Switch Mode").clicked() {
                    self.t = LogDataType::Location { accurate: !accurate };
                }
            },
            LogDataType::PingTime { ref mut address } => {
                ui.label("Address:");
                ui.text_edit_singleline(address);
            }
            LogDataType::Http { ref mut address } => {
                ui.label("Address:");
                ui.text_edit_singleline(address);
            }
            _ => {
                // No specific settings for other types yet
            }

        }
    }
}
