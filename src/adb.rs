use std::{
    any, os,
    path::PathBuf,
    process::{Command, abort},
    thread::{self, JoinHandle, Thread},
    time::{Duration, Instant},
};

use chrono::Local;
use egui_macroquad::egui::{self, Color32, Context, Ui, modal};
use macroquad::{miniquad::BufferUsage::Stream, models, window::screen_height};
use savefile::savefile_derive::Savefile;

use crate::{
    flash::FlashSettings, log_data::LogDataState, scripts::SCRIPTS, util::{any_modal_is_open, start_modal}
};

use crate::device_sensor::DeviceSensor;

use std::env::temp_dir;

pub fn now_savefile_default_fn() -> Instant {
    Instant::now()
}

fn default_join_handle() -> Option<JoinHandle<anyhow::Result<AdbManager>>> {
    None
}

#[derive(Savefile)]
pub struct AdbManager {
    pub path: PathBuf,
    pub termux_path: PathBuf,
    pub termux_api_path: PathBuf,
    pub status: String,
    /// (name, size)
    pub device_files: Vec<(String, u64)>,

    #[savefile_default_fn="default_join_handle"]
    #[savefile_ignore]
    #[savefile_introspect_ignore]
    pub update_thread: Option<JoinHandle<anyhow::Result<AdbManager>>>,

    #[savefile_ignore]
    #[savefile_default_fn="now_savefile_default_fn"]
    timer: Instant,
    device_ids: Vec<String>,
    test_res: Vec<bool>,
    show_test_res: bool,
    available_sensors: Vec<DeviceSensor>,
}

impl AdbManager {
    pub fn new() -> AdbManager {
        AdbManager {
            path: PathBuf::from("./bundled/adb.exe"),
            termux_path: PathBuf::from("./bundled/termux-beta.apk"),
            termux_api_path: PathBuf::from("./bundled/termux-api.apk"),
            status: String::from("initialising.."),
            timer: Instant::now(),
            device_ids: vec![],
            device_files: vec![],
            available_sensors: vec![],
            update_thread: None,
            test_res: vec![],
            show_test_res: false,
        }
    }

    pub fn save_secrets(&mut self) {
        // no sec for now
    }

    pub fn update_available_sensors(&mut self) {
        if let Ok(sensors) = DeviceSensor::gen_list(self) {
            self.available_sensors = sensors;
        } else {
            self.available_sensors = vec![];
        }

    }

    pub fn render_test_results(&mut self, cxt: &egui_macroquad::egui::Context) {

        if !self.show_test_res {return;}



        if egui_macroquad::egui::Modal::new("test resaults modal".into())
            .show(cxt, |ui| {
            let test_list = LogDataState::get_array(&self);
            if self.test_res.len() != test_list.len() {
            ui.label("Test results not available");
            if ui.button("Run Tests").clicked() {
                start_modal("run_tests", "Run Tests?", "Warning! Running these tests will delete existing logged data", true);
                return;
            }
            return;
        }
        if ui.button("close").clicked() {
            self.show_test_res = false;
        }
    egui::ScrollArea::vertical()
        .max_height(screen_height())
        .show(ui, |ui| {
        egui_macroquad::egui::Grid::new("test_results")
            .num_columns(2)
            .striped(true)
            .show(ui, |ui| {
            for i in 0..test_list.len() {
                ui.label(test_list[i].t.name());
                if self.test_res[i] {
                    ui.colored_label(Color32::GREEN, "Pass");
                } else {
                    ui.colored_label(Color32::RED, "Fail/Unsupported");
                }
                ui.end_row();
            }
        });
        });
        })        .should_close() {self.show_test_res = false;};

    }

    pub fn render(&mut self, ui: &mut Ui) {
        ui.horizontal(|ui| {
            ui.label(&self.status);
            if self.update_thread.is_some() {
                ui.spinner();
            }
        });

        if !self.update_thread.is_some() {
            if self.timer.elapsed() > Duration::from_secs(3) {
                self.timer = Instant::now();
                self.update_devices_connected();
            }
        }

        if let Some(handle) = self.update_thread.take() {
            if handle.is_finished() {
                match handle.join() {
                    Ok(Ok(mut a)) => {
                        std::mem::swap(&mut a, self);
                    }
                    Ok(Err(e)) => {
                        start_modal("error_in_flash", "Error in flash", e.to_string().as_str(), false);
                        self.status = "error".to_string();
                    }
                    Err(e) => {
                        start_modal("error_in_flash", "Error in flash", &format!("{e:?}"), false);
                        self.status = "thread panicked".to_string();
                        eprintln!("{:?}", e);
                    }
                }
            } else {
                self.update_thread = Some(handle);
            }
        }
    }

