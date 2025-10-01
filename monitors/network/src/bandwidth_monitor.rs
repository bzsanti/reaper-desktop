use std::process::Command;
use std::collections::HashMap;
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct BandwidthStats {
    pub current_upload_bps: u64,
    pub current_download_bps: u64,
    pub peak_upload_bps: u64,
    pub peak_download_bps: u64,
    pub average_upload_bps: u64,
    pub average_download_bps: u64,
}

#[derive(Debug, Clone)]
pub struct InterfaceStats {
    pub name: String,
    pub is_active: bool,
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub packets_sent: u64,
    pub packets_received: u64,
    pub errors_in: u64,
    pub errors_out: u64,
    pub drops_in: u64,
    pub drops_out: u64,
}

#[derive(Debug)]
struct InterfaceSnapshot {
    bytes_sent: u64,
    bytes_received: u64,
    timestamp: Instant,
}

pub struct BandwidthMonitor {
    interface_snapshots: HashMap<String, InterfaceSnapshot>,
    process_bandwidth: HashMap<u32, (u64, u64)>, // pid -> (upload, download)
    current_stats: BandwidthStats,
    peak_upload: u64,
    peak_download: u64,
    sample_count: u64,
    total_upload: u64,
    total_download: u64,
}

impl BandwidthMonitor {
    pub fn new() -> Self {
        Self {
            interface_snapshots: HashMap::new(),
            process_bandwidth: HashMap::new(),
            current_stats: BandwidthStats {
                current_upload_bps: 0,
                current_download_bps: 0,
                peak_upload_bps: 0,
                peak_download_bps: 0,
                average_upload_bps: 0,
                average_download_bps: 0,
            },
            peak_upload: 0,
            peak_download: 0,
            sample_count: 0,
            total_upload: 0,
            total_download: 0,
        }
    }
    
    pub fn get_current_bandwidth(&mut self) -> BandwidthStats {
        self.refresh();
        self.current_stats.clone()
    }
    
    pub fn get_interface_stats(&self) -> Vec<InterfaceStats> {
        let mut interfaces = Vec::new();
        
        // Run ifconfig to get interface statistics
        if let Ok(output) = Command::new("ifconfig").arg("-a").output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            interfaces = self.parse_ifconfig(&stdout);
        }
        
