use crate::{CpuAnalyzer, ProcessMonitor, KernelInterface, ProcessAction, ActionResult, ProcessDetails, ProcessTreeBuilder, ProcessTreeNode};
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

static KERNEL_INTERFACE: Lazy<Mutex<KernelInterface>> = Lazy::new(|| {
    Mutex::new(KernelInterface::new())
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
    pub user_time: f64,
    pub system_time: f64,
    
    // Advanced analysis fields
    pub io_wait_time_ms: u64,
    pub context_switches: u64,
    pub minor_faults: u64,
    pub major_faults: u64,
    pub priority: i32,
    pub is_unkillable: u8,  // bool as u8 for C compatibility
    pub is_problematic: u8, // bool as u8 for C compatibility
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
        // Create CStrings safely, handling potential errors
        let name = match CString::new(process.name.as_str()) {
            Ok(s) => s,
            Err(_) => CString::new("Unknown").unwrap(),
        };
        let status = match CString::new(process.status.as_str()) {
            Ok(s) => s,
            Err(_) => CString::new("Unknown").unwrap(),
        };
        
        c_processes.push(CProcessInfo {
            pid: process.pid,
            name: name.into_raw(),
            cpu_usage: process.cpu_usage,
            memory_mb: process.memory_mb,
            status: status.into_raw(),
            parent_pid: process.parent_pid.unwrap_or(0),
            thread_count: process.thread_count,
            run_time: process.run_time,
            user_time: process.user_time as f64,
            system_time: process.system_time as f64,
            
            // Advanced analysis fields
            io_wait_time_ms: process.io_wait_time_ms,
            context_switches: process.context_switches,
            minor_faults: process.minor_faults,
            major_faults: process.major_faults,
            priority: process.priority,
            is_unkillable: if process.is_unkillable { 1 } else { 0 },
            is_problematic: if process.is_problematic { 1 } else { 0 },
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
        // Create CStrings safely, handling potential errors
        let name = match CString::new(process.name.as_str()) {
            Ok(s) => s,
            Err(_) => CString::new("Unknown").unwrap(),
        };
        let status = match CString::new(process.status.as_str()) {
            Ok(s) => s,
            Err(_) => CString::new("Unknown").unwrap(),
        };
        
        c_processes.push(CProcessInfo {
            pid: process.pid,
            name: name.into_raw(),
            cpu_usage: process.cpu_usage,
            memory_mb: process.memory_mb,
            status: status.into_raw(),
            parent_pid: process.parent_pid.unwrap_or(0),
            thread_count: process.thread_count,
            run_time: process.run_time,
            user_time: process.user_time as f64,
            system_time: process.system_time as f64,
            
            // Advanced analysis fields
            io_wait_time_ms: process.io_wait_time_ms,
            context_switches: process.context_switches,
            minor_faults: process.minor_faults,
            major_faults: process.major_faults,
            priority: process.priority,
            is_unkillable: if process.is_unkillable { 1 } else { 0 },
            is_problematic: if process.is_problematic { 1 } else { 0 },
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
pub enum CActionResult {
    Success = 0,
    ProcessNotFound = 1,
    PermissionDenied = 2,
    ProcessUnkillable = 3,
    AlreadyInState = 4,
    UnknownError = 5,
}

#[repr(C)]
pub struct CActionResponse {
    pub result: CActionResult,
    pub message: *mut c_char,
}

#[repr(C)]
pub struct CProcessDetails {
    pub pid: u32,
    pub name: *mut c_char,
    pub exe_path: *mut c_char,
    pub command_line: *mut c_char,
    pub working_directory: *mut c_char,
    pub user_id: u32,
    pub parent_pid: u32,
    pub threads_count: usize,
    pub open_files_count: usize,
    pub cpu_usage: f32,
    pub memory_usage: u64,
    pub virtual_memory: u64,
    pub start_time: u64,
    pub state: *mut c_char,
    pub environment_count: usize,
    pub environment_vars: *mut CEnvironmentVar,
}

#[repr(C)]
pub struct CEnvironmentVar {
    pub key: *mut c_char,
    pub value: *mut c_char,
}

#[no_mangle]
pub extern "C" fn terminate_process(pid: u32) -> *mut CActionResponse {
    execute_process_action(pid, ProcessAction::Terminate)
}

#[no_mangle]
pub extern "C" fn force_kill_process(pid: u32) -> *mut CActionResponse {
    execute_process_action(pid, ProcessAction::Kill)
}

#[no_mangle]
pub extern "C" fn suspend_process(pid: u32) -> *mut CActionResponse {
    execute_process_action(pid, ProcessAction::Suspend)
}

#[no_mangle]
pub extern "C" fn resume_process(pid: u32) -> *mut CActionResponse {
    execute_process_action(pid, ProcessAction::Resume)
}

fn execute_process_action(pid: u32, action: ProcessAction) -> *mut CActionResponse {
    let result = match KERNEL_INTERFACE.lock() {
        Ok(mut kernel) => kernel.execute_action(pid, action),
        Err(_) => ActionResult::UnknownError("Failed to acquire kernel interface lock".to_string()),
    };
    
    let (c_result, message) = match result {
        ActionResult::Success(msg) => (CActionResult::Success, msg),
        ActionResult::ProcessNotFound => (CActionResult::ProcessNotFound, "Process not found".to_string()),
        ActionResult::PermissionDenied(msg) => (CActionResult::PermissionDenied, msg),
        ActionResult::ProcessUnkillable(msg) => (CActionResult::ProcessUnkillable, msg),
        ActionResult::AlreadyInState(msg) => (CActionResult::AlreadyInState, msg),
        ActionResult::UnknownError(msg) => (CActionResult::UnknownError, msg),
    };
    
    let c_message = CString::new(message).unwrap_or_else(|_| CString::new("Error").unwrap());
    
    Box::into_raw(Box::new(CActionResponse {
        result: c_result,
        message: c_message.into_raw(),
    }))
}

#[no_mangle]
pub extern "C" fn get_process_details(pid: u32) -> *mut CProcessDetails {
    let details = match ProcessDetails::new(pid) {
        Some(d) => d,
        None => return std::ptr::null_mut(),
    };
    
    // Convert command line vector to single string
    let command_line = details.arguments.join(" ");
    
    // Convert environment variables
    let env_count = details.environment.len();
    let mut env_vars = Vec::with_capacity(env_count);
    
    for (key, value) in details.environment.iter() {
        let c_key = CString::new(key.as_str()).unwrap_or_else(|_| CString::new("").unwrap());
        let c_value = CString::new(value.as_str()).unwrap_or_else(|_| CString::new("").unwrap());
        
        env_vars.push(CEnvironmentVar {
            key: c_key.into_raw(),
            value: c_value.into_raw(),
        });
    }
    
    // Get process name from executable path
    let name = details.executable_path.split('/').last().unwrap_or("Unknown").to_string();
    
    let c_name = CString::new(name.as_str()).unwrap_or_else(|_| CString::new("Unknown").unwrap());
    let c_exe_path = CString::new(details.executable_path.as_str()).unwrap_or_else(|_| CString::new("Unknown").unwrap());
    let c_command_line = CString::new(command_line.as_str()).unwrap_or_else(|_| CString::new("").unwrap());
    let c_working_dir = CString::new("Unknown").unwrap(); // ProcessDetails doesn't have working_directory
    let c_state = CString::new("Unknown").unwrap(); // ProcessDetails doesn't have state
    
    let env_ptr = if env_vars.is_empty() {
        std::ptr::null_mut()
    } else {
        let boxed_slice = env_vars.into_boxed_slice();
        Box::into_raw(boxed_slice) as *mut CEnvironmentVar
    };
    
    Box::into_raw(Box::new(CProcessDetails {
        pid: details.pid,
        name: c_name.into_raw(),
        exe_path: c_exe_path.into_raw(),
        command_line: c_command_line.into_raw(),
        working_directory: c_working_dir.into_raw(),
        user_id: 0, // ProcessDetails doesn't have user_id
        parent_pid: 0, // ProcessDetails doesn't have parent_pid
        threads_count: 0, // ProcessDetails doesn't have threads_count
        open_files_count: details.open_files.len(),
        cpu_usage: 0.0, // ProcessDetails doesn't have cpu_usage
        memory_usage: 0, // ProcessDetails doesn't have memory_usage
        virtual_memory: 0, // ProcessDetails doesn't have virtual_memory
        start_time: 0, // ProcessDetails doesn't have start_time
        state: c_state.into_raw(),
        environment_count: env_count,
        environment_vars: env_ptr,
    }))
}

#[no_mangle]
pub extern "C" fn free_action_response(response: *mut CActionResponse) {
    if !response.is_null() {
        unsafe {
            let response = Box::from_raw(response);
            if !response.message.is_null() {
                let _ = CString::from_raw(response.message);
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn free_process_details(details: *mut CProcessDetails) {
    if !details.is_null() {
        unsafe {
            let details = Box::from_raw(details);
            
            // Free all string fields
            if !details.name.is_null() {
                let _ = CString::from_raw(details.name);
            }
            if !details.exe_path.is_null() {
                let _ = CString::from_raw(details.exe_path);
            }
            if !details.command_line.is_null() {
                let _ = CString::from_raw(details.command_line);
            }
            if !details.working_directory.is_null() {
                let _ = CString::from_raw(details.working_directory);
            }
            if !details.state.is_null() {
                let _ = CString::from_raw(details.state);
            }
            
            // Free environment variables
            if !details.environment_vars.is_null() && details.environment_count > 0 {
                let env_slice = std::slice::from_raw_parts_mut(
                    details.environment_vars,
                    details.environment_count
                );
                
                for env_var in env_slice.iter() {
                    if !env_var.key.is_null() {
                        let _ = CString::from_raw(env_var.key);
                    }
                    if !env_var.value.is_null() {
                        let _ = CString::from_raw(env_var.value);
                    }
                }
                
                let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                    details.environment_vars,
                    details.environment_count
                ));
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn get_cpu_usage_only() -> f32 {
    // Lightweight function that only gets CPU usage, no process list
    match CPU_ANALYZER.lock() {
        Ok(mut analyzer) => {
            analyzer.refresh();
            analyzer.get_current_metrics().total_usage
        }
        Err(_) => 0.0,
    }
}

#[no_mangle]
pub extern "C" fn monitor_cleanup() {
    // Cleanup function for graceful shutdown
    // The static mutexes will be cleaned up automatically
    // This is here for explicit cleanup if needed
}



// Process Tree FFI structures
#[repr(C)]
pub struct CProcessTreeNode {
    pub pid: u32,
    pub name: *mut c_char,
    pub command: *mut *mut c_char,  // Array of strings
    pub command_count: usize,
    pub executable_path: *mut c_char,
    pub cpu_usage: f32,
    pub memory_mb: f64,
    pub status: *mut c_char,
    pub thread_count: usize,
    pub children: *mut CProcessTreeNode,
    pub children_count: usize,
    pub total_cpu_usage: f32,
    pub total_memory_mb: f64,
    pub descendant_count: usize,
}

#[repr(C)]
pub struct CProcessTree {
    pub roots: *mut CProcessTreeNode,
    pub roots_count: usize,
    pub total_processes: usize,
}

// Helper function to convert ProcessTreeNode to CProcessTreeNode
fn convert_tree_node(node: ProcessTreeNode) -> CProcessTreeNode {
    let name = CString::new(node.name).unwrap_or_default();
    let executable_path = CString::new(node.executable_path).unwrap_or_default();
    let status = CString::new(node.status).unwrap_or_default();
    
    // Convert command arguments
    let mut c_command: Vec<*mut c_char> = node.command
        .into_iter()
        .map(|arg| CString::new(arg).unwrap_or_default().into_raw())
        .collect();
    
    // Convert children recursively
    let mut c_children: Vec<CProcessTreeNode> = node.children
        .into_iter()
        .map(convert_tree_node)
        .collect();
    
    let result = CProcessTreeNode {
        pid: node.pid,
        name: name.into_raw(),
        command: c_command.as_mut_ptr(),
        command_count: c_command.len(),
        executable_path: executable_path.into_raw(),
        cpu_usage: node.cpu_usage,
        memory_mb: node.memory_mb,
        status: status.into_raw(),
        thread_count: node.thread_count,
        children: if c_children.is_empty() { 
            std::ptr::null_mut() 
        } else { 
            c_children.as_mut_ptr() 
        },
        children_count: c_children.len(),
        total_cpu_usage: node.total_cpu_usage,
        total_memory_mb: node.total_memory_mb,
        descendant_count: node.descendant_count,
    };
    
    // Prevent vectors from being deallocated
    std::mem::forget(c_command);
    std::mem::forget(c_children);
    
    result
}

#[no_mangle]
pub extern "C" fn get_process_tree() -> *mut CProcessTree {
    let mut builder = ProcessTreeBuilder::new();
    let tree = builder.build_tree();
    
    // Convert roots to C structures
    let mut c_roots: Vec<CProcessTreeNode> = tree.roots
        .into_iter()
        .map(convert_tree_node)
        .collect();
    
    let result = Box::new(CProcessTree {
        roots: if c_roots.is_empty() { 
            std::ptr::null_mut() 
        } else { 
            c_roots.as_mut_ptr() 
        },
        roots_count: c_roots.len(),
        total_processes: tree.total_processes,
    });
    
    // Prevent vector from being deallocated
    std::mem::forget(c_roots);
    
    Box::into_raw(result)
}

#[no_mangle]
pub extern "C" fn free_process_tree_node(node: *mut CProcessTreeNode) {
    if node.is_null() {
        return;
    }
    
    unsafe {
        let node = &mut *node;
        
        // Free name
        if !node.name.is_null() {
            let _ = CString::from_raw(node.name);
        }
        
        // Free executable path
        if !node.executable_path.is_null() {
            let _ = CString::from_raw(node.executable_path);
        }
        
        // Free status
        if !node.status.is_null() {
            let _ = CString::from_raw(node.status);
        }
        
        // Free command arguments
        if !node.command.is_null() {
            let commands = Vec::from_raw_parts(node.command, node.command_count, node.command_count);
            for cmd in commands {
                if !cmd.is_null() {
                    let _ = CString::from_raw(cmd);
                }
            }
        }
        
        // Free children recursively
        if !node.children.is_null() {
            let children = Vec::from_raw_parts(node.children, node.children_count, node.children_count);
            for mut child in children {
                free_process_tree_node(&mut child as *mut CProcessTreeNode);
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn free_process_tree(tree: *mut CProcessTree) {
    if tree.is_null() {
        return;
    }
    
    unsafe {
        let tree = Box::from_raw(tree);
        
        // Free all root nodes
        if !tree.roots.is_null() {
            let roots = Vec::from_raw_parts(tree.roots, tree.roots_count, tree.roots_count);
            for mut root in roots {
                free_process_tree_node(&mut root as *mut CProcessTreeNode);
            }
        }
    }
}

// ============================================================================
// Advanced CPU Analysis FFI Exports (v0.4.6)
// ============================================================================

use crate::thermal_monitor::{ThermalMonitor, ThermalConfig};
use crate::cpu_history::{CpuHistoryStore, CpuHistoryConfig};
use once_cell::sync::OnceCell;
use std::time::Duration;

static THERMAL_MONITOR: OnceCell<Mutex<ThermalMonitor>> = OnceCell::new();
static CPU_HISTORY: OnceCell<Mutex<CpuHistoryStore>> = OnceCell::new();

// Thermal monitoring structures for FFI
#[repr(C)]
pub struct CThermalSensor {
    pub name: *mut c_char,
    pub location: *mut c_char,
    pub current_temperature: f32,
    pub max_temperature: f32,
    pub is_throttling: u8, // bool as u8
}

#[repr(C)]
pub struct CThermalData {
    pub sensors: *mut CThermalSensor,
    pub sensor_count: usize,
    pub cpu_temperature: f32,
    pub is_throttling: u8,
    pub hottest_temperature: f32,
}

// CPU History structures for FFI
#[repr(C)]
pub struct CCpuHistoryPoint {
    pub timestamp: u64,
    pub cpu_usage: f32,
    pub frequency_mhz: u64,
    pub temperature: f32,
}

#[repr(C)]
pub struct CCpuHistoryData {
    pub points: *mut CCpuHistoryPoint,
    pub point_count: usize,
    pub average_usage: f32,
    pub max_usage: f32,
    pub min_usage: f32,
}

// Initialize thermal monitoring
#[no_mangle]
pub extern "C" fn initialize_thermal_monitor() -> u8 {
    let config = ThermalConfig::default();
    match ThermalMonitor::new(config) {
        Ok(monitor) => {
            THERMAL_MONITOR.set(Mutex::new(monitor)).unwrap_or(());
            1 // success
        }
        Err(_) => 0 // failure
    }
}

// Get current thermal data
#[no_mangle]
pub extern "C" fn get_thermal_data() -> *mut CThermalData {
    let monitor = THERMAL_MONITOR.get_or_init(|| {
        let config = ThermalConfig::default();
        Mutex::new(ThermalMonitor::new(config).unwrap_or_else(|_| {
            // Return a dummy monitor if initialization fails
            ThermalMonitor::new(ThermalConfig {
                polling_interval_ms: 5000,
                temperature_threshold_celsius: 100.0,
                throttling_detection_enabled: false,
                sensor_blacklist: Vec::new(),
                alert_on_high_temperature: false,
                max_history_entries: 100,
            }).unwrap()
        }))
    });

    let mut monitor = monitor.lock().unwrap();
    let _ = monitor.update(); // Update sensor readings

    let sensors = monitor.get_sensors();
    let cpu_temp = monitor.get_cpu_temperature().unwrap_or(0.0);
    let is_throttling = monitor.is_throttling_active();
    let hottest = monitor.get_hottest_temperature().unwrap_or(0.0);

    // Convert to C structures
    let c_sensors: Vec<CThermalSensor> = sensors.iter().map(|sensor| {
        CThermalSensor {
            name: CString::new(sensor.name.clone()).unwrap().into_raw(),
            location: CString::new(format!("{:?}", sensor.location)).unwrap().into_raw(),
            current_temperature: sensor.current_temperature,
            max_temperature: sensor.max_temperature,
            is_throttling: if is_throttling { 1 } else { 0 },
        }
    }).collect();

    let thermal_data = Box::new(CThermalData {
        sensors: Box::into_raw(c_sensors.into_boxed_slice()) as *mut CThermalSensor,
        sensor_count: sensors.len(),
        cpu_temperature: cpu_temp,
        is_throttling: if is_throttling { 1 } else { 0 },
        hottest_temperature: hottest,
    });

    Box::into_raw(thermal_data)
}

// Free thermal data
#[no_mangle]
pub extern "C" fn free_thermal_data(data: *mut CThermalData) {
    if data.is_null() {
        return;
    }

    unsafe {
        let data = Box::from_raw(data);
        
        // Free sensor names and locations
        if !data.sensors.is_null() {
            let sensors = Vec::from_raw_parts(data.sensors, data.sensor_count, data.sensor_count);
            for sensor in sensors {
                if !sensor.name.is_null() {
                    let _ = CString::from_raw(sensor.name);
                }
                if !sensor.location.is_null() {
                    let _ = CString::from_raw(sensor.location);
                }
            }
        }
    }
}

// Initialize CPU history storage
#[no_mangle]
pub extern "C" fn initialize_cpu_history() -> u8 {
    let config = CpuHistoryConfig::default();
    match CpuHistoryStore::new(config) {
        Ok(store) => {
            CPU_HISTORY.set(Mutex::new(store)).unwrap_or(());
            1 // success
        }
        Err(_) => 0 // failure
    }
}

// Get CPU history for last N minutes
#[no_mangle]
pub extern "C" fn get_cpu_history(minutes: u32) -> *mut CCpuHistoryData {
    let history = CPU_HISTORY.get_or_init(|| {
        let config = CpuHistoryConfig::default();
        Mutex::new(CpuHistoryStore::new(config).unwrap())
    });

    let history = history.lock().unwrap();
    let duration = Duration::from_secs(minutes as u64 * 60);
    let recent_data = history.get_recent_data(duration);
    let stats = history.get_statistics(duration);

    // Convert to C structures
    let points: Vec<CCpuHistoryPoint> = recent_data.iter().map(|point| {
        CCpuHistoryPoint {
            timestamp: point.timestamp,
            cpu_usage: point.total_usage,
            frequency_mhz: point.frequency_mhz,
            temperature: point.temperature.unwrap_or(0.0),
        }
    }).collect();

    let history_data = Box::new(CCpuHistoryData {
        points: Box::into_raw(points.into_boxed_slice()) as *mut CCpuHistoryPoint,
        point_count: recent_data.len(),
        average_usage: stats.average_cpu_usage,
        max_usage: stats.max_cpu_usage,
        min_usage: stats.min_cpu_usage,
    });

    Box::into_raw(history_data)
}

// Free CPU history data
#[no_mangle]
pub extern "C" fn free_cpu_history(data: *mut CCpuHistoryData) {
    if data.is_null() {
        return;
    }

    unsafe {
        let data = Box::from_raw(data);
        
        // Free points array
        if !data.points.is_null() {
            let _ = Vec::from_raw_parts(data.points, data.point_count, data.point_count);
        }
    }
}

// Enable high-frequency CPU sampling
#[no_mangle]
pub extern "C" fn enable_high_frequency_sampling() -> u8 {
    if let Ok(mut analyzer) = CPU_ANALYZER.lock() {
        analyzer.enable_high_frequency_sampling();
        1 // success
    } else {
        0 // failure
    }
}

// Disable high-frequency CPU sampling
#[no_mangle]
pub extern "C" fn disable_high_frequency_sampling() -> u8 {
    if let Ok(mut analyzer) = CPU_ANALYZER.lock() {
        analyzer.disable_high_frequency_sampling();
        1 // success
    } else {
        0 // failure
    }
}