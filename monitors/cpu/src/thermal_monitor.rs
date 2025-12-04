use std::collections::HashMap;
use std::ffi::CString;
use std::time::{Duration, Instant, SystemTime};
use serde::{Deserialize, Serialize};
use libc::{c_char, c_int, c_void, size_t};

// IOKit and CoreFoundation bindings
extern "C" {
    // IOKit Service Matching
    fn IOServiceMatching(name: *const c_char) -> *mut c_void;
    fn IOServiceGetMatchingServices(
        master_port: u32,
        matching: *mut c_void,
        iterator: *mut u32,
    ) -> c_int;
    fn IOIteratorNext(iterator: u32) -> u32;
    fn IOObjectRelease(object: u32) -> c_int;
    
    // IOKit Registry
    fn IORegistryEntryCreateCFProperty(
        entry: u32,
        key: *const c_void,
        allocator: *const c_void,
        options: u32,
    ) -> *mut c_void;
    
    // CoreFoundation String
    fn CFStringCreateWithCString(
        allocator: *const c_void,
        cstr: *const c_char,
        encoding: u32,
    ) -> *mut c_void;
    fn CFRelease(cf: *mut c_void);
    
    // CoreFoundation Number
    fn CFNumberGetValue(
        number: *mut c_void,
        the_type: i32,
        value_ptr: *mut c_void,
    ) -> bool;
    
    // CoreFoundation Data
    fn CFDataGetBytePtr(data: *mut c_void) -> *const u8;
    fn CFDataGetLength(data: *mut c_void) -> size_t;
}

const CF_STRING_ENCODING_UTF8: u32 = 0x08000100;
const K_CF_NUMBER_FLOAT_TYPE: i32 = 12;

/// Thermal sensor information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThermalSensor {
    pub name: String,
    pub location: ThermalLocation,
    pub current_temperature: f32,
    pub max_temperature: f32,
    pub critical_temperature: f32,
    pub sensor_type: SensorType,
    pub is_valid: bool,
}

/// Thermal location on the system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ThermalLocation {
    CpuCore(u32),        // CPU core number
    CpuPackage,          // Entire CPU package
    Gpu,                 // Graphics processor
    Memory,              // Memory modules
    PowerSupply,         // Power management unit
    Ambient,             // Ambient temperature
    Battery,             // Battery temperature
    Other(String),       // Other location
}

/// Type of thermal sensor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SensorType {
    Digital,             // Digital temperature sensor
    Analog,              // Analog temperature sensor
    Diode,               // Thermal diode
    Thermistor,          // Thermistor sensor
    Unknown,             // Unknown sensor type
}

/// Thermal throttling event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThermalThrottlingEvent {
    pub timestamp: SystemTime,
    pub sensor_name: String,
    pub temperature_celsius: f32,
    pub throttling_level: ThrottlingLevel,
    pub duration_ms: Option<u64>,
    pub affected_processes: Vec<u32>,
    pub cpu_frequency_before: Option<u64>,
    pub cpu_frequency_after: Option<u64>,
}

/// Level of thermal throttling
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ThrottlingLevel {
    None,                // No throttling
    Light,               // Minor frequency reduction
    Moderate,            // Significant frequency reduction  
    Heavy,               // Severe throttling
    Critical,            // Emergency shutdown protection
}

/// Thermal monitoring configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThermalConfig {
    pub polling_interval_ms: u64,
    pub temperature_threshold_celsius: f32,
    pub throttling_detection_enabled: bool,
    pub sensor_blacklist: Vec<String>,
    pub alert_on_high_temperature: bool,
    pub max_history_entries: usize,
}

impl Default for ThermalConfig {
    fn default() -> Self {
        Self {
            polling_interval_ms: 1000,
            temperature_threshold_celsius: 80.0,
            throttling_detection_enabled: true,
            sensor_blacklist: Vec::new(),
            alert_on_high_temperature: true,
            max_history_entries: 1000,
        }
    }
}

/// Thermal monitoring system
pub struct ThermalMonitor {
    config: ThermalConfig,
    sensors: Vec<ThermalSensor>,
    throttling_history: Vec<ThermalThrottlingEvent>,
    last_update: Instant,
    temperature_history: HashMap<String, Vec<(Instant, f32)>>,
    baseline_frequency: Option<u64>,
}

impl ThermalMonitor {
    pub fn new(config: ThermalConfig) -> std::io::Result<Self> {
        let mut monitor = Self {
            config,
            sensors: Vec::new(),
            throttling_history: Vec::new(),
            last_update: Instant::now(),
            temperature_history: HashMap::new(),
            baseline_frequency: None,
        };

        monitor.discover_thermal_sensors()?;
        monitor.initialize_baseline_frequency()?;

        Ok(monitor)
    }

