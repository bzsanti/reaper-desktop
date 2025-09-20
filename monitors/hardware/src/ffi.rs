use crate::HARDWARE_MONITOR;
use crate::hardware_monitor::{SensorType, ThermalState};
use std::ffi::CString;
use std::os::raw::c_char;

#[repr(C)]
pub struct CHardwareMetrics {
    pub temperatures: *mut CTemperatureSensor,
    pub temperature_count: usize,
    pub cpu_frequency_mhz: u64,
    pub thermal_state: u8,  // 0=Normal, 1=Warm, 2=Hot, 3=Throttling
    pub cpu_power_watts: f32,
    pub gpu_power_watts: f32,
    pub total_power_watts: f32,
    pub has_power_metrics: u8,
}

#[repr(C)]
pub struct CTemperatureSensor {
    pub name: *mut c_char,
    pub value_celsius: f32,
    pub sensor_type: u8,  // Maps to SensorType enum
    pub is_critical: u8,
}

#[no_mangle]
pub extern "C" fn hardware_monitor_init() {
    // Initialize the hardware monitor
    let _guard = HARDWARE_MONITOR.lock();
}

#[no_mangle]
pub extern "C" fn hardware_monitor_refresh() {
    if let Ok(mut monitor) = HARDWARE_MONITOR.lock() {
        // Force refresh by getting metrics
        let _ = monitor.get_metrics();
    }
}

#[no_mangle]
pub extern "C" fn get_hardware_metrics() -> *mut CHardwareMetrics {
    let metrics = match HARDWARE_MONITOR.lock() {
        Ok(mut monitor) => monitor.get_metrics(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    // Convert temperatures to C format
    let mut c_temperatures = Vec::with_capacity(metrics.temperatures.len());
    
    for sensor in &metrics.temperatures {
        let name = CString::new(sensor.name.clone()).unwrap_or_else(|_| CString::new("Unknown").unwrap());
        
        let sensor_type = match sensor.sensor_type {
            SensorType::CpuCore => 0,
            SensorType::CpuPackage => 1,
            SensorType::Gpu => 2,
            SensorType::Memory => 3,
            SensorType::Storage => 4,
            SensorType::Battery => 5,
            SensorType::Other => 6,
        };
        
        c_temperatures.push(CTemperatureSensor {
            name: name.into_raw(),
            value_celsius: sensor.value_celsius,
            sensor_type,
            is_critical: if sensor.is_critical { 1 } else { 0 },
        });
    }
    
    let thermal_state = match metrics.thermal_state {
        ThermalState::Normal => 0,
        ThermalState::Warm => 1,
        ThermalState::Hot => 2,
        ThermalState::Throttling => 3,
    };
    
    let (cpu_power, gpu_power, total_power, has_power) = if let Some(power) = metrics.power_metrics {
        (
            power.cpu_power_watts.unwrap_or(0.0),
            power.gpu_power_watts.unwrap_or(0.0),
            power.total_power_watts.unwrap_or(0.0),
            1
        )
    } else {
        (0.0, 0.0, 0.0, 0)
    };
    
    let temperature_count = c_temperatures.len();
    let mut c_temperatures = c_temperatures.into_boxed_slice();
    let temperatures_ptr = if temperature_count > 0 {
        c_temperatures.as_mut_ptr()
    } else {
        std::ptr::null_mut()
    };
    
    let c_metrics = Box::new(CHardwareMetrics {
        temperatures: temperatures_ptr,
        temperature_count,
        cpu_frequency_mhz: metrics.cpu_frequency_mhz,
        thermal_state,
        cpu_power_watts: cpu_power,
        gpu_power_watts: gpu_power,
        total_power_watts: total_power,
        has_power_metrics: has_power,
    });
    
    // Prevent deallocation of the temperature array
    std::mem::forget(c_temperatures);
    
    Box::into_raw(c_metrics)
}

#[no_mangle]
pub extern "C" fn free_hardware_metrics(metrics: *mut CHardwareMetrics) {
    if metrics.is_null() {
        return;
    }
    
    unsafe {
        let metrics = Box::from_raw(metrics);
        
        // Free temperature sensors
        if !metrics.temperatures.is_null() && metrics.temperature_count > 0 {
            let temperatures = Vec::from_raw_parts(
                metrics.temperatures,
                metrics.temperature_count,
                metrics.temperature_count
            );
            
            // Free each sensor name
            for sensor in temperatures {
                if !sensor.name.is_null() {
                    let _ = CString::from_raw(sensor.name);
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn get_thermal_state() -> u8 {
    match HARDWARE_MONITOR.lock() {
        Ok(mut monitor) => {
            let metrics = monitor.get_metrics();
            match metrics.thermal_state {
                ThermalState::Normal => 0,
                ThermalState::Warm => 1,
                ThermalState::Hot => 2,
                ThermalState::Throttling => 3,
            }
        }
        Err(_) => 0,
    }
}