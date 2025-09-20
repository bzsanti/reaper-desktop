use once_cell::sync::Lazy;
use std::sync::Mutex;

pub mod hardware_monitor;
pub mod ffi;

// Re-export main types
pub use hardware_monitor::{HardwareMonitor, HardwareMetrics, TemperatureSensor, SensorType};

// Global hardware monitor instance
static HARDWARE_MONITOR: Lazy<Mutex<HardwareMonitor>> = Lazy::new(|| {
    Mutex::new(HardwareMonitor::new())
});