        // Alternative: Use netstat -i for interface statistics
        if interfaces.is_empty() {
            if let Ok(output) = Command::new("netstat").args(&["-i", "-b"]).output() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                interfaces = self.parse_netstat_interfaces(&stdout);
            }
        }
        
        interfaces
    }
    
    pub fn get_process_bandwidth(&self, pid: u32) -> Option<(u64, u64)> {
        self.process_bandwidth.get(&pid).copied()
    }
    
    pub fn refresh(&mut self) {
        let interfaces = self.get_interface_stats();
        let now = Instant::now();
        
        // Calculate bandwidth for each interface
        let mut total_upload_bps = 0u64;
        let mut total_download_bps = 0u64;
        
        for interface in &interfaces {
            if !interface.is_active {
                continue;
            }
            
            if let Some(snapshot) = self.interface_snapshots.get(&interface.name) {
                let time_diff = now.duration_since(snapshot.timestamp).as_secs_f64();
                
                if time_diff > 0.0 {
                    let bytes_sent_diff = interface.bytes_sent.saturating_sub(snapshot.bytes_sent);
                    let bytes_received_diff = interface.bytes_received.saturating_sub(snapshot.bytes_received);
                    
                    let upload_bps = (bytes_sent_diff as f64 / time_diff) as u64;
                    let download_bps = (bytes_received_diff as f64 / time_diff) as u64;
                    
                    total_upload_bps += upload_bps;
                    total_download_bps += download_bps;
                }
            }
            
            // Update snapshot
            self.interface_snapshots.insert(
                interface.name.clone(),
                InterfaceSnapshot {
                    bytes_sent: interface.bytes_sent,
                    bytes_received: interface.bytes_received,
                    timestamp: now,
                },
            );
        }
        
        // Update current stats
        self.current_stats.current_upload_bps = total_upload_bps;
        self.current_stats.current_download_bps = total_download_bps;
        
        // Update peaks
        if total_upload_bps > self.peak_upload {
            self.peak_upload = total_upload_bps;
            self.current_stats.peak_upload_bps = total_upload_bps;
        }
        
        if total_download_bps > self.peak_download {
            self.peak_download = total_download_bps;
            self.current_stats.peak_download_bps = total_download_bps;
        }
        
        // Update averages
        self.sample_count += 1;
        self.total_upload += total_upload_bps;
        self.total_download += total_download_bps;
        
        if self.sample_count > 0 {
            self.current_stats.average_upload_bps = self.total_upload / self.sample_count;
            self.current_stats.average_download_bps = self.total_download / self.sample_count;
        }
        
        // Try to get per-process bandwidth using nettop (macOS specific)
        self.update_process_bandwidth();
    }
    
    fn parse_ifconfig(&self, output: &str) -> Vec<InterfaceStats> {
        let mut interfaces = Vec::new();
        let mut current_interface: Option<InterfaceStats> = None;
        
        for line in output.lines() {
            // Check if this is a new interface line (starts at column 0)
            if !line.starts_with('\t') && !line.starts_with(' ') && line.contains(':') {
                // Save previous interface if exists
                if let Some(interface) = current_interface.take() {
                    interfaces.push(interface);
                }
                
                // Parse interface name
                if let Some(colon_pos) = line.find(':') {
                    let name = line[..colon_pos].to_string();
                    let is_active = line.contains("UP") && line.contains("RUNNING");
                    
                    current_interface = Some(InterfaceStats {
                        name,
                        is_active,
                        bytes_sent: 0,
                        bytes_received: 0,
                        packets_sent: 0,
                        packets_received: 0,
                        errors_in: 0,
                        errors_out: 0,
                        drops_in: 0,
                        drops_out: 0,
                    });
                }
            } else if current_interface.is_some() {
                // Parse interface statistics
                // Look for lines like: "RX packets:12345 errors:0 dropped:0"
                if line.contains("packets") || line.contains("bytes") {
                    // This is highly platform-specific, simplified for macOS
                    // Real implementation would need more robust parsing
                }
            }
        }
        
        // Don't forget the last interface
        if let Some(interface) = current_interface {
            interfaces.push(interface);
        }
        
        interfaces
    }
    
    fn parse_netstat_interfaces(&self, output: &str) -> Vec<InterfaceStats> {
        let mut interfaces = Vec::new();
        let lines: Vec<&str> = output.lines().collect();
        
        // Skip header lines
        for line in lines.iter().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            
            if parts.len() >= 11 {
                let name = parts[0].to_string();
                
                // Parse statistics (positions may vary)
                let packets_in = parts[4].parse::<u64>().unwrap_or(0);
                let errs_in = parts[5].parse::<u64>().unwrap_or(0);
                let bytes_in = parts[6].parse::<u64>().unwrap_or(0);
                let packets_out = parts[7].parse::<u64>().unwrap_or(0);
                let errs_out = parts[8].parse::<u64>().unwrap_or(0);
                let bytes_out = parts[9].parse::<u64>().unwrap_or(0);
                
                interfaces.push(InterfaceStats {
                    name,
                    is_active: bytes_in > 0 || bytes_out > 0,
                    bytes_sent: bytes_out,
                    bytes_received: bytes_in,
                    packets_sent: packets_out,
                    packets_received: packets_in,
                    errors_in: errs_in,
                    errors_out: errs_out,
                    drops_in: 0,
                    drops_out: 0,
                });
            }
        }
        
        interfaces
    }
    
    fn update_process_bandwidth(&mut self) {
        // Try to use nettop to get per-process bandwidth (macOS specific)
        // Note: nettop requires special entitlements or root
        // This is a simplified implementation
        
        if let Ok(output) = Command::new("nettop")
            .args(&["-P", "-l", "1", "-J", "bytes_in,bytes_out"])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout);
            self.parse_nettop(&stdout);
        }
    }
    
    fn parse_nettop(&mut self, _output: &str) {
        // Parse nettop output to get per-process bandwidth
        // This is platform-specific and requires proper parsing
        // For now, we'll leave this as a stub
    }
}

impl Default for BandwidthStats {
    fn default() -> Self {
        Self {
            current_upload_bps: 0,
            current_download_bps: 0,
            peak_upload_bps: 0,
            peak_download_bps: 0,
            average_upload_bps: 0,
            average_download_bps: 0,
        }
    }
}