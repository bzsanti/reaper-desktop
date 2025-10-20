use crate::disk_monitor::DiskMonitor;
use crate::file_analyzer::{FileAnalyzer, DirectoryAnalysis, DuplicateGroup, FileEntry, FileCategory};
use once_cell::sync::Lazy;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::Mutex;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

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

// ============================================================================
// File Analyzer FFI
// ============================================================================

#[repr(C)]
pub struct CFileEntry {
    pub path: *mut c_char,
    pub size_bytes: u64,
    pub is_dir: u8,
    pub modified_timestamp: u64,
    pub file_type: *mut c_char,
}

#[repr(C)]
pub struct CFileEntryList {
    pub entries: *mut CFileEntry,
    pub count: usize,
}

#[repr(C)]
pub struct CFileCategoryStats {
    pub category: u8, // FileCategory as u8
    pub total_size: u64,
    pub file_count: usize,
}

#[repr(C)]
pub struct CCategoryStatsList {
    pub stats: *mut CFileCategoryStats,
    pub count: usize,
}

#[repr(C)]
pub struct CDirectoryAnalysis {
    pub path: *mut c_char,
    pub total_size: u64,
    pub file_count: usize,
    pub dir_count: usize,
    pub largest_files: *mut CFileEntryList,
    pub category_stats: *mut CCategoryStatsList,
}

#[repr(C)]
pub struct CDuplicateGroup {
    pub hash: *mut c_char,
    pub size_bytes: u64,
    pub files: *mut *mut c_char,
    pub file_count: usize,
    pub total_wasted_space: u64,
}

#[repr(C)]
pub struct CDuplicateGroupList {
    pub groups: *mut CDuplicateGroup,
    pub count: usize,
}

// Type alias for progress callback from Swift
pub type CProgressCallback = extern "C" fn(files_processed: usize, bytes_processed: u64);

// Global state for current analysis operation
static CANCEL_FLAG: Lazy<Mutex<Arc<AtomicBool>>> = Lazy::new(|| {
    Mutex::new(Arc::new(AtomicBool::new(false)))
});

/// Convert FileCategory to u8 for C FFI
fn category_to_u8(category: &FileCategory) -> u8 {
    match category {
        FileCategory::Documents => 0,
        FileCategory::Media => 1,
        FileCategory::Code => 2,
        FileCategory::Archives => 3,
        FileCategory::Applications => 4,
        FileCategory::SystemFiles => 5,
        FileCategory::Other => 6,
    }
}

/// Analyze a directory and find largest files
#[no_mangle]
pub extern "C" fn analyze_directory(
    path_str: *const c_char,
    top_n: usize,
    progress_callback: Option<CProgressCallback>,
) -> *mut CDirectoryAnalysis {
    if path_str.is_null() {
        return std::ptr::null_mut();
    }

    let path = unsafe {
        match std::ffi::CStr::from_ptr(path_str).to_str() {
            Ok(s) => s,
            Err(_) => return std::ptr::null_mut(),
        }
    };

    // Reset cancel flag
    if let Ok(cancel) = CANCEL_FLAG.lock() {
        cancel.store(false, Ordering::Relaxed);
    }

    let cancel_flag = CANCEL_FLAG.lock().unwrap().clone();

    let analyzer = FileAnalyzer::new()
        .enable_default_cache()
        .with_max_depth(15);

    let progress_cb = progress_callback.map(|cb| {
        Arc::new(move |files: usize, bytes: u64| {
            cb(files, bytes);
        }) as Arc<dyn Fn(usize, u64) + Send + Sync>
    });

    let analysis = match analyzer.analyze_directory_with_progress(
        path,
        top_n,
        progress_cb,
        cancel_flag,
    ) {
        Ok(a) => a,
        Err(_) => return std::ptr::null_mut(),
    };

    convert_directory_analysis_to_c(analysis)
}

/// Cancel the current analysis operation
#[no_mangle]
pub extern "C" fn cancel_analysis() {
    if let Ok(cancel) = CANCEL_FLAG.lock() {
        cancel.store(true, Ordering::Relaxed);
    }
}

