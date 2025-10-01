use crate::disk_monitor::DiskMonitor;
use once_cell::sync::Lazy;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::Mutex;

static DISK_MONITOR: Lazy<Mutex<DiskMonitor>> = Lazy::new(|| {
    Mutex::new(DiskMonitor::new())
});

#[repr(C)]
pub struct CDiskInfo {
    pub mount_point: *mut c_char,
    pub name: *mut c_char,
    pub file_system: *mut c_char,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub used_bytes: u64,
    pub usage_percent: f32,
    pub is_removable: u8,  // bool as u8 for C compatibility
    pub disk_type: *mut c_char,
}

#[repr(C)]
pub struct CDiskList {
    pub disks: *mut CDiskInfo,
    pub count: usize,
}

#[no_mangle]
pub extern "C" fn disk_monitor_init() {
    let _ = &*DISK_MONITOR;
}

#[no_mangle]
pub extern "C" fn disk_monitor_refresh() {
    if let Ok(mut monitor) = DISK_MONITOR.lock() {
        monitor.refresh();
    }
}

#[no_mangle]
pub extern "C" fn get_all_disks() -> *mut CDiskList {
    let disks = match DISK_MONITOR.lock() {
        Ok(monitor) => monitor.get_all_disks(),
        Err(_) => return std::ptr::null_mut(),
    };
    
    let count = disks.len();
    if count == 0 {
        return Box::into_raw(Box::new(CDiskList {
            disks: std::ptr::null_mut(),
            count: 0,
        }));
    }
    
    let mut c_disks = Vec::with_capacity(count);
    
    for disk in disks {
        let mount_point = CString::new(disk.mount_point).unwrap_or_default();
        let name = CString::new(disk.name).unwrap_or_default();
        let file_system = CString::new(disk.file_system).unwrap_or_default();
        let disk_type = CString::new(disk.disk_type.as_str()).unwrap_or_default();
        
        c_disks.push(CDiskInfo {
            mount_point: mount_point.into_raw(),
            name: name.into_raw(),
            file_system: file_system.into_raw(),
            total_bytes: disk.total_bytes,
            available_bytes: disk.available_bytes,
            used_bytes: disk.used_bytes,
            usage_percent: disk.usage_percent,
            is_removable: if disk.is_removable { 1 } else { 0 },
            disk_type: disk_type.into_raw(),
        });
    }
    
    let mut c_disks = c_disks.into_boxed_slice();
    let disks_ptr = c_disks.as_mut_ptr();
    
    let list = Box::new(CDiskList {
        disks: disks_ptr,
        count,
    });
    
    std::mem::forget(c_disks);
    Box::into_raw(list)
}

#[no_mangle]
pub extern "C" fn get_primary_disk() -> *mut CDiskInfo {
    let disk = match DISK_MONITOR.lock() {
        Ok(monitor) => match monitor.get_primary_disk() {
            Some(d) => {
                eprintln!("[DISK FFI] Primary disk: {} available, {} total, {:.2}% used",
                    crate::disk_monitor::DiskMonitor::format_bytes(d.available_bytes),
                    crate::disk_monitor::DiskMonitor::format_bytes(d.total_bytes),
                    d.usage_percent);
                d
            },
            None => return std::ptr::null_mut(),
        },
        Err(_) => return std::ptr::null_mut(),
    };
    
    let mount_point = CString::new(disk.mount_point).unwrap_or_default();
    let name = CString::new(disk.name).unwrap_or_default();
    let file_system = CString::new(disk.file_system).unwrap_or_default();
    let disk_type = CString::new(disk.disk_type.as_str()).unwrap_or_default();
    
    Box::into_raw(Box::new(CDiskInfo {
        mount_point: mount_point.into_raw(),
        name: name.into_raw(),
        file_system: file_system.into_raw(),
        total_bytes: disk.total_bytes,
        available_bytes: disk.available_bytes,
        used_bytes: disk.used_bytes,
        usage_percent: disk.usage_percent,
        is_removable: if disk.is_removable { 1 } else { 0 },
        disk_type: disk_type.into_raw(),
    }))
}

