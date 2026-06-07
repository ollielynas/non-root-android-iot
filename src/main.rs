

use egui_macroquad::egui::{self,  Theme, ThemePreference::Light, Visuals};
use macroquad::prelude::*;

use crate::state::AppState;

pub mod flash;
pub mod state;
pub mod log_data;
pub mod adb;
pub mod web_endpoint;
pub mod util;
pub mod scripts;
pub mod device_sensor;


fn window_conf() -> Conf {
    Conf {
        window_title: "Android IOT Manager".to_owned(),
        window_height: 700,
        window_width: 800,

        platform: miniquad::conf::Platform {
            ..Default::default()
        },
        ..Default::default()
    }
}

#[macroquad::main(window_conf)]
async fn main() {

    let mut app_state: AppState = AppState::new();
    egui_macroquad::ui(|egui_ctx| {
        egui_ctx.set_theme(Theme::Light);
    });

    loop {
        clear_background(WHITE);

        // Process keys, mouse etc.

        egui_macroquad::ui(|egui_ctx| {
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
                    app_state.render_center(ui);
                });

        });

        // Draw things before egui

        egui_macroquad::draw();

        // Draw things after egui

        next_frame().await;
    }
}