    pub fn update(&mut self) -> std::io::Result<()> {
        if self.last_update.elapsed() < Duration::from_millis(self.config.polling_interval_ms) {
            return Ok(());
        }

        // Update sensor readings
        self.update_sensor_temperatures()?;

        // Detect thermal throttling
        if self.config.throttling_detection_enabled {
            self.detect_thermal_throttling()?;
        }

        // Update temperature history
        self.update_temperature_history();

        // Trim history if needed
        self.trim_history();

        self.last_update = Instant::now();
        Ok(())
    }

    pub fn get_sensors(&self) -> &[ThermalSensor] {
        &self.sensors
    }

    pub fn get_throttling_events(&self) -> &[ThermalThrottlingEvent] {
        &self.throttling_history
    }

    pub fn get_hottest_temperature(&self) -> Option<f32> {
        self.sensors
            .iter()
            .filter(|s| s.is_valid)
            .map(|s| s.current_temperature)
            .fold(None, |max, temp| {
                Some(max.unwrap_or(temp).max(temp))
            })
    }

    pub fn get_cpu_temperature(&self) -> Option<f32> {
        self.sensors
            .iter()
            .find(|s| matches!(s.location, ThermalLocation::CpuPackage) && s.is_valid)
            .map(|s| s.current_temperature)
            .or_else(|| {
                // Average of CPU core temperatures
                let core_temps: Vec<f32> = self.sensors
                    .iter()
                    .filter(|s| matches!(s.location, ThermalLocation::CpuCore(_)) && s.is_valid)
                    .map(|s| s.current_temperature)
                    .collect();

                if !core_temps.is_empty() {
                    Some(core_temps.iter().sum::<f32>() / core_temps.len() as f32)
                } else {
                    None
                }
            })
    }

    pub fn is_throttling_active(&self) -> bool {
        !self.throttling_history.is_empty() && 
        self.throttling_history
            .last()
            .map(|event| {
                event.timestamp
                    .elapsed()
                    .unwrap_or(Duration::from_secs(60))
                    < Duration::from_secs(30)
            })
            .unwrap_or(false)
    }

    pub fn get_thermal_statistics(&self) -> ThermalStatistics {
        let valid_sensors: Vec<&ThermalSensor> = self.sensors
            .iter()
            .filter(|s| s.is_valid)
            .collect();

        if valid_sensors.is_empty() {
            return ThermalStatistics::default();
        }

        let current_temps: Vec<f32> = valid_sensors
            .iter()
            .map(|s| s.current_temperature)
            .collect();

        let avg_temp = current_temps.iter().sum::<f32>() / current_temps.len() as f32;
        let max_temp = current_temps.iter().fold(f32::NEG_INFINITY, |a, &b| a.max(b));
        let min_temp = current_temps.iter().fold(f32::INFINITY, |a, &b| a.min(b));

        ThermalStatistics {
            sensor_count: valid_sensors.len(),
            average_temperature: avg_temp,
            max_temperature: max_temp,
            min_temperature: min_temp,
            cpu_temperature: self.get_cpu_temperature(),
            throttling_events_last_hour: self.count_recent_throttling_events(Duration::from_secs(3600)),
            is_currently_throttling: self.is_throttling_active(),
        }
    }

    fn discover_thermal_sensors(&mut self) -> std::io::Result<()> {
        unsafe {
            // Search for AppleSMC service
            let service_name = CString::new("AppleSMC")?;
            let matching = IOServiceMatching(service_name.as_ptr());
            if matching.is_null() {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "Could not create IOKit service matching for AppleSMC",
                ));
            }