#[no_mangle]
pub extern "C" fn get_disk_by_mount_point(mount_point_str: *const c_char) -> *mut CDiskInfo {
    if mount_point_str.is_null() {
        return std::ptr::null_mut();
    }
    
    let mount_point = unsafe {
        match std::ffi::CStr::from_ptr(mount_point_str).to_str() {
            Ok(s) => s,
            Err(_) => return std::ptr::null_mut(),
        }
    };
    
    let disk = match DISK_MONITOR.lock() {
        Ok(monitor) => match monitor.get_disk_by_mount_point(mount_point) {
            Some(d) => d,
            None => return std::ptr::null_mut(),
        },
        Err(_) => return std::ptr::null_mut(),
    };
    
    let mount_point_c = CString::new(disk.mount_point).unwrap_or_default();
    let name = CString::new(disk.name).unwrap_or_default();
    let file_system = CString::new(disk.file_system).unwrap_or_default();
    let disk_type = CString::new(disk.disk_type.as_str()).unwrap_or_default();
    
    Box::into_raw(Box::new(CDiskInfo {
        mount_point: mount_point_c.into_raw(),
        name: name.into_raw(),
        file_system: file_system.into_raw(),
        total_bytes: disk.total_bytes,
        available_bytes: disk.available_bytes,
        used_bytes: disk.used_bytes,
        usage_percent: disk.usage_percent,
        is_removable: if disk.is_removable { 1 } else { 0 },
        disk_type: disk_type.into_raw(),
    }))
}

#[no_mangle]
pub extern "C" fn get_high_usage_disks(threshold: f32) -> *mut CDiskList {
    let disks = match DISK_MONITOR.lock() {
        Ok(monitor) => monitor.get_high_usage_disks(threshold),
        Err(_) => return std::ptr::null_mut(),
    };
    
    let count = disks.len();
    if count == 0 {
        return Box::into_raw(Box::new(CDiskList {
            disks: std::ptr::null_mut(),
            count: 0,
        }));
    }
    
    let mut c_disks = Vec::with_capacity(count);
    
    for disk in disks {
        let mount_point = CString::new(disk.mount_point).unwrap_or_default();
        let name = CString::new(disk.name).unwrap_or_default();
        let file_system = CString::new(disk.file_system).unwrap_or_default();
        let disk_type = CString::new(disk.disk_type.as_str()).unwrap_or_default();
        
        c_disks.push(CDiskInfo {
            mount_point: mount_point.into_raw(),
            name: name.into_raw(),
            file_system: file_system.into_raw(),
            total_bytes: disk.total_bytes,
            available_bytes: disk.available_bytes,
            used_bytes: disk.used_bytes,
            usage_percent: disk.usage_percent,
            is_removable: if disk.is_removable { 1 } else { 0 },
            disk_type: disk_type.into_raw(),
        });
    }
    
    let mut c_disks = c_disks.into_boxed_slice();
    let disks_ptr = c_disks.as_mut_ptr();
    
    let list = Box::new(CDiskList {
        disks: disks_ptr,
        count,
    });
    
    std::mem::forget(c_disks);
    Box::into_raw(list)
}

#[no_mangle]
pub extern "C" fn get_disk_growth_rate(mount_point_str: *const c_char) -> f32 {
    if mount_point_str.is_null() {
        return 0.0;
    }
    
    let mount_point = unsafe {
        match std::ffi::CStr::from_ptr(mount_point_str).to_str() {
            Ok(s) => s,
            Err(_) => return 0.0,
        }
    };
    
    match DISK_MONITOR.lock() {
        Ok(monitor) => monitor.get_disk_growth_rate(mount_point).unwrap_or(0.0),
        Err(_) => 0.0,
    }
}

#[no_mangle]
pub extern "C" fn format_bytes(bytes: u64) -> *mut c_char {
    let formatted = DiskMonitor::format_bytes(bytes);
    CString::new(formatted).unwrap_or_default().into_raw()
}

#[no_mangle]
pub extern "C" fn free_disk_info(info: *mut CDiskInfo) {
    if info.is_null() {
        return;
    }
    
    unsafe {
        let info = Box::from_raw(info);
        
        if !info.mount_point.is_null() {
            let _ = CString::from_raw(info.mount_point);
        }
        if !info.name.is_null() {
            let _ = CString::from_raw(info.name);
        }
        if !info.file_system.is_null() {
            let _ = CString::from_raw(info.file_system);
        }
        if !info.disk_type.is_null() {
            let _ = CString::from_raw(info.disk_type);
        }
    }
}

#[no_mangle]
pub extern "C" fn free_disk_list(list: *mut CDiskList) {
    if list.is_null() {
        return;
    }
    
    unsafe {
        let list = Box::from_raw(list);
        if !list.disks.is_null() && list.count > 0 {
            let disks = std::slice::from_raw_parts_mut(list.disks, list.count);
            for disk in disks.iter() {
                if !disk.mount_point.is_null() {
                    let _ = CString::from_raw(disk.mount_point);
                }
                if !disk.name.is_null() {
                    let _ = CString::from_raw(disk.name);
                }
                if !disk.file_system.is_null() {
                    let _ = CString::from_raw(disk.file_system);
                }
                if !disk.disk_type.is_null() {
                    let _ = CString::from_raw(disk.disk_type);
                }
            }
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(list.disks, list.count));
        }
    }
}