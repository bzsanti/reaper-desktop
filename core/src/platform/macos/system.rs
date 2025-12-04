//! macOS system monitoring implementation

use crate::platform::{SystemMetrics, SystemMonitor, PlatformResult};
use std::collections::HashMap;
use sysinfo::System;

pub struct MacOSSystemMonitor {
    system: std::sync::Mutex<System>,
}

impl MacOSSystemMonitor {
    pub fn new() -> Self {
        Self {
            system: std::sync::Mutex::new(System::new_all()),
        }
    }
}

impl SystemMonitor for MacOSSystemMonitor {
    fn get_system_metrics(&self) -> PlatformResult<SystemMetrics> {
        let mut system = self.system.lock().unwrap();
        
        // Refresh all metrics
        system.refresh_cpu();
        system.refresh_memory();
        
        // Get load average
        let load_avg = System::load_average();
        
        Ok(SystemMetrics {
            cpu_count: system.cpus().len(),
            cpu_frequency_mhz: system.cpus().first()
                .map(|cpu| cpu.frequency() as f64)
                .unwrap_or(0.0),
            cpu_usage_percent: system.global_cpu_info().cpu_usage(),
            memory_total_bytes: system.total_memory() * 1024,
            memory_used_bytes: system.used_memory() * 1024,
            memory_available_bytes: system.available_memory() * 1024,
            swap_total_bytes: system.total_swap() * 1024,
            swap_used_bytes: system.used_swap() * 1024,
            load_average_1min: load_avg.one,
            load_average_5min: load_avg.five,
            load_average_15min: load_avg.fifteen,
            uptime_seconds: System::uptime(),
        })
    }
    
    fn get_cpu_temperature(&self) -> PlatformResult<Option<f32>> {
        // On macOS, temperature sensors require IOKit
        // For now, return None - can be implemented with IOKit later
        Ok(None)
    }
    
    fn get_disk_io_stats(&self) -> PlatformResult<HashMap<String, (u64, u64)>> {
        // Note: sysinfo 0.30 doesn't expose disk I/O stats directly
        // This would need to be implemented using IOKit
        Ok(HashMap::new())
    }
    
    fn get_network_io_stats(&self) -> PlatformResult<HashMap<String, (u64, u64)>> {
        // Note: sysinfo 0.30 doesn't expose network stats in this way
        // This would need platform-specific implementation
        Ok(HashMap::new())
    }
}