use crate::memory_monitor::{MemoryMonitor, ProcessMemoryInfo, MemoryPressureLevel};
use once_cell::sync::Lazy;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::Mutex;

static MEMORY_MONITOR: Lazy<Mutex<MemoryMonitor>> = Lazy::new(|| {
    Mutex::new(MemoryMonitor::new())
});

#[repr(C)]
pub struct CMemoryInfo {
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
    pub free_bytes: u64,
    pub swap_total_bytes: u64,
    pub swap_used_bytes: u64,
    pub swap_free_bytes: u64,
    pub cached_bytes: u64,
    pub buffer_bytes: u64,
    pub usage_percent: f32,
    pub swap_usage_percent: f32,
    pub memory_pressure: *mut c_char,  // "Low", "Normal", "High", "Critical"
}

#[repr(C)]
pub struct CProcessMemoryInfo {
    pub pid: u32,
    pub name: *mut c_char,
    pub memory_bytes: u64,
    pub virtual_memory_bytes: u64,
    pub memory_percent: f32,
    pub is_growing: u8,  // bool as u8
    pub growth_rate_mb_per_min: f32,
}

#[repr(C)]
pub struct CProcessMemoryList {
    pub processes: *mut CProcessMemoryInfo,
    pub count: usize,
}

#[no_mangle]
pub extern "C" fn memory_monitor_init() {
    let _ = &*MEMORY_MONITOR;
}

#[no_mangle]
pub extern "C" fn memory_monitor_refresh() {
    if let Ok(mut monitor) = MEMORY_MONITOR.lock() {
        monitor.refresh();
    }
}

#[no_mangle]
pub extern "C" fn get_memory_info() -> *mut CMemoryInfo {
    let info = match MEMORY_MONITOR.lock() {
        Ok(monitor) => monitor.get_memory_info(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    let pressure = CString::new(info.memory_pressure.as_str())
        .unwrap_or_else(|_| CString::new("Unknown").unwrap());
    
    Box::into_raw(Box::new(CMemoryInfo {
        total_bytes: info.total_bytes,
        used_bytes: info.used_bytes,
        available_bytes: info.available_bytes,
        free_bytes: info.free_bytes,
        swap_total_bytes: info.swap_total_bytes,
        swap_used_bytes: info.swap_used_bytes,
        swap_free_bytes: info.swap_free_bytes,
        cached_bytes: info.cached_bytes,
        buffer_bytes: info.buffer_bytes,
        usage_percent: info.usage_percent,
        swap_usage_percent: info.swap_usage_percent,
        memory_pressure: pressure.into_raw(),
    }))
}

#[no_mangle]
pub extern "C" fn free_memory_info(info: *mut CMemoryInfo) {
    if !info.is_null() {
        unsafe {
            let boxed = Box::from_raw(info);
            if !boxed.memory_pressure.is_null() {
                let _ = CString::from_raw(boxed.memory_pressure);
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn get_process_memory_list() -> *mut CProcessMemoryList {
    let processes = match MEMORY_MONITOR.lock() {
        Ok(monitor) => monitor.get_process_memory_info(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    create_process_memory_list(processes)
}

#[no_mangle]
pub extern "C" fn get_top_memory_processes(limit: usize) -> *mut CProcessMemoryList {
    let processes = match MEMORY_MONITOR.lock() {
        Ok(monitor) => monitor.get_top_memory_processes(limit),
        Err(_) => return std::ptr::null_mut(),
    };
    
    create_process_memory_list(processes)
}

#[no_mangle]
pub extern "C" fn detect_memory_leaks() -> *mut CProcessMemoryList {
    let processes = match MEMORY_MONITOR.lock() {
        Ok(monitor) => monitor.detect_memory_leaks(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    create_process_memory_list(processes)
}

fn create_process_memory_list(processes: Vec<ProcessMemoryInfo>) -> *mut CProcessMemoryList {
    let count = processes.len();
    
    if count == 0 {
        return Box::into_raw(Box::new(CProcessMemoryList {
            processes: std::ptr::null_mut(),
            count: 0,
        }));
    }
    
    let mut c_processes = Vec::with_capacity(count);
    
    for process in processes {
        let name = CString::new(process.name.as_str())
            .unwrap_or_else(|_| CString::new("Unknown").unwrap());
        
        c_processes.push(CProcessMemoryInfo {
            pid: process.pid,
            name: name.into_raw(),
            memory_bytes: process.memory_bytes,
            virtual_memory_bytes: process.virtual_memory_bytes,
            memory_percent: process.memory_percent,
            is_growing: if process.is_growing { 1 } else { 0 },
            growth_rate_mb_per_min: process.growth_rate_mb_per_min,
        });
    }
    
    let mut boxed_processes = c_processes.into_boxed_slice();
    let processes_ptr = boxed_processes.as_mut_ptr();
    std::mem::forget(boxed_processes);
    
    Box::into_raw(Box::new(CProcessMemoryList {
        processes: processes_ptr,
        count,
    }))
}

#[no_mangle]
pub extern "C" fn free_process_memory_list(list: *mut CProcessMemoryList) {
    if !list.is_null() {
        unsafe {
            let boxed = Box::from_raw(list);
            
            if !boxed.processes.is_null() && boxed.count > 0 {
                let processes = Vec::from_raw_parts(
                    boxed.processes,
                    boxed.count,
                    boxed.count
                );
                
                for process in processes {
                    if !process.name.is_null() {
                        let _ = CString::from_raw(process.name);
                    }
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn get_memory_pressure() -> *mut c_char {
    let pressure = match MEMORY_MONITOR.lock() {
        Ok(monitor) => monitor.get_memory_pressure(),
        Err(_) => MemoryPressureLevel::Normal,
    };
    
    CString::new(pressure.as_str())
        .unwrap_or_else(|_| CString::new("Unknown").unwrap())
        .into_raw()
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}