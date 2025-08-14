use crate::{CpuAnalyzer, ProcessMonitor, KernelInterface, KillResult};
use once_cell::sync::Lazy;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::Mutex;

static PROCESS_MONITOR: Lazy<Mutex<ProcessMonitor>> = Lazy::new(|| {
    Mutex::new(ProcessMonitor::new())
});

static CPU_ANALYZER: Lazy<Mutex<CpuAnalyzer>> = Lazy::new(|| {
    Mutex::new(CpuAnalyzer::new())
});

#[repr(C)]
pub struct CProcessInfo {
    pub pid: u32,
    pub name: *mut c_char,
    pub cpu_usage: f32,
    pub memory_mb: f64,
    pub status: *mut c_char,
    pub parent_pid: u32,
    pub thread_count: usize,
    pub run_time: u64,
}

#[repr(C)]
pub struct CProcessList {
    pub processes: *mut CProcessInfo,
    pub count: usize,
}

#[repr(C)]
pub struct CCpuMetrics {
    pub total_usage: f32,
    pub core_count: usize,
    pub load_avg_1: f64,
    pub load_avg_5: f64,
    pub load_avg_15: f64,
    pub frequency_mhz: u64,
}

#[no_mangle]
pub extern "C" fn monitor_init() {
    let _ = &*PROCESS_MONITOR;
    let _ = &*CPU_ANALYZER;
}

#[no_mangle]
pub extern "C" fn monitor_refresh() {
    if let Ok(mut monitor) = PROCESS_MONITOR.lock() {
        monitor.refresh();
    }
    if let Ok(mut analyzer) = CPU_ANALYZER.lock() {
        analyzer.refresh();
    }
}

#[no_mangle]
pub extern "C" fn get_all_processes() -> *mut CProcessList {
    let processes = match PROCESS_MONITOR.lock() {
        Ok(monitor) => monitor.get_all_processes(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    let count = processes.len();
    if count == 0 {
        return Box::into_raw(Box::new(CProcessList {
            processes: std::ptr::null_mut(),
            count: 0,
        }));
    }
    
    // Allocate memory for all processes at once
    let mut c_processes = Vec::with_capacity(count);
    
    for process in processes {
        // Use unwrap_or_default for better performance
        let name = CString::new(process.name.as_str()).unwrap_or_default();
        let status = CString::new(process.status.as_str()).unwrap_or_default();
        
        c_processes.push(CProcessInfo {
            pid: process.pid,
            name: name.into_raw(),
            cpu_usage: process.cpu_usage,
            memory_mb: process.memory_mb,
            status: status.into_raw(),
            parent_pid: process.parent_pid.unwrap_or(0),
            thread_count: process.thread_count,
            run_time: process.run_time,
        });
    }
    
    let mut c_processes = c_processes.into_boxed_slice();
    let processes_ptr = c_processes.as_mut_ptr();
    
    let list = Box::new(CProcessList {
        processes: processes_ptr,
        count,
    });
    
    std::mem::forget(c_processes);
    Box::into_raw(list)
}

#[no_mangle]
pub extern "C" fn get_high_cpu_processes(threshold: f32) -> *mut CProcessList {
    let processes = match PROCESS_MONITOR.lock() {
        Ok(monitor) => monitor.get_high_cpu_processes(threshold),
        Err(_) => return std::ptr::null_mut(),
    };
    
    let count = processes.len();
    if count == 0 {
        return Box::into_raw(Box::new(CProcessList {
            processes: std::ptr::null_mut(),
            count: 0,
        }));
    }
    
    let mut c_processes = Vec::with_capacity(count);
    
    for process in processes {
        let name = CString::new(process.name.as_str()).unwrap_or_default();
        let status = CString::new(process.status.as_str()).unwrap_or_default();
        
        c_processes.push(CProcessInfo {
            pid: process.pid,
            name: name.into_raw(),
            cpu_usage: process.cpu_usage,
            memory_mb: process.memory_mb,
            status: status.into_raw(),
            parent_pid: process.parent_pid.unwrap_or(0),
            thread_count: process.thread_count,
            run_time: process.run_time,
        });
    }
    
    let mut c_processes = c_processes.into_boxed_slice();
    let processes_ptr = c_processes.as_mut_ptr();
    
    let list = Box::new(CProcessList {
        processes: processes_ptr,
        count,
    });
    
    std::mem::forget(c_processes);
    Box::into_raw(list)
}

#[no_mangle]
pub extern "C" fn get_cpu_metrics() -> *mut CCpuMetrics {
    let metrics = match CPU_ANALYZER.lock() {
        Ok(analyzer) => analyzer.get_current_metrics(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    Box::into_raw(Box::new(CCpuMetrics {
        total_usage: metrics.total_usage,
        core_count: metrics.per_core_usage.len(),
        load_avg_1: metrics.load_average.one_minute,
        load_avg_5: metrics.load_average.five_minutes,
        load_avg_15: metrics.load_average.fifteen_minutes,
        frequency_mhz: metrics.frequency_mhz,
    }))
}

#[no_mangle]
pub extern "C" fn free_process_list(list: *mut CProcessList) {
    if list.is_null() {
        return;
    }
    
    unsafe {
        let list = Box::from_raw(list);
        if !list.processes.is_null() && list.count > 0 {
            // Reconstruct the boxed slice to properly deallocate
            let processes = std::slice::from_raw_parts_mut(list.processes, list.count);
            for process in processes.iter() {
                if !process.name.is_null() {
                    let _ = CString::from_raw(process.name);
                }
                if !process.status.is_null() {
                    let _ = CString::from_raw(process.status);
                }
            }
            // Deallocate the slice
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(list.processes, list.count));
        }
    }
}

#[no_mangle]
pub extern "C" fn free_cpu_metrics(metrics: *mut CCpuMetrics) {
    if !metrics.is_null() {
        unsafe {
            let _ = Box::from_raw(metrics);
        }
    }
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[repr(C)]
pub enum CKillResult {
    Success = 0,
    ProcessNotFound = 1,
    PermissionDenied = 2,
    ProcessUnkillable = 3,
    UnknownError = 4,
}

#[no_mangle]
pub extern "C" fn terminate_process(pid: u32) -> CKillResult {
    let kernel = KernelInterface::new();
    match kernel.terminate_process(pid) {
        KillResult::Success => CKillResult::Success,
        KillResult::ProcessNotFound => CKillResult::ProcessNotFound,
        KillResult::PermissionDenied => CKillResult::PermissionDenied,
        KillResult::ProcessUnkillable(_) => CKillResult::ProcessUnkillable,
        KillResult::UnknownError(_) => CKillResult::UnknownError,
    }
}

#[no_mangle]
pub extern "C" fn force_kill_process(pid: u32) -> CKillResult {
    let kernel = KernelInterface::new();
    match kernel.force_kill_process(pid) {
        KillResult::Success => CKillResult::Success,
        KillResult::ProcessNotFound => CKillResult::ProcessNotFound,
        KillResult::PermissionDenied => CKillResult::PermissionDenied,
        KillResult::ProcessUnkillable(_) => CKillResult::ProcessUnkillable,
        KillResult::UnknownError(_) => CKillResult::UnknownError,
    }
}

#[no_mangle]
pub extern "C" fn suspend_process(pid: u32) -> bool {
    let kernel = KernelInterface::new();
    kernel.suspend_process(pid)
}

#[no_mangle]
pub extern "C" fn resume_process(pid: u32) -> bool {
    let kernel = KernelInterface::new();
    kernel.resume_process(pid)
}