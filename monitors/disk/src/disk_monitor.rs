use sysinfo::Disks;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct DiskInfo {
    pub mount_point: String,
    pub name: String,
    pub file_system: String,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub used_bytes: u64,
    pub usage_percent: f32,
    pub is_removable: bool,
    pub disk_type: DiskType,
}

#[derive(Debug, Clone)]
pub enum DiskType {
    HDD,
    SSD,
    Network,
    Removable,
    Unknown,
}

impl DiskType {
    pub fn as_str(&self) -> &str {
        match self {
            DiskType::HDD => "HDD",
            DiskType::SSD => "SSD",
            DiskType::Network => "Network",
            DiskType::Removable => "Removable",
            DiskType::Unknown => "Unknown",
        }
    }
}

pub struct DiskMonitor {
    disks: Disks,
    disk_history: HashMap<String, Vec<u64>>, // Mount point -> usage history
}

impl DiskMonitor {
    pub fn new() -> Self {
        let disks = Disks::new_with_refreshed_list();
        
        Self {
            disks,
            disk_history: HashMap::new(),
        }
    }
    
    pub fn refresh(&mut self) {
        self.disks.refresh();
        
        // Update history for trend analysis
        for disk in self.disks.iter() {
            let mount_point = disk.mount_point().to_string_lossy().to_string();
            let used = disk.total_space() - disk.available_space();
            
            let history = self.disk_history.entry(mount_point).or_insert_with(Vec::new);
            history.push(used);
            
            // Keep only last 60 samples (1 minute at 1Hz refresh)
            if history.len() > 60 {
                history.remove(0);
            }
        }
    }
    
    pub fn get_all_disks(&self) -> Vec<DiskInfo> {
        self.disks
            .iter()
            .map(|disk| {
                let mount_point = disk.mount_point().to_string_lossy().to_string();
                let name = disk.name().to_string_lossy().to_string();
                let total = disk.total_space();
                let available = disk.available_space();
                let used = total - available;
                let usage_percent = if total > 0 {
                    (used as f32 / total as f32) * 100.0
                } else {
                    0.0
                };
                
                // Determine disk type based on mount point and file system
                let file_system_str = disk.file_system().to_string_lossy().to_string();
                let disk_type = self.determine_disk_type(&mount_point, file_system_str.as_bytes());
                let is_removable = disk.is_removable();
                
                DiskInfo {
                    mount_point,
                    name,
                    file_system: file_system_str,
                    total_bytes: total,
                    available_bytes: available,
                    used_bytes: used,
                    usage_percent,
                    is_removable,
                    disk_type,
                }
            })
            .collect()
    }
    
    pub fn get_primary_disk(&self) -> Option<DiskInfo> {
        // On macOS, the primary disk is usually mounted at "/"
        self.get_all_disks()
            .into_iter()
            .find(|disk| disk.mount_point == "/")
    }
    
    pub fn get_disk_by_mount_point(&self, mount_point: &str) -> Option<DiskInfo> {
        self.get_all_disks()
            .into_iter()
            .find(|disk| disk.mount_point == mount_point)
    }
    
    pub fn get_high_usage_disks(&self, threshold: f32) -> Vec<DiskInfo> {
        self.get_all_disks()
            .into_iter()
            .filter(|disk| disk.usage_percent >= threshold)
            .collect()
    }
    
    pub fn get_disk_growth_rate(&self, mount_point: &str) -> Option<f32> {
        // Calculate growth rate in MB/min
        if let Some(history) = self.disk_history.get(mount_point) {
            if history.len() >= 2 {
                let recent = history.last()?;
                let past = history.first()?;
                let time_span_seconds = history.len() as f32;
                let growth_bytes = *recent as f32 - *past as f32;
                let growth_mb_per_second = growth_bytes / 1024.0 / 1024.0 / time_span_seconds;
                return Some(growth_mb_per_second * 60.0); // Convert to MB/min
            }
        }
        None
    }
    
    fn determine_disk_type(&self, mount_point: &str, file_system: &[u8]) -> DiskType {
        let fs_str = String::from_utf8_lossy(file_system);
        
        // Check for network file systems
        if fs_str.contains("nfs") || fs_str.contains("smb") || fs_str.contains("afp") {
            return DiskType::Network;
        }
        
        // Check for removable media mount points
        if mount_point.contains("/Volumes/") && !mount_point.contains("Macintosh") {
            return DiskType::Removable;
        }
        
        // On macOS, we can try to determine SSD vs HDD
        // This is a simplified heuristic
        if mount_point == "/" || mount_point.starts_with("/System") {
            // System volumes on modern Macs are typically SSD
            return DiskType::SSD;
        }
        
        DiskType::Unknown
    }
    
    pub fn format_bytes(bytes: u64) -> String {
        const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB", "PB"];
        let mut size = bytes as f64;
        let mut unit_index = 0;
        
        while size >= 1024.0 && unit_index < UNITS.len() - 1 {
            size /= 1024.0;
            unit_index += 1;
        }
        
        if unit_index == 0 {
            format!("{} {}", size as u64, UNITS[unit_index])
        } else {
            format!("{:.1} {}", size, UNITS[unit_index])
        }
    }
}