/// Find duplicate files in a directory
#[no_mangle]
pub extern "C" fn find_duplicates(
    path_str: *const c_char,
    min_size: u64,
    progress_callback: Option<CProgressCallback>,
) -> *mut CDuplicateGroupList {
    if path_str.is_null() {
        return std::ptr::null_mut();
    }

    let path = unsafe {
        match std::ffi::CStr::from_ptr(path_str).to_str() {
            Ok(s) => s,
            Err(_) => return std::ptr::null_mut(),
        }
    };

    // Reset cancel flag
    if let Ok(cancel) = CANCEL_FLAG.lock() {
        cancel.store(false, Ordering::Relaxed);
    }

    let cancel_flag = CANCEL_FLAG.lock().unwrap().clone();

    let analyzer = FileAnalyzer::new()
        .enable_default_cache()
        .with_min_file_size(min_size)
        .with_max_depth(15);

    let progress_cb = progress_callback.map(|cb| {
        Arc::new(move |files: usize, bytes: u64| {
            cb(files, bytes);
        }) as Arc<dyn Fn(usize, u64) + Send + Sync>
    });

    let duplicates = match analyzer.find_duplicates_with_progress(
        path,
        progress_cb,
        cancel_flag,
    ) {
        Ok(d) => d,
        Err(_) => return std::ptr::null_mut(),
    };

    convert_duplicate_groups_to_c(duplicates)
}

fn convert_directory_analysis_to_c(analysis: DirectoryAnalysis) -> *mut CDirectoryAnalysis {
    let path_c = CString::new(analysis.path.to_string_lossy().as_ref()).unwrap_or_default();

    // Convert largest files
    let largest_files = convert_file_entries_to_c(&analysis.largest_files);

    // Convert category stats
    let category_stats = convert_category_stats_to_c(&analysis.category_stats);

    Box::into_raw(Box::new(CDirectoryAnalysis {
        path: path_c.into_raw(),
        total_size: analysis.total_size,
        file_count: analysis.file_count,
        dir_count: analysis.dir_count,
        largest_files,
        category_stats,
    }))
}

fn convert_file_entries_to_c(entries: &[FileEntry]) -> *mut CFileEntryList {
    let count = entries.len();
    if count == 0 {
        return Box::into_raw(Box::new(CFileEntryList {
            entries: std::ptr::null_mut(),
            count: 0,
        }));
    }

    let c_entries: Vec<CFileEntry> = entries
        .iter()
        .map(|entry| {
            let path = CString::new(entry.path.to_string_lossy().as_ref()).unwrap_or_default();
            let file_type = CString::new(entry.file_type.as_str()).unwrap_or_default();
            let timestamp = entry
                .modified
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();

            CFileEntry {
                path: path.into_raw(),
                size_bytes: entry.size_bytes,
                is_dir: if entry.is_dir { 1 } else { 0 },
                modified_timestamp: timestamp,
                file_type: file_type.into_raw(),
            }
        })
        .collect();

    let mut boxed = c_entries.into_boxed_slice();
    let ptr = boxed.as_mut_ptr();

    let list = Box::new(CFileEntryList {
        entries: ptr,
        count,
    });

    std::mem::forget(boxed);
    Box::into_raw(list)
}

fn convert_category_stats_to_c(
    stats: &std::collections::HashMap<FileCategory, crate::file_analyzer::FileCategoryStats>,
) -> *mut CCategoryStatsList {
    let count = stats.len();
    if count == 0 {
        return Box::into_raw(Box::new(CCategoryStatsList {
            stats: std::ptr::null_mut(),
            count: 0,
        }));
    }

    let c_stats: Vec<CFileCategoryStats> = stats
        .values()
        .map(|s| CFileCategoryStats {
            category: category_to_u8(&s.category),
            total_size: s.total_size,
            file_count: s.file_count,
        })
        .collect();

    let mut boxed = c_stats.into_boxed_slice();
    let ptr = boxed.as_mut_ptr();

    let list = Box::new(CCategoryStatsList {
        stats: ptr,
        count,
    });

    std::mem::forget(boxed);
    Box::into_raw(list)
}