            let mut iterator = 0;
            let result = IOServiceGetMatchingServices(0, matching, &mut iterator);
            if result != 0 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    "Could not get AppleSMC services",
                ));
            }

            let mut service = IOIteratorNext(iterator);
            while service != 0 {
                self.read_smc_sensors(service)?;
                IOObjectRelease(service);
                service = IOIteratorNext(iterator);
            }

            IOObjectRelease(iterator);
        }

        // Add common thermal sensor locations if not found via SMC
        if self.sensors.is_empty() {
            self.add_fallback_sensors();
        }

        Ok(())
    }

    fn read_smc_sensors(&mut self, service: u32) -> std::io::Result<()> {
        // Common macOS thermal sensor keys
        let sensor_keys = vec![
            ("TC0P", "CPU Proximity", ThermalLocation::CpuPackage),
            ("TC0H", "CPU Heatsink", ThermalLocation::CpuPackage),
            ("TC0D", "CPU Die", ThermalLocation::CpuPackage),
            ("TC1C", "CPU Core 1", ThermalLocation::CpuCore(0)),
            ("TC2C", "CPU Core 2", ThermalLocation::CpuCore(1)),
            ("TC3C", "CPU Core 3", ThermalLocation::CpuCore(2)),
            ("TC4C", "CPU Core 4", ThermalLocation::CpuCore(3)),
            ("TGDD", "GPU Die", ThermalLocation::Gpu),
            ("TM0P", "Memory Proximity", ThermalLocation::Memory),
            ("TA0P", "Ambient", ThermalLocation::Ambient),
            ("TB1T", "Battery", ThermalLocation::Battery),
        ];

        for (key, name, location) in sensor_keys {
            if let Some(temperature) = self.read_smc_temperature(service, key)? {
                let sensor = ThermalSensor {
                    name: name.to_string(),
                    location,
                    current_temperature: temperature,
                    max_temperature: temperature,
                    critical_temperature: 100.0, // Default critical temp
                    sensor_type: SensorType::Digital,
                    is_valid: temperature > -50.0 && temperature < 150.0,
                };

                if sensor.is_valid && !self.config.sensor_blacklist.contains(&sensor.name) {
                    self.sensors.push(sensor);
                }
            }
        }

        Ok(())
    }

    fn read_smc_temperature(&self, service: u32, key: &str) -> std::io::Result<Option<f32>> {
        unsafe {
            let key_string = CString::new(key)?;
            let cf_key = CFStringCreateWithCString(
                std::ptr::null(),
                key_string.as_ptr(),
                CF_STRING_ENCODING_UTF8,
            );
            
            if cf_key.is_null() {
                return Ok(None);
            }

            let property = IORegistryEntryCreateCFProperty(
                service,
                cf_key,
                std::ptr::null(),
                0,
            );

            CFRelease(cf_key);

            if property.is_null() {
                return Ok(None);
            }

            // Try to read as CFNumber first
            let mut temperature: f32 = 0.0;
            if CFNumberGetValue(property, K_CF_NUMBER_FLOAT_TYPE, &mut temperature as *mut f32 as *mut c_void) {
                CFRelease(property);
                return Ok(Some(temperature));
            }

            // Try to read as CFData (raw SMC data)
            let data_ptr = CFDataGetBytePtr(property);
            let data_length = CFDataGetLength(property);

            if !data_ptr.is_null() && data_length >= 4 {
                // SMC temperature is typically stored as a fixed-point value
                let bytes = std::slice::from_raw_parts(data_ptr, data_length);
                if bytes.len() >= 2 {
                    let raw_value = ((bytes[0] as u16) << 8) | (bytes[1] as u16);
                    let temperature = raw_value as f32 / 256.0; // SMC fixed-point conversion
                    CFRelease(property);
                    return Ok(Some(temperature));
                }
            }

            CFRelease(property);
        }

        Ok(None)
    }

    fn add_fallback_sensors(&mut self) {
        // Add CPU package sensor using sysctl if available
        if let Ok(temp) = self.read_cpu_temperature_sysctl() {
            self.sensors.push(ThermalSensor {
                name: "CPU Package (sysctl)".to_string(),
                location: ThermalLocation::CpuPackage,
                current_temperature: temp,
                max_temperature: temp,
                critical_temperature: 100.0,
                sensor_type: SensorType::Digital,
                is_valid: temp > 0.0 && temp < 150.0,
            });
        }
    }

    fn read_cpu_temperature_sysctl(&self) -> std::io::Result<f32> {
        // This is a simplified fallback - in a real implementation,
        // you would use sysctlbyname to read thermal data
        use std::process::Command;

        let output = Command::new("sysctl")
            .arg("-n")
            .arg("machdep.xcpm.cpu_thermal_state")
            .output()?;

        if output.status.success() {
            let temp_str = String::from_utf8_lossy(&output.stdout);
            temp_str.trim().parse::<f32>()
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        } else {
            Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "Could not read CPU temperature via sysctl",
            ))
        }
    }

    fn update_sensor_temperatures(&mut self) -> std::io::Result<()> {
        // In a real implementation, you would re-read from IOKit/SMC
        // For now, we'll simulate temperature updates
        for sensor in &mut self.sensors {
            if sensor.is_valid {
                // Simulate small temperature variations
                let variation = (rand::random::<f32>() - 0.5) * 2.0; // ±1°C variation
                sensor.current_temperature = (sensor.current_temperature + variation)
                    .max(20.0)
                    .min(120.0);
                
                sensor.max_temperature = sensor.max_temperature.max(sensor.current_temperature);
            }
        }
        
        Ok(())
    }

    fn detect_thermal_throttling(&mut self) -> std::io::Result<()> {
        let current_frequency = self.get_current_cpu_frequency()?;
        
        if let (Some(current), Some(baseline)) = (current_frequency, self.baseline_frequency) {
            let frequency_ratio = current as f32 / baseline as f32;
            
            // Detect throttling based on frequency reduction
            let throttling_level = if frequency_ratio < 0.5 {
                ThrottlingLevel::Critical
            } else if frequency_ratio < 0.7 {
                ThrottlingLevel::Heavy
            } else if frequency_ratio < 0.85 {
                ThrottlingLevel::Moderate
            } else if frequency_ratio < 0.95 {
                ThrottlingLevel::Light
            } else {
                ThrottlingLevel::None
            };

            // Check if any sensors are above threshold
            let hot_sensors: Vec<&ThermalSensor> = self.sensors
                .iter()
                .filter(|s| s.is_valid && s.current_temperature > self.config.temperature_threshold_celsius)
                .collect();

            if !hot_sensors.is_empty() && !matches!(throttling_level, ThrottlingLevel::None) {
                let hottest_sensor = hot_sensors
                    .iter()
                    .max_by(|a, b| a.current_temperature.partial_cmp(&b.current_temperature).unwrap())
                    .unwrap();

                let event = ThermalThrottlingEvent {
                    timestamp: SystemTime::now(),
                    sensor_name: hottest_sensor.name.clone(),
                    temperature_celsius: hottest_sensor.current_temperature,
                    throttling_level,
                    duration_ms: None,
                    affected_processes: Vec::new(), // Would be populated in real implementation
                    cpu_frequency_before: Some(baseline),
                    cpu_frequency_after: Some(current),
                };

                self.throttling_history.push(event);
            }
        }

        Ok(())
    }

    fn get_current_cpu_frequency(&self) -> std::io::Result<Option<u64>> {
        use std::process::Command;

        let output = Command::new("sysctl")
            .arg("-n")
            .arg("hw.cpufrequency")
            .output()?;

        if output.status.success() {
            let freq_str = String::from_utf8_lossy(&output.stdout);
            freq_str.trim().parse::<u64>()
                .map(Some)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
        } else {
            Ok(None)
        }
    }

    fn initialize_baseline_frequency(&mut self) -> std::io::Result<()> {
        self.baseline_frequency = self.get_current_cpu_frequency()?;
        Ok(())
    }

    fn update_temperature_history(&mut self) {
        let now = Instant::now();
        
        for sensor in &self.sensors {
            if sensor.is_valid {
                let history = self.temperature_history
                    .entry(sensor.name.clone())
                    .or_insert_with(Vec::new);
                
                history.push((now, sensor.current_temperature));
                
                // Keep only recent history
                let cutoff = now - Duration::from_secs(3600); // 1 hour
                history.retain(|(timestamp, _)| *timestamp > cutoff);
            }
        }
    }

    fn trim_history(&mut self) {
        if self.throttling_history.len() > self.config.max_history_entries {
            let excess = self.throttling_history.len() - self.config.max_history_entries;
            self.throttling_history.drain(0..excess);
        }
    }

    fn count_recent_throttling_events(&self, duration: Duration) -> usize {
        let cutoff = SystemTime::now() - duration;
        
        self.throttling_history
            .iter()
            .filter(|event| event.timestamp > cutoff)
            .count()
    }
}

