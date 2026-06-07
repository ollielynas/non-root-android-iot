pub const LOOP_SCRIPT: &str = include_str!("scripts/loop.sh");
pub const UPLOAD_SCRIPT: &str = include_str!("scripts/upload.sh");

pub const TAKE_PHOTO_SCRIPT: &str = include_str!("scripts/take_photo.sh");
pub const BATTERY_SCRIPT: &str = include_str!("scripts/log_battery.sh");
pub const BLUETOOTH_SCRIPT: &str = include_str!("scripts/log_bluetooth.sh");
pub const DATA_USAGE_SCRIPT: &str = include_str!("scripts/log_data_usage.sh");
pub const NTP_SCRIPT: &str = include_str!("scripts/log_ntp.sh");
pub const PING_SCRIPT: &str = include_str!("scripts/log_ping.sh");
pub const WIFI_SCRIPT: &str = include_str!("scripts/log_wifi.sh");
pub const CELL_SCRIPT: &str = include_str!("scripts/log_cell.sh");
pub const SCREEN_SCRIPT: &str = include_str!("scripts/log_screen.sh");
pub const VOLUME_SCRIPT: &str = include_str!("scripts/log_volume.sh");
pub const STORAGE_SCRIPT: &str = include_str!("scripts/log_storage.sh");
pub const CPU_SCRIPT: &str = include_str!("scripts/log_cpu.sh");
pub const MEMORY_SCRIPT: &str = include_str!("scripts/log_memory.sh");
pub const PROCESSES_SCRIPT: &str = include_str!("scripts/log_processes.sh");
pub const DNS_SCRIPT: &str = include_str!("scripts/log_dns.sh");
pub const HTTP_SCRIPT: &str = include_str!("scripts/log_http.sh");
pub const PUBLIC_IP_SCRIPT: &str = include_str!("scripts/log_public_ip.sh");
pub const VPN_SCRIPT: &str = include_str!("scripts/log_vpn.sh");
pub const AUDIO_SCRIPT: &str = include_str!("scripts/log_audio.sh");
pub const SERIAL_USB_INTERFACE_SCRIPT: &str = include_str!("scripts/log_serial_usb_interface.sh");
pub const SENSOR_SCRIPT: &str = include_str!("scripts/log_sensor.sh");

pub const SCRIPTS: &[(&str, &str)] = &[
    ("loop.sh", LOOP_SCRIPT),
    ("take_photo.sh", TAKE_PHOTO_SCRIPT),
    ("log_battery.sh", BATTERY_SCRIPT),
    ("log_bluetooth.sh", BLUETOOTH_SCRIPT),
    ("log_data_usage.sh", DATA_USAGE_SCRIPT),
    ("log_wifi.sh", WIFI_SCRIPT),
    ("log_cell.sh", CELL_SCRIPT),
    ("log_screen.sh", SCREEN_SCRIPT),
    ("log_volume.sh", VOLUME_SCRIPT),
    ("log_storage.sh", STORAGE_SCRIPT),
    ("log_cpu.sh", CPU_SCRIPT),
    ("log_memory.sh", MEMORY_SCRIPT),
    ("log_processes.sh", PROCESSES_SCRIPT),
    ("log_dns.sh", DNS_SCRIPT),
    ("log_http.sh", HTTP_SCRIPT),
    ("log_public_ip.sh", PUBLIC_IP_SCRIPT),
    ("log_vpn.sh", VPN_SCRIPT),
    ("log_audio.sh", AUDIO_SCRIPT),
    ("log_serial_usb_interface.sh", SERIAL_USB_INTERFACE_SCRIPT),
    ("log_sensor.sh", SENSOR_SCRIPT),
];


// the following scripts should not be automatically copied

pub const UPLOAD_SMS: &str = include_str!("scripts/upload_scripts/upload_sms.sh");
pub const UPLOAD_POCKETBASE: &str = include_str!("scripts/upload_scripts/upload_pocketbase.sh");
