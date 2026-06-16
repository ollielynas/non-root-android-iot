use egui_macroquad::egui::{Grid, Ui};
use savefile::savefile_derive::Savefile;

use crate::{scripts::{UPLOAD_POCKETBASE, UPLOAD_SMS, UPLOAD_TAILDROP}, tailscale::TailscaleSettings};


#[derive(Clone, Savefile)]
pub enum UploadOptions {
    None,
    PocketBase{api_key: String, address:String},
    Sms{ph_num: String},
    Taildrop {destinations: Vec<String>},
}

impl UploadOptions {
    pub fn name(&self) -> String {
        match self {
            Self::None => "None",
            Self::PocketBase { api_key: _, address: _ } => "PocketBase.io",
            Self::Sms { ph_num:_ } => "SMS Message",
            Self::Taildrop { destinations: _ } => "Taildrop",
        }.to_string()
    }


    pub fn shell_file(&self, tailscale_settings: &TailscaleSettings) -> String {
        match self {
            UploadOptions::None => "".to_string(),
            UploadOptions::PocketBase { api_key, address } => {
                let mut file_text = UPLOAD_POCKETBASE.to_string();
                file_text = file_text.replace("API_KEY_HERE", api_key);
                file_text = file_text.replace("ADDRESS_HERE", address);
                file_text
            },
            UploadOptions::Sms { ph_num } => {
                let mut file_text = UPLOAD_SMS.to_string();
                file_text = file_text.replace("DESTINATION_PHONE_NUMBER_HERE", ph_num);
                file_text
            },
            UploadOptions::Taildrop { destinations } => {
                let mut file_text = UPLOAD_TAILDROP.to_string();
                file_text = file_text.replace(
                    "DEST_NODES_GO_HERE",
                    &destinations.iter()
                        .map(|x| format!("\"{}\"", x))
                        .collect::<Vec<String>>()
                        .join(" "),   // space-separated, not newline
                );
                file_text
            }
        }
    }


    pub fn render(&mut self, ui: &mut Ui, tailscale: &mut TailscaleSettings) {
        match self {
            UploadOptions::None => {
                ui.label("Uploads will not occur");
            },
            UploadOptions::PocketBase { api_key, address } => {
                if ui.link("https://pocketbase.io/").clicked() {
                    let _ = open::that("https://pocketbase.io/");
                }
                ui.strong("Address");
                ui.text_edit_singleline(address).on_hover_text("Make sure to include the protocol (https://) and the port (e.g. :8090)");

                ui.strong("api key");
                ui.text_edit_singleline(api_key).on_hover_text("This API key is a part of the setup of this device and will be shared if the settings file is shared");
            },

            UploadOptions::Sms { ph_num } => {
                ui.strong("Destination Phone Number");
                ui.text_edit_singleline(ph_num);
            },
            UploadOptions::Taildrop { destinations } => {
                ui.strong("Destinations");
                const PLACEHOLDER_DEL_VAL: usize = 99999;
                let mut del = PLACEHOLDER_DEL_VAL;
                let mut update_devices = false;
                Grid::new("taildrop grid")
                    .num_columns(2)

                    .show(ui, |ui| {
                        for (i, dest) in (*destinations).iter().enumerate() {
                            ui.label(dest);
                            if ui.button("Remove").clicked() {
                                del = i;
                            }
                            ui.end_row();
                        }
                    });
                if ui.menu_button("Add Tailscale Device", |ui| {
                    for device in tailscale.devices_on_network.iter() {
                        if ui.button(device).clicked() {
                            destinations.push(device.clone());
                            ui.close_menu();
                        }
                    }
                }).response.clicked() && tailscale.devices_on_network.len() == 0 {
                    update_devices = true;
                };
                if del != PLACEHOLDER_DEL_VAL  {
                    destinations.remove(del);
                }
                if update_devices {
                    tailscale.devices_on_network = tailscale.get_devices_on_network().unwrap_or_default();
                }
            },
        }
    }
}


pub const UPLOAD_OPTIONS: &[UploadOptions] = &[
    UploadOptions::None,
    UploadOptions::PocketBase { api_key: String::new(), address: String::new() },
    UploadOptions::Sms { ph_num: String::new() },
    UploadOptions::Taildrop { destinations: Vec::new() },
];
