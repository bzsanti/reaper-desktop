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
}

impl ProcessMonitor {
    pub fn new() -> Self {
        let mut system = System::new_all();
        system.refresh_all();
        
        ProcessMonitor {
            system,
            process_cache: HashMap::new(),
        }
    }
    
    pub fn refresh(&mut self) {
        self.system.refresh_all();
        self.update_process_cache();
    }
    
    fn update_process_cache(&mut self) {
        self.process_cache.clear();
        
        for (pid, process) in self.system.processes() {
            let process_info = ProcessInfo {
                pid: pid.as_u32(),
                name: process.name().to_string(),
                cpu_usage: process.cpu_usage(),
                memory_mb: process.memory() as f64 / 1024.0,
                status: format!("{:?}", process.status()),
                parent_pid: process.parent().map(|p| p.as_u32()),
                thread_count: 1,
                run_time: process.run_time(),
                user_time: 0.0,
                system_time: 0.0,
            };
            
            self.process_cache.insert(pid.as_u32(), process_info);
        }
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