/// Thermal monitoring statistics
#[derive(Debug, Clone)]
pub struct ThermalStatistics {
    pub sensor_count: usize,
    pub average_temperature: f32,
    pub max_temperature: f32,
    pub min_temperature: f32,
    pub cpu_temperature: Option<f32>,
    pub throttling_events_last_hour: usize,
    pub is_currently_throttling: bool,
}

impl Default for ThermalStatistics {
    fn default() -> Self {
        Self {
            sensor_count: 0,
            average_temperature: 0.0,
            max_temperature: 0.0,
            min_temperature: 0.0,
            cpu_temperature: None,
            throttling_events_last_hour: 0,
            is_currently_throttling: false,
        }
    }
}

// Mock random function for testing
mod rand {
    use std::cell::Cell;
    
    thread_local! {
        static SEED: Cell<u64> = Cell::new(1);
    }
    
    pub fn random<T>() -> T
    where
        T: From<f32>,
    {
        SEED.with(|seed| {
            let mut s = seed.get();
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            seed.set(s);
            T::from((s as f32) / (u64::MAX as f32))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_thermal_config_default() {
        let config = ThermalConfig::default();
        assert_eq!(config.polling_interval_ms, 1000);
        assert_eq!(config.temperature_threshold_celsius, 80.0);
        assert!(config.throttling_detection_enabled);
    }

    #[test]
    fn test_thermal_statistics_default() {
        let stats = ThermalStatistics::default();
        assert_eq!(stats.sensor_count, 0);
        assert_eq!(stats.average_temperature, 0.0);
        assert!(!stats.is_currently_throttling);
    }

    #[test]
    fn test_throttling_level_ordering() {
        use std::mem;
        
        // Ensure throttling levels have meaningful ordering
        assert!(mem::discriminant(&ThrottlingLevel::None) != mem::discriminant(&ThrottlingLevel::Critical));
    }
}