fn convert_duplicate_groups_to_c(groups: Vec<DuplicateGroup>) -> *mut CDuplicateGroupList {
    let count = groups.len();
    if count == 0 {
        return Box::into_raw(Box::new(CDuplicateGroupList {
            groups: std::ptr::null_mut(),
            count: 0,
        }));
    }

    let c_groups: Vec<CDuplicateGroup> = groups
        .into_iter()
        .map(|group| {
            let hash = CString::new(group.hash).unwrap_or_default();
            let file_count = group.files.len();

            let file_paths: Vec<*mut c_char> = group
                .files
                .iter()
                .map(|p| {
                    CString::new(p.to_string_lossy().as_ref())
                        .unwrap_or_default()
                        .into_raw()
                })
                .collect();

            let mut boxed_paths = file_paths.into_boxed_slice();
            let paths_ptr = boxed_paths.as_mut_ptr();
            std::mem::forget(boxed_paths);

            CDuplicateGroup {
                hash: hash.into_raw(),
                size_bytes: group.size_bytes,
                files: paths_ptr,
                file_count,
                total_wasted_space: group.total_wasted_space,
            }
        })
        .collect();

    let mut boxed = c_groups.into_boxed_slice();
    let ptr = boxed.as_mut_ptr();

    let list = Box::new(CDuplicateGroupList {
        groups: ptr,
        count,
    });

    std::mem::forget(boxed);
    Box::into_raw(list)
}

// Free functions

#[no_mangle]
pub extern "C" fn free_directory_analysis(analysis: *mut CDirectoryAnalysis) {
    if analysis.is_null() {
        return;
    }

    unsafe {
        let analysis = Box::from_raw(analysis);

        if !analysis.path.is_null() {
            let _ = CString::from_raw(analysis.path);
        }

        if !analysis.largest_files.is_null() {
            free_file_entry_list(analysis.largest_files);
        }

        if !analysis.category_stats.is_null() {
            free_category_stats_list(analysis.category_stats);
        }
    }
}

#[no_mangle]
pub extern "C" fn free_file_entry_list(list: *mut CFileEntryList) {
    if list.is_null() {
        return;
    }

    unsafe {
        let list = Box::from_raw(list);
        if !list.entries.is_null() && list.count > 0 {
            let entries = std::slice::from_raw_parts_mut(list.entries, list.count);
            for entry in entries.iter() {
                if !entry.path.is_null() {
                    let _ = CString::from_raw(entry.path);
                }
                if !entry.file_type.is_null() {
                    let _ = CString::from_raw(entry.file_type);
                }
            }
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(list.entries, list.count));
        }
    }
}

#[no_mangle]
pub extern "C" fn free_category_stats_list(list: *mut CCategoryStatsList) {
    if list.is_null() {
        return;
    }

    unsafe {
        let list = Box::from_raw(list);
        if !list.stats.is_null() && list.count > 0 {
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(list.stats, list.count));
        }
    }
}

#[no_mangle]
pub extern "C" fn free_duplicate_group_list(list: *mut CDuplicateGroupList) {
    if list.is_null() {
        return;
    }

    unsafe {
        let list = Box::from_raw(list);
        if !list.groups.is_null() && list.count > 0 {
            let groups = std::slice::from_raw_parts_mut(list.groups, list.count);
            for group in groups.iter() {
                if !group.hash.is_null() {
                    let _ = CString::from_raw(group.hash);
                }
                if !group.files.is_null() && group.file_count > 0 {
                    let files = std::slice::from_raw_parts_mut(group.files, group.file_count);
                    for file_path in files.iter() {
                        if !file_path.is_null() {
                            let _ = CString::from_raw(*file_path);
                        }
                    }
                    let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                        group.files,
                        group.file_count,
                    ));
                }
            }
            let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(list.groups, list.count));
        }
    }
}