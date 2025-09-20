use sysinfo::{System, Components};
use std::process::Command;

#[derive(Debug, Clone)]
pub struct HardwareMetrics {
    pub temperatures: Vec<TemperatureSensor>,
    pub cpu_frequency_mhz: u64,
    pub thermal_state: ThermalState,
    pub power_metrics: Option<PowerMetrics>,
}

#[derive(Debug, Clone)]
pub struct TemperatureSensor {
    pub name: String,
    pub value_celsius: f32,
    pub sensor_type: SensorType,
    pub is_critical: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum SensorType {
    CpuCore,
    CpuPackage,
    Gpu,
    Memory,
    Storage,
    Battery,
    Other,
}

#[derive(Debug, Clone)]
pub enum ThermalState {
    Normal,      // < 60°C
    Warm,        // 60-75°C
    Hot,         // 75-85°C
    Throttling,  // > 85°C
}

#[derive(Debug, Clone)]
pub struct PowerMetrics {
    pub cpu_power_watts: Option<f32>,
    pub gpu_power_watts: Option<f32>,
    pub total_power_watts: Option<f32>,
}

pub struct HardwareMonitor {
    system: System,
    components: Components,
    last_update: std::time::Instant,
    cache_duration: std::time::Duration,
    cached_metrics: Option<HardwareMetrics>,
}

impl HardwareMonitor {
    pub fn new() -> Self {
        let system = System::new_all();
        let components = Components::new_with_refreshed_list();
        
        Self {
            system,
            components,
            last_update: std::time::Instant::now(),
            cache_duration: std::time::Duration::from_secs(2),
            cached_metrics: None,
        }
    }
    
    pub fn get_metrics(&mut self) -> HardwareMetrics {
        // Use cache if available and fresh
        if let Some(ref metrics) = self.cached_metrics {
            if self.last_update.elapsed() < self.cache_duration {
                return metrics.clone();
            }
        }
        
        // Refresh system info
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        self.components.refresh();
        
        // Collect temperature sensors
        let temperatures = self.collect_temperatures();
        
        // Get CPU frequency
        let cpu_frequency_mhz = self.get_cpu_frequency();
        
        // Determine thermal state
        let thermal_state = self.determine_thermal_state(&temperatures);
        
        // Try to get power metrics (may fail without sudo)
        let power_metrics = self.get_power_metrics();
        
        let metrics = HardwareMetrics {
            temperatures,
            cpu_frequency_mhz,
            thermal_state,
            power_metrics,
        };
        
        // Update cache
        self.cached_metrics = Some(metrics.clone());
        self.last_update = std::time::Instant::now();
        
        metrics
    }
    
    fn collect_temperatures(&mut self) -> Vec<TemperatureSensor> {
        let mut sensors = Vec::new();
        
        // Get temperatures from sysinfo components
        for component in self.components.iter() {
            let name = component.label().to_string();
            let temp = component.temperature();
            
            // Skip invalid readings
            if temp <= 0.0 || temp > 150.0 {
                continue;
            }
            
            let sensor_type = match name.to_lowercase().as_str() {
                s if s.contains("cpu") => SensorType::CpuCore,
                s if s.contains("gpu") => SensorType::Gpu,
                s if s.contains("memory") || s.contains("ram") => SensorType::Memory,
                s if s.contains("ssd") || s.contains("disk") => SensorType::Storage,
                s if s.contains("battery") => SensorType::Battery,
                _ => SensorType::Other,
            };
            
            let is_critical = temp > 85.0;
            
            sensors.push(TemperatureSensor {
                name: self.clean_sensor_name(&name),
                value_celsius: temp,
                sensor_type,
                is_critical,
            });
        }
        
        // If no sensors found via sysinfo, try to get CPU temp from system
        if sensors.is_empty() {
            if let Some(cpu_temp) = self.get_cpu_temp_fallback() {
                sensors.push(TemperatureSensor {
                    name: "CPU Package".to_string(),
                    value_celsius: cpu_temp,
                    sensor_type: SensorType::CpuPackage,
                    is_critical: cpu_temp > 85.0,
                });
            }
        }
        
        // Sort by sensor type and temperature
        sensors.sort_by(|a, b| {
            match a.sensor_type.cmp(&b.sensor_type) {
                std::cmp::Ordering::Equal => b.value_celsius.partial_cmp(&a.value_celsius).unwrap(),
                other => other,
            }
        });
        
        sensors
    }
    
