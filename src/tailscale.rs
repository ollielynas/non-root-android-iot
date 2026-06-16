use chrono::{DateTime, Utc};
use egui_macroquad::egui::{Ui};
use savefile::savefile_derive::Savefile;
use std::fs;

use crate::state::{AppState, GLOBAL_VERSION};

#[derive(Clone, Savefile)]
pub struct Secret {
    pub key: String
}

impl Secret {
    fn as_str(&self) -> &str {
        &self.key
    }
    fn load(id: &str) -> Secret {
        let dir = AppState::home_dir();
        let path = dir.join(id);
        savefile::load_file(path.to_path_buf(), GLOBAL_VERSION).unwrap_or(Self { key: "".to_string() })
    }

    fn save(&self, id: &str) {
        let dir = AppState::home_dir();
        let path = dir.join(id);
        savefile::save_file(path.to_path_buf(), GLOBAL_VERSION, self).unwrap();
    }
}

// 1. Reads the key and ID from a simple text file, separated by a newline
fn load_local_key() -> Secret {
    Secret::load("tailscale.key")
}



#[derive(Clone, Savefile)]
pub struct TailscaleSettings {
    #[savefile_default_fn="load_local_key"]
    #[savefile_ignore]
    api_key: Secret,

    pub use_tailscale: bool,
    num_days: i64,
    pub devices_on_network: Vec<String>,
}

impl TailscaleSettings {
    pub fn new() -> TailscaleSettings {
        TailscaleSettings {
            api_key: load_local_key(),
            use_tailscale: false,
            num_days: 1,
            devices_on_network: Vec::new(),
        }
    }

    pub fn save_secrets(&mut self) {
        self.api_key.save("tailscale.key");
    }

    pub fn generate_auth_key(&self) -> anyhow::Result<String> {

        if !self.use_tailscale {
            return Ok("".to_owned());
        }

        let expiry_seconds = self.num_days * 24 * 60 * 60;
        let payload = serde_json::json!({
            "capabilities": {
                "devices": {
                    "create": {
                        "reusable": false,
                        "ephemeral": true,
                        "preauthorized": true
                    }
                }
            },
            "expirySeconds": expiry_seconds
        });

        let body = payload.to_string();

        let mut response = ureq::post("https://api.tailscale.com/api/v2/tailnet/-/keys")
            .header("Authorization", &format!("Bearer {}", self.api_key.as_str()))
            .header("Content-Type", "application/json")
            .send(body.as_str())
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let text = response.body_mut().read_to_string()
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let json: serde_json::Value = serde_json::from_str(&text)
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let api_key = json["key"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("no key in response"))?
            .to_string();

        Ok(api_key)
    }

    pub fn get_devices_on_network(&self) -> anyhow::Result<Vec<String>> {
        let mut response = ureq::get("https://api.tailscale.com/api/v2/tailnet/-/devices")
            .header("Authorization", &format!("Bearer {}", self.api_key.as_str()))
            .call()
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let text = response.body_mut().read_to_string()
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let json: serde_json::Value = serde_json::from_str(&text)
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let devices: Vec<String> = json["devices"]
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("no devices in response"))?
            .iter()
            .filter_map(|d| {
                // Pick the 100.x.x.x address from the addresses array
                d["addresses"]
                    .as_array()?
                    .iter()
                    .find_map(|a| {
                        let s = a.as_str()?;
                        s.starts_with("100.").then(|| s.to_string())
                    })
            })
            .collect();

        Ok(devices)
    }

    pub fn render(&mut self, ui: &mut Ui, start_time: DateTime<Utc>, collection_duration: std::time::Duration) {
        ui.vertical(|ui| {
            ui.checkbox(&mut self.use_tailscale, "Use Tailscale");
            if self.use_tailscale {

                // Render field for API Key
                ui.label("API Key:").on_hover_ui(|ui| {
                    ui.label("Dont worry, you api key will not be shared if you share your settings file");
                });
                ui.text_edit_singleline(&mut self.api_key.key).on_hover_ui(|ui| {
                    ui.label("Dont worry, you api key will not be shared if you share your settings file");
                });

                if ui.link("https://tailscale.com/docs/reference/tailscale-api").clicked() {
                    let _ = open::that("https://tailscale.com/docs/reference/tailscale-api");
                }
                let end_time = start_time + collection_duration;
                let time_from_now = end_time - Utc::now();

                let days = time_from_now.num_days() + 1;

                if days > 90 {
                    ui.label("CAUTION! Your AUTH key will expire before the data collection period ends.");
                }

                ui.horizontal(|ui| {
                    ui.label(format!("There are {} devices on your network", self.devices_on_network.len()));
                    if ui.button("update").clicked() {
                        self.devices_on_network = self.get_devices_on_network().unwrap_or_default();
                    }
                });

                ui.label(format!("Generated AUTH key will expire in {} days", days.min(90).max(1))).on_hover_ui(|ui| {
                    ui.label("A new Ephemeral auth key will be generated for each device that you flash and it will last exactly as long enough to expire at the end of the set data collection period. These keys will last a max of 90 days.");
                });
                self.num_days = days.min(90).max(1);
            }
        });
    }
}
