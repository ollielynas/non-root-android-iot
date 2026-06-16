use std::process::Command;

use savefile::savefile_derive::Savefile;

use crate::adb::AdbManager;

#[derive(Clone, Savefile)]
pub struct DeviceSensor {
    pub id: String,           // termux name e.g. "bmi320_acc"
    pub display_name: String, // human readable e.g. "Accelerometer"
    pub sensor_type: String,  // android type e.g. "android.sensor.accelerometer"
    pub vendor: String,       // e.g. "bosch"
    pub num_values: usize,    // how many values it returns (1, 3, 4 etc)
    pub value_labels: Vec<String>, // e.g. ["x", "y", "z"] or ["lux"] or ["steps"]
}



impl DeviceSensor {

    pub fn display_name(&self) -> String {
        format!("{} ({})", self.display_name, self.id)
    }

    pub fn gen_list(adb: &AdbManager) -> anyhow::Result<Vec<DeviceSensor>> {
        let output = Command::new(&adb.path)
            .args(["shell", "dumpsys sensorservice | grep -E '^0x'"])
            .output()?;

        if !output.status.success() {
            anyhow::bail!("Failed to query sensor list: {}", String::from_utf8_lossy(&output.stderr));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let sensors = stdout
            .lines()
            .filter_map(|line| {
                // Format: 0x00000001) bmi320_acc | bosch | ver: 1 | type: android.sensor.accelerometer(1) | ...
                let parts: Vec<&str> = line.splitn(2, ')').collect();
                if parts.len() < 2 { return None; }

                let fields: Vec<&str> = parts[1].split('|').map(str::trim).collect();
                if fields.len() < 4 { return None; }

                let id = fields[0].trim().to_string();
                let vendor = fields[1].trim().to_string();
                let sensor_type = fields[3]
                    .trim()
                    .strip_prefix("type: ")
                    .unwrap_or("")
                    .split('(')
                    .next()
                    .unwrap_or("")
                    .trim()
                    .to_string();

                let (display_name, num_values, value_labels) = sensor_meta(&sensor_type);

                Some(DeviceSensor {
                    id,
                    display_name,
                    sensor_type,
                    vendor,
                    num_values,
                    value_labels,
                })
            })
            .collect();

        Ok(sensors)
    }
}

fn sensor_meta(sensor_type: &str) -> (String, usize, Vec<String>) {
    match sensor_type {
        "android.sensor.accelerometer" =>
            ("Accelerometer".into(), 3, vec!["x".into(), "y".into(), "z".into()]),
        "android.sensor.magnetic_field" =>
            ("Magnetometer".into(), 3, vec!["x".into(), "y".into(), "z".into()]),
        "android.sensor.gyroscope" =>
            ("Gyroscope".into(), 3, vec!["x".into(), "y".into(), "z".into()]),
        "android.sensor.light" =>
            ("Light".into(), 1, vec!["lux".into()]),
        "android.sensor.proximity" =>
            ("Proximity".into(), 1, vec!["cm".into()]),
        "android.sensor.gravity" =>
            ("Gravity".into(), 3, vec!["x".into(), "y".into(), "z".into()]),
        "android.sensor.linear_acceleration" =>
            ("Linear Acceleration".into(), 3, vec!["x".into(), "y".into(), "z".into()]),
        "android.sensor.rotation_vector" =>
            ("Rotation Vector".into(), 4, vec!["x".into(), "y".into(), "z".into(), "w".into()]),
        "android.sensor.orientation" =>
            ("Orientation".into(), 3, vec!["azimuth".into(), "pitch".into(), "roll".into()]),
        "android.sensor.step_counter" =>
            ("Step Counter".into(), 1, vec!["steps".into()]),
        "android.sensor.step_detector" =>
            ("Step Detector".into(), 1, vec!["event".into()]),
        _ =>
            (sensor_type.split('.').last().unwrap_or(sensor_type).replace('_', " ").to_string(),
             1, vec!["value".into()]),
    }
}