    pub fn copy_without_thread(&self) -> AdbManager {
        return AdbManager {
            path: self.path.clone(),
            status: self.status.clone(),
            timer: self.timer.clone(),
            device_ids: self.device_ids.clone(),
            device_files: self.device_files.clone(),
            termux_path: self.termux_path.clone(),
            termux_api_path: self.termux_api_path.clone(),
            test_res: self.test_res.clone(),
            available_sensors: self.available_sensors.clone(),
            show_test_res: self.show_test_res.clone(),
            update_thread: None,
        };
    }

    pub fn delete_files_sync(&mut self) -> anyhow::Result<()> {



        let output = Command::new(&self.path)
            .args(["shell", "rm", "-rf", "/sdcard/AndroidIOT"])
            .output()?;

        if !output.status.success() {
            anyhow::bail!(
                "Failed to delete files: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }

        // Recreate the empty folder
        Command::new(&self.path)
            .args(["shell", "mkdir", "-p", "/sdcard/AndroidIOT"])
            .output()?;

        Ok(())
    }

    pub fn delete_data(&mut self) {
        if self.update_thread.is_some() {
            return;
        };
        let mut adb_state = self.copy_without_thread();
        self.status = "Deleting files".to_string();
        self.update_thread = Some(thread::spawn(move || {
            adb_state.kill_termux_processes()?;
            adb_state.delete_files_sync()?;
            return Ok(adb_state);
        }));
    }
pub fn download_files_sync(&mut self) -> anyhow::Result<()> {
    let downloads = anyhow::Context::context(dirs::download_dir(), "no home dir")?;
    let date = Local::now().format("%Y-%m-%d_%H-%M-%S").to_string();
    let destination = downloads.join(format!("AndroidIOT {}", date));

    anyhow::Context::context(std::fs::create_dir_all(&destination), "failed to create destination directory")?;

    for (path, _) in &self.device_files {
        let output = Command::new(&self.path)
            .args([
                "pull",
                path,
                anyhow::Context::context(destination
                    .to_str(), "failed to convert destination path to string")?,
            ])
            .output()?;
        if !output.status.success() {
            anyhow::bail!("Failed to pull file {}: {}", path, String::from_utf8_lossy(&output.stderr));
        }
    }

    open::that(destination)?;
    Ok(())
}

    pub fn download_data(&mut self) {
        if self.update_thread.is_some() {
            return;
        };
        let mut adb_state = self.copy_without_thread();
        self.status = "Downloading files".to_string();
        self.update_thread = Some(thread::spawn(move || {
            adb_state.download_files_sync()?;
            return Ok(adb_state);
        }));

    }

    pub fn update_devices_connected(&mut self) {
        if self.update_thread.is_some() || any_modal_is_open() {
            return;
        };
        let mut adb_state = self.copy_without_thread();
        self.update_thread = Some(thread::spawn(move || {
            let output = Command::new(&adb_state.path).args(["devices"]).output();
            if let Ok(out) = output {
                adb_state.device_ids.clear();
                for line in String::from_utf8(out.stdout)?.lines() {
                    match line {
                        "List of devices attached" => {}
                        "" => {}
                        a => adb_state.device_ids.push(
                            a.split(" ")
                                .next()
                                .unwrap_or("error parsing output")
                                .to_string(),
                        ),
                    }
                }
            }

            adb_state.status = match adb_state.device_ids.len() {
                0 => "no devices connected".to_string(),
                1 => {
                    format!("Connected to: {}", adb_state.device_ids[0])
                }
                a => {
                    format!("{} Devices Connected", a)
                }
            };

            adb_state.device_files = adb_state.get_device_files()?;
            adb_state.update_available_sensors();
            return Ok(adb_state);
        }));
    }

    pub fn get_device_files(&self) -> anyhow::Result<Vec<(String, u64)>> {
        Command::new(&self.path)
            .args(["shell", "mkdir", "-p", "/sdcard/AndroidIOT"])
            .output()
            .ok();

        // Then always list it
        let files_output = Command::new(&self.path)
            .args(["shell", "ls", "-l", "/sdcard/AndroidIOT"])
            .output();

        match files_output {
            Ok(a) => {
                return Ok(parse_ls_output(
                    &String::from_utf8(a.stdout)?,
                    "/sdcard/AndroidIOT",
                ));
            }
            Err(e) => println!("Error: {:?}", e),
        }
        return Ok(vec![]);
    }
    pub fn kill_termux_processes(&self) -> anyhow::Result<()> {
        // Remove all at jobs first, before killing processes
        let kill_jobs_cmd = "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c \
            'export PATH=/data/data/com.termux/files/usr/bin:$PATH && \
            at -l | awk \"{print \\$1}\" | xargs -r atrm'";
        let output = Command::new(&self.path)
            .args(["shell", kill_jobs_cmd])
            .output()?;
        if !output.status.success() {
            anyhow::bail!(
                "Failed to remove termux jobs: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
        // Cancel all termux-job-scheduler jobs
        let cancel_jobs_cmd = "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c \
            'export PATH=/data/data/com.termux/files/usr/bin:$PATH && \
            termux-job-scheduler --cancel-all'";
        let output = Command::new(&self.path)
            .args(["shell", cancel_jobs_cmd])
            .output()?;
        if !output.status.success() {
            anyhow::bail!(
                "Failed to cancel termux scheduled jobs: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
        // Kill processes in a separate command — ignore exit code since
        // pkill will kill its own shell, causing a non-zero exit
        let kill_procs_cmd = "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c \
            'export PATH=/data/data/com.termux/files/usr/bin:$PATH && \
            pkill -u $(id -u); exit 0'";
        Command::new(&self.path)
            .args(["shell", kill_procs_cmd])
            .output()?;
        Ok(())
    }
    fn install_terminux(&mut self) -> anyhow::Result<()> {

        println!("installing termux...");
        let apk_path = anyhow::Context::context(self
            .termux_path
            .to_str(), "failed to get termux path")?;

        let termux_installed = Command::new(&self.path)
            .args(["shell", "pm", "list", "packages", "com.termux"])
            .output()
            .map(|o| {
                o.status.success() && String::from_utf8_lossy(&o.stdout).contains("com.termux")
            })
            .unwrap_or(false);

        // Try install with recommended flags first and capture output for debugging
        if !termux_installed {
            let attempt = Command::new(&self.path)
                .args([
                    "install",
                    "-g",
                    "-d",
                    "--bypass-low-target-sdk-block",
                    apk_path,
                ])
                .output();

            let mut install_ok = false;
            let mut last_stdout = Vec::new();
            let mut last_stderr = Vec::new();

            if let Ok(out) = attempt {
                last_stdout = out.stdout.clone();
                last_stderr = out.stderr.clone();
                if out.status.success() {
                    install_ok = true;
                } else {
                    println!(
                        "install attempt with flags failed: {}",
                        String::from_utf8_lossy(&out.stderr)
                    );
                }
            } else {
                println!("failed to spawn adb for install with flags");
            }

            // Fallback: try a plain install (some adb versions or devices dislike extra flags)
            if !install_ok {
                println!("trying fallback plain install...");
                let fallback = Command::new(&self.path)
                    .args(["install", apk_path])
                    .output()?;
                last_stdout = fallback.stdout.clone();
                last_stderr = fallback.stderr.clone();
                if fallback.status.success() {
                    install_ok = true;
                } else {
                    println!(
                        "fallback install failed: {}",
                        String::from_utf8_lossy(&fallback.stderr)
                    );
                }
            }

            if !install_ok {
                println!("install stdout: {}", String::from_utf8_lossy(&last_stdout));
                println!("install stderr: {}", String::from_utf8_lossy(&last_stderr));
                anyhow::bail!("ADB install failed; see logs above for details");
            }
        }
        println!("installed termux");

        // Attempt to whitelist Termux from Doze (deviceidle) so job-scheduler can run.
        let mut package_name = String::from("com.termux");
        if let Ok(out) = Command::new(&self.path)
            .args(["shell", "pm", "list", "packages"])
            .output()
        {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                for line in s.lines() {
                    if line.to_lowercase().contains("termux") {
                        if let Some(p) = line.strip_prefix("package:") {
                            package_name = p.to_string();
                            break;
                        }
                    }
                }
            }
        }

        println!("whitelisting '{}' from Doze (deviceidle)", package_name);
        let plus_pkg = format!("+{}", package_name);
        match Command::new(&self.path)
            .args(["shell", "cmd", "deviceidle", "whitelist", &plus_pkg])
            .output()
        {
            Ok(o) => {
                println!("whitelist stdout: {}", String::from_utf8_lossy(&o.stdout));
                println!("whitelist stderr: {}", String::from_utf8_lossy(&o.stderr));
                if !o.status.success() {
                    println!("deviceidle whitelist command returned non-zero");
                }
            }
            Err(e) => println!("failed to run whitelist command: {:?}", e),
        }

        // Print current whitelist for debugging
        if let Ok(o) = Command::new(&self.path)
            .args(["shell", "cmd", "deviceidle", "getwhitelist"])
            .output()
        {
            println!(
                "deviceidle whitelist: {}",
                String::from_utf8_lossy(&o.stdout)
            );
        }
        self.show_notification("installed termux...");
        Ok(())
    }
    fn show_notification(&self, message: &str) {
        let cmd = format!(
            "cmd notification post -S bigtext -t '{}'",
            message.replace('\'', r"'\''")  // escape any single quotes in message
        );

        if let Ok(o) = Command::new(&self.path)
            .args(["shell", &cmd])
            .output()
        {
        }
    }

    fn install_terminux_api(&mut self) -> anyhow::Result<()> {
        println!("installing termux api...");
        let apk_path = anyhow::Context::context(self
            .termux_api_path
            .to_str(), "failed to get termux api path")?;

        let termux_installed = Command::new(&self.path)
            .args(["shell", "pm", "list", "packages", "com.termux.api"])
            .output()
            .map(|o| {
                o.status.success() && String::from_utf8_lossy(&o.stdout).contains("com.termux.api")
            })
            .unwrap_or(false);

        // Try install with recommended flags first and capture output for debugging
        if !termux_installed {
            let attempt = Command::new(&self.path)
                .args([
                    "install",
                    "-g",
                    "-d",
                    "--bypass-low-target-sdk-block",
                    apk_path,
                ])
                .output();

            let mut install_ok = false;
            let mut last_stdout = Vec::new();
            let mut last_stderr = Vec::new();

            if let Ok(out) = attempt {
                last_stdout = out.stdout.clone();
                last_stderr = out.stderr.clone();
                if out.status.success() {
                    install_ok = true;
                } else {
                    println!(
                        "install attempt with flags failed: {}",
                        String::from_utf8_lossy(&out.stderr)
                    );
                }
            } else {
                println!("failed to spawn adb for install with flags");
            }

            // Fallback: try a plain install (some adb versions or devices dislike extra flags)
            if !install_ok {
                println!("trying fallback plain install...");
                let fallback = Command::new(&self.path)
                    .args(["install", apk_path])
                    .output()?;
                last_stdout = fallback.stdout.clone();
                last_stderr = fallback.stderr.clone();
                if fallback.status.success() {
                    install_ok = true;
                } else {
                    println!(
                        "fallback install failed: {}",
                        String::from_utf8_lossy(&fallback.stderr)
                    );
                }
            }

            if !install_ok {
                println!("install stdout: {}", String::from_utf8_lossy(&last_stdout));
                println!("install stderr: {}", String::from_utf8_lossy(&last_stderr));
                anyhow::bail!("ADB install failed; see logs above for details");
            }
        }
        println!("installed termux");

        // Attempt to whitelist Termux from Doze (deviceidle) so job-scheduler can run.
        let mut package_name = String::from("com.termux.api");
        if let Ok(out) = Command::new(&self.path)
            .args(["shell", "pm", "list", "packages"])
            .output()
        {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                for line in s.lines() {
                    if line.to_lowercase().contains("termux.api") {
                        if let Some(p) = line.strip_prefix("package:") {
                            package_name = p.to_string();
                            break;
                        }
                    }
                }
            }
        }

        println!("whitelisting '{}' from Doze (deviceidle)", package_name);
        let plus_pkg = format!("+{}", package_name);
        match Command::new(&self.path)
            .args(["shell", "cmd", "deviceidle", "whitelist", &plus_pkg])
            .output()
        {
            Ok(o) => {
                println!("whitelist stdout: {}", String::from_utf8_lossy(&o.stdout));
                println!("whitelist stderr: {}", String::from_utf8_lossy(&o.stderr));
                if !o.status.success() {
                    println!("deviceidle whitelist command returned non-zero");
                }
            }
            Err(e) => println!("failed to run whitelist command: {:?}", e),
        }

        // Print current whitelist for debugging
        if let Ok(o) = Command::new(&self.path)
            .args(["shell", "cmd", "deviceidle", "getwhitelist"])
            .output()
        {
            println!(
                "deviceidle whitelist: {}",
                String::from_utf8_lossy(&o.stdout)
            );
        }

        Ok(())
    }

    pub fn copy_scripts_to_device(&mut self, flash_settings: &FlashSettings) -> anyhow::Result<()> {
        for (name, content) in [SCRIPTS, &[
            ("upload.sh", &flash_settings.upload_options.shell_file(&flash_settings.tailscale_settings)),
            ("settings.txt", &flash_settings.generate_settings_file()?)
        ]].concat() {
            self.show_notification(&format!("Copying file: {}", name));
            let mut temp_path = temp_dir();
            temp_path.push(name);
            let normalized = content.replace("\r\n", "\n").replace('\r', "");
            std::fs::write(&temp_path, normalized)?;
            let output = Command::new(&self.path)
                .args([
                    "push",
                    anyhow::Context::context(temp_path
                        .to_str(), "failed to convert temp path to string")?,
                    &format!("/sdcard/AndroidIOT/{}", name),
                ])
                .output()?;
            if !output.status.success() {
                anyhow::bail!(
                    "Failed to push script {}: {}",
                    name,
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }

        Ok(())
    }

    pub fn create_commands_txt(
        &self,
        tasks: &Vec<crate::log_data::LogDataState>,
    ) -> anyhow::Result<()> {
        let mut commands = String::new();
        for task in tasks {
            self.show_notification(&format!("Adding task: {}", task.t.name()));
            commands.push_str(&(task.freq.to_sec().to_string() + " "));
            commands.push_str(&format!(
                "{} -l {}",
                "/data/data/com.termux/files/usr/bin/bash",
                task.t.log_script_command().join(" ")
            ));

            if task.write_to_disk {
                commands.push_str(" --download");
            }
            if task.upload {
                commands.push_str(" --upload");
            }
            commands.push_str("\n");
        }

        std::fs::write("commands.txt", commands)?;
        // send to device
        let output = Command::new(&self.path)
            .args(["push", "commands.txt", "/sdcard/AndroidIOT/commands.txt"])
            .output()?;
        if !output.status.success() {
            anyhow::bail!(
                "Failed to push commands.txt: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
        Ok(())
    }

    pub fn duplicate_loop_script(&mut self, tasks: &Vec<crate::log_data::LogDataState>) -> anyhow::Result<()> {
        // for each task, create a copy of loop.sh on the device with a unique name like loop1.sh, loop2.sh, etc
        for (i, task) in tasks.iter().enumerate() {
            self.show_notification(&format!("Duplicating loop script for task: {}", task.t.name()));
            let output = Command::new(&self.path)
                .args([
                    "shell",
                    "cp",
                    "/sdcard/AndroidIOT/loop.sh",
                    &format!("/sdcard/AndroidIOT/loop{}.sh", i + 1),
                ])
                .output()?;
            if !output.status.success() {
                anyhow::bail!(
                    "Failed to duplicate loop script for task {}: {}",
                    task.t.name(),
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }
        Ok(())
    }


    pub fn flash_device(&mut self, tasks: &Vec<crate::log_data::LogDataState>, flash_settings: &FlashSettings) {
        if self.update_thread.is_some() {
            return;
        };
        println!("flash_device: tasks={} flash_settings={}", tasks.len(), flash_settings.upload_options.name());
        let mut adb_state = self.copy_without_thread();
        let flash_settings = flash_settings.clone();
        let tasks = tasks.clone();
        self.status = "Flashing device...".to_string();
        self.update_thread = Some(thread::spawn(move || {
            adb_state.delete_files_sync()?;


            adb_state.install_terminux()?;
            adb_state.install_terminux_api()?;

            adb_state.kill_termux_processes()?;

            adb_state.copy_scripts_to_device(&flash_settings)?;
            adb_state.run_tests(&tasks)?;
            adb_state.delete_files_sync()?;


            adb_state.copy_scripts_to_device(&flash_settings)?;
            adb_state.create_commands_txt(&tasks)?;

            adb_state.duplicate_loop_script(&tasks)?;


            adb_state.run_loop_scripts(&tasks)?;

            adb_state.show_notification("Finished flashing IOT device");

            return Ok(adb_state);
        }));
    }


    pub fn run_all_tests(&mut self, flash_settings: &FlashSettings) -> anyhow::Result<()> {
    if self.update_thread.is_some() {
        return Ok(());
    };
    self.status = "Running tests, this could take some time...".to_string();
    let mut adb_state = self.copy_without_thread();
    let flash_settings = flash_settings.clone();

    self.update_thread = Some(thread::spawn(move || {
        adb_state.delete_data();
        adb_state.copy_scripts_to_device(&flash_settings)?;
        let tasks = LogDataState::get_array(&adb_state);
        let res = adb_state.run_tests(&tasks)?;
        adb_state.test_res = res;
        adb_state.show_test_res = true;
        return Ok(adb_state);
    }));

        Ok(())
    }

    pub fn run_loop_scripts(&self, tasks: &Vec<crate::log_data::LogDataState>) -> anyhow::Result<()> {
        for i in 0..tasks.len() {

            // We wrap the ENTIRE `run-as` command in `nohup` and `&`.
            // The loop script output goes to loopX.log.
            // Any errors from `run-as` itself go to launchX.log so you can still debug failures.
            let cmd = format!(
                "nohup run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'export PATH=/data/data/com.termux/files/usr/bin:$PATH && bash /sdcard/AndroidIOT/loop{}.sh > /sdcard/AndroidIOT/loop{}.log 2>&1' > /sdcard/AndroidIOT/launch{}.log 2>&1 &",
                i + 1,
                i + 1,
                i + 1
            );

            let output = Command::new(&self.path)
                .args(["shell", cmd.as_str()])
                .output()?;

            // Because we completely backgrounded the command, output.stdout and stderr
            // returned to Rust will likely be empty, and status will be immediate success.
            println!(
                "launched loop script {}: stdout: '{}', stderr: '{}'",
                i + 1,
                String::from_utf8_lossy(&output.stdout).trim(),
                String::from_utf8_lossy(&output.stderr).trim()
            );

            if !output.status.success() {
                anyhow::bail!(
                    "Failed to send shell command for loop script {}: {}",
                    i + 1,
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }
        Ok(())
    }
    pub fn run_tests(&mut self, tasks: &Vec<crate::log_data::LogDataState>) -> anyhow::Result<Vec<bool>> {
        println!("Running tests to validate scripts are working correctly...");
        let mut pass_fail_mask = vec![];
        for t in tasks {
            self.show_notification(&format!("Testing command for task: {}", t.t.name()));
            println!("Testing command for task: {}", t.t.name());
            let mut c = t.t.log_script_command();
            c.push("--download".into());
            let cmd = format!(
                "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'export PATH=/data/data/com.termux/files/usr/bin:$PATH && bash {}'",
                c.join(" ")
            );
            let output = Command::new(&self.path)
                .args(["shell", cmd.as_str()])
                .output();
            pass_fail_mask.push(match output {
                Ok(_a) => {
                    let output_test = t.t.validate_output(
                        self.get_device_files()?
                            .iter()
                            .map(|(f, _)| f.clone())
                            .collect::<Vec<String>>()
                            .as_slice(),
                    );
                    if output_test { true } else { false }
                }
                Err(a) => {
                    println!("error running command {}: {:?}", c.join(" "), a);
                    false
                }
            });
        }
        println!("Test results:");
        for (i, &passed) in pass_fail_mask.iter().enumerate() {
            println!("  {}: {}", i + 1, if passed { "PASS" } else { "FAIL" });
        }
        Ok(pass_fail_mask)
    }
}

fn parse_ls_output(output: &str, base_path: &str) -> Vec<(String, u64)> {
    output
        .lines()
        .filter(|line| {
            !line.trim().starts_with("total")
                && !line.is_empty()
                && !line.trim().starts_with('d')
                && !line.trim().contains(".sh")
        })
        .filter_map(|line| {
            let mut parts = line.split_whitespace();

            let _permissions = parts.next()?;
            let _links = parts.next()?;
            let _owner = parts.next()?;
            let _group = parts.next()?;
            let size_bytes: u64 = parts.next()?.parse().ok()?;
            let _date = parts.next()?;
            let time = parts.next()?;

            // Find the filename by locating where the time column ends
            let time_pos = line.find(time)? + time.len();
            let filename = line[time_pos..].trim();

            Some((format!("{}/{}", base_path, filename), size_bytes))
        })
        .collect()
}
