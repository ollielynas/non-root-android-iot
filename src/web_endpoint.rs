use egui_macroquad::egui::Ui;

use crate::scripts::{UPLOAD_POCKETBASE, UPLOAD_SMS};


#[derive(Clone)]
pub enum UploadOptions {
    None,
    PocketBase{api_key: String, address:String},
    Sms{ph_num: String}
}

impl UploadOptions {
    pub fn name(&self) -> String {
        match self {
            Self::None => "None",
            Self::PocketBase { api_key: _, address: _ } => "PocketBase.io",
            Self::Sms { ph_num:_ } => "SMS Message",
        }.to_string()
    }


    pub fn shell_file(&self) -> String {
        match self {
            UploadOptions::None => "".to_string(),
            UploadOptions::PocketBase { api_key: _, address: _ } => {UPLOAD_POCKETBASE.to_string()},
            UploadOptions::Sms { ph_num } => {
                let mut file_text = UPLOAD_SMS.to_string();
                file_text = file_text.replace("DESTINATION_PHONE_NUMBER_HERE", ph_num);
                file_text
            },
        }
    }


    pub fn render(&mut self, ui: &mut Ui) {
        match self {
            UploadOptions::None => {
                ui.label("Uploads will not occur");
            },
            UploadOptions::PocketBase { api_key, address } => {
                if ui.link("https://pocketbase.io/").clicked() {
                    let _ = open::that("https://pocketbase.io/");
                }
                ui.strong("Address");
                ui.text_edit_singleline(address);
                ui.strong("api key");
                ui.text_edit_singleline(api_key);
            },

            UploadOptions::Sms { ph_num } => {
                ui.strong("Destination Phone Number");
                ui.text_edit_singleline(ph_num);
            },
        }
    }
}


pub const UPLOAD_OPTIONS: &[UploadOptions] = &[
    UploadOptions::None,
    UploadOptions::PocketBase { api_key: String::new(), address: String::new() },
    UploadOptions::Sms { ph_num: String::new() },
];
