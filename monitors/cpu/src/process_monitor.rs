use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use sysinfo::{Pid, System, ProcessStatus};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[repr(C)]
pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
    pub cpu_usage: f32,
    pub memory_mb: f64,
    pub status: String,
    pub parent_pid: Option<u32>,
    pub thread_count: usize,
    pub run_time: u64,
    pub user_time: f32,
    pub system_time: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessState {
    pub is_uninterruptible: bool,
    pub is_zombie: bool,
    pub is_idle: bool,
    pub is_running: bool,
    pub context_switches: u64,
}

pub struct ProcessMonitor {
    system: System,
    process_cache: HashMap<u32, ProcessInfo>,
    last_full_refresh: std::time::Instant,
    refresh_counter: u32,
}

impl ProcessMonitor {
    pub fn new() -> Self {
        let mut system = System::new();
        // Only refresh CPU and memory initially, not all processes
        system.refresh_cpu();
        system.refresh_memory();
        system.refresh_processes();
        
        ProcessMonitor {
            system,
            process_cache: HashMap::with_capacity(200), // Pre-allocate for typical process count
            last_full_refresh: std::time::Instant::now(),
            refresh_counter: 0,
        }
    }
    
    pub fn refresh(&mut self) {
        self.refresh_counter += 1;
        
        // Full refresh every 30 cycles or every 30 seconds (reduced frequency)
        let needs_full_refresh = self.refresh_counter % 30 == 0 
            || self.last_full_refresh.elapsed().as_secs() > 30;
        
        if needs_full_refresh {
            self.system.refresh_processes();
            self.last_full_refresh = std::time::Instant::now();
        } else {
            // Ultra-lightweight refresh - only CPU for existing processes
            self.system.refresh_processes_specifics(
                sysinfo::ProcessRefreshKind::new()
                    .with_cpu()
                    // Skip memory updates unless necessary
            );
        }
        
        self.system.refresh_cpu();
        self.update_process_cache_optimized();
    }
    
    fn update_process_cache_optimized(&mut self) {
        // Only update processes with significant changes
        let mut seen_pids = std::collections::HashSet::with_capacity(self.process_cache.len());
        
        for (pid, process) in self.system.processes() {
            let pid_u32 = pid.as_u32();
            seen_pids.insert(pid_u32);
            
            let new_cpu = process.cpu_usage();
            
            // Check if update is needed (CPU changed by more than 1%)
            if let Some(existing) = self.process_cache.get_mut(&pid_u32) {
                let cpu_delta = (existing.cpu_usage - new_cpu).abs();
                if cpu_delta > 1.0 {
                    // Significant change, update
                    existing.cpu_usage = new_cpu;
                    existing.memory_mb = process.memory() as f64 / 1024.0;
                    existing.status = format!("{:?}", process.status());
                    existing.run_time = process.run_time();
                }
                // Otherwise skip update to save processing
            } else {
                // New process, add it
                let process_info = ProcessInfo {
                    pid: pid_u32,
                    name: process.name().to_string(),
                    cpu_usage: new_cpu,
                    memory_mb: process.memory() as f64 / 1024.0,
                    status: format!("{:?}", process.status()),
                    parent_pid: process.parent().map(|p| p.as_u32()),
                    thread_count: 1,
                    run_time: process.run_time(),
                    user_time: 0.0,
                    system_time: 0.0,
                };
                self.process_cache.insert(pid_u32, process_info);
            }
        }
        
        // Remove dead processes
        self.process_cache.retain(|pid, _| seen_pids.contains(pid));
    }
    
    
    pub fn get_all_processes(&self) -> Vec<ProcessInfo> {
        self.process_cache.values().cloned().collect()
    }
    
    pub fn get_process(&self, pid: u32) -> Option<ProcessInfo> {
        self.process_cache.get(&pid).cloned()
    }
    
    pub fn get_high_cpu_processes(&self, threshold: f32) -> Vec<ProcessInfo> {
        self.process_cache
            .values()
            .filter(|p| p.cpu_usage > threshold)
            .cloned()
            .collect()
    }
    
    pub fn analyze_process_state(&self, pid: u32) -> Option<ProcessState> {
        let process = self.system.process(Pid::from(pid as usize))?;
        
        let status = process.status();
        let state = ProcessState {
            is_uninterruptible: matches!(status, ProcessStatus::UninterruptibleDiskSleep),
            is_zombie: matches!(status, ProcessStatus::Zombie),
            is_idle: matches!(status, ProcessStatus::Idle),
            is_running: matches!(status, ProcessStatus::Run),
            context_switches: 0,
        };
        
        Some(state)
    }
    
    pub fn get_unkillable_processes(&self) -> Vec<ProcessInfo> {
        self.process_cache
            .values()
            .filter(|p| {
                if let Some(state) = self.analyze_process_state(p.pid) {
                    state.is_uninterruptible || state.is_zombie
                } else {
                    false
                }
            })
            .cloned()
            .collect()
    }
}