    fn clean_sensor_name(&self, name: &str) -> String {
        // Clean up sensor names for better display
        name.replace("_", " ")
            .replace("TC", "Core")
            .replace("TG", "GPU")
            .replace("TB", "Battery")
            .replace("TM", "Memory")
            .replace("TS", "Storage")
            .trim()
            .to_string()
    }
    
    fn get_cpu_frequency(&self) -> u64 {
        // Get global CPU frequency
        let cpus = self.system.cpus();
        if let Some(cpu) = cpus.first() {
            cpu.frequency()
        } else {
            0
        }
    }
    
    fn determine_thermal_state(&self, temperatures: &[TemperatureSensor]) -> ThermalState {
        // Get the highest CPU temperature
        let max_cpu_temp = temperatures
            .iter()
            .filter(|s| matches!(s.sensor_type, SensorType::CpuCore | SensorType::CpuPackage))
            .map(|s| s.value_celsius)
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(0.0);
        
        match max_cpu_temp {
            t if t >= 85.0 => ThermalState::Throttling,
            t if t >= 75.0 => ThermalState::Hot,
            t if t >= 60.0 => ThermalState::Warm,
            _ => ThermalState::Normal,
        }
    }
    
    fn get_cpu_temp_fallback(&self) -> Option<f32> {
        // Try to get CPU temperature using sysctl on macOS
        #[cfg(target_os = "macos")]
        {
            if let Ok(output) = Command::new("sysctl")
                .arg("-n")
                .arg("machdep.xcpm.cpu_thermal_level")
                .output()
            {
                if let Ok(thermal_level) = String::from_utf8_lossy(&output.stdout).trim().parse::<i32>() {
                    // Map thermal level to approximate temperature
                    // This is a rough approximation
                    return Some(match thermal_level {
                        0..=20 => 45.0,
                        21..=40 => 55.0,
                        41..=60 => 65.0,
                        61..=80 => 75.0,
                        81..=100 => 85.0,
                        _ => 95.0,
                    });
                }
            }
        }
        
        None
    }
    
    fn get_power_metrics(&self) -> Option<PowerMetrics> {
        // Try to get power metrics using powermetrics (requires sudo)
        // For now, return None as we don't want to require sudo
        // In the future, we could implement SMC reading
        None
    }
}

impl SensorType {
    pub fn icon(&self) -> &str {
        match self {
            SensorType::CpuCore | SensorType::CpuPackage => "cpu",
            SensorType::Gpu => "gpu.card",
            SensorType::Memory => "memorychip",
            SensorType::Storage => "internaldrive",
            SensorType::Battery => "battery.100",
            SensorType::Other => "thermometer",
        }
    }
    
    pub fn display_name(&self) -> &str {
        match self {
            SensorType::CpuCore => "CPU Core",
            SensorType::CpuPackage => "CPU Package",
            SensorType::Gpu => "GPU",
            SensorType::Memory => "Memory",
            SensorType::Storage => "Storage",
            SensorType::Battery => "Battery",
            SensorType::Other => "Other",
        }
    }
}

impl ThermalState {
    pub fn color(&self) -> &str {
        match self {
            ThermalState::Normal => "green",
            ThermalState::Warm => "yellow",
            ThermalState::Hot => "orange",
            ThermalState::Throttling => "red",
        }
    }
    
    pub fn description(&self) -> &str {
        match self {
            ThermalState::Normal => "Normal",
            ThermalState::Warm => "Warm",
            ThermalState::Hot => "Hot",
            ThermalState::Throttling => "Throttling",
        }
    }
}