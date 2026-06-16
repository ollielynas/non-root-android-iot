

use egui_macroquad::egui::{self,  Theme, ThemePreference::Light, Visuals};
use macroquad::{miniquad::window::dropped_file_path, prelude::*};

use crate::state::AppState;

pub mod flash;
pub mod state;
pub mod log_data;
pub mod adb;
pub mod web_endpoint;
pub mod util;
pub mod scripts;
pub mod device_sensor;
pub mod tailscale;

pub const KEYRING_SERVICE: &str = "non-root-android-iot";

fn window_conf() -> Conf {
    Conf {
        window_title: "Android IOT Manager".to_owned(),
        window_height: 700,
        window_width: 800,
        high_dpi: true,
        platform: miniquad::conf::Platform {
            ..Default::default()
        },
        ..Default::default()
    }
}

#[macroquad::main(window_conf)]
async fn main() {

    let mut app_state: AppState = AppState::load(AppState::home_dir().join("last_state"));
    egui_macroquad::ui(|egui_ctx| {
        egui_ctx.set_theme(Theme::Light);
        let mut style = egui_ctx.style().as_ref().clone();
        style.interaction.tooltip_delay = 0.0;
        egui_ctx.set_style(style);
    });

    loop {
        clear_background(WHITE);

        if let Some(path) = dropped_file_path(0) {
            app_state = AppState::load(path);
        }

        egui_macroquad::ui(|egui_ctx| {

            match app_state.update() {
                Ok(_) => {}
                Err(e) => {
                    egui::Window::new("Error")
                        .show(egui_ctx, |ui| {
                            ui.label(e.to_string());
                        });
                }
            }

            app_state.render_modals(egui_ctx);
            egui::TopBottomPanel::top("top panel")
                .show(egui_ctx, |ui|{
                    app_state.render_top(ui);
                });
            egui::TopBottomPanel::bottom("Bottom Panel")
                .show(egui_ctx, |ui|{
                    app_state.render_bottom(ui, egui_ctx);
                });
            egui::CentralPanel::default()
                .show(egui_ctx, |ui|{

                            app_state.render_center(ui, egui_ctx);
                });

        });

        // Draw things before egui

        egui_macroquad::draw();

        // Draw things after egui

        next_frame().await;
    }
}
