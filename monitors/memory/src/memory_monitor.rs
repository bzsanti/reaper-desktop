use sysinfo::System;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct MemoryInfo {
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
    pub memory_pressure: MemoryPressureLevel,
}

#[derive(Debug, Clone)]
pub enum MemoryPressureLevel {
    Low,      // < 50% usage
    Normal,   // 50-75% usage  
    High,     // 75-90% usage
    Critical, // > 90% usage
}

impl MemoryPressureLevel {
    pub fn from_usage_percent(percent: f32) -> Self {
        match percent {
            p if p < 50.0 => Self::Low,
            p if p < 75.0 => Self::Normal,
            p if p < 90.0 => Self::High,
            _ => Self::Critical,
        }
    }
    
    pub fn as_str(&self) -> &str {
        match self {
            Self::Low => "Low",
            Self::Normal => "Normal",
            Self::High => "High",
            Self::Critical => "Critical",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ProcessMemoryInfo {
    pub pid: u32,
    pub name: String,
    pub memory_bytes: u64,
    pub virtual_memory_bytes: u64,
    pub memory_percent: f32,
    pub is_growing: bool,  // Track if memory is increasing
    pub growth_rate_mb_per_min: f32,
}

pub struct MemoryMonitor {
    system: System,
    process_memory_history: HashMap<u32, Vec<u64>>,  // Track memory over time
    last_update: std::time::Instant,
}

impl MemoryMonitor {
    pub fn new() -> Self {
        let mut system = System::new_all();
        system.refresh_all();
        
        Self {
            system,
            process_memory_history: HashMap::new(),
            last_update: std::time::Instant::now(),
        }
    }
    
    pub fn refresh(&mut self) {
        self.system.refresh_memory();
        self.system.refresh_processes();
        self.update_memory_history();
        self.last_update = std::time::Instant::now();
    }
    
    fn update_memory_history(&mut self) {
        // Track memory usage for each process
        for (pid, process) in self.system.processes() {
            let memory = process.memory();
            let pid_u32 = pid.as_u32();
            
            let history = self.process_memory_history
                .entry(pid_u32)
                .or_insert_with(Vec::new);
            
            history.push(memory);
            
            // Keep only last 60 samples (1 minute at 1Hz)
            if history.len() > 60 {
                history.remove(0);
            }
        }
        
        // Clean up history for dead processes
        let active_pids: Vec<u32> = self.system.processes()
            .keys()
            .map(|pid| pid.as_u32())
            .collect();
        
        self.process_memory_history.retain(|pid, _| active_pids.contains(pid));
    }
    
    pub fn get_memory_info(&self) -> MemoryInfo {
        let total = self.system.total_memory() * 1024;  // Convert KB to bytes
        let used = self.system.used_memory() * 1024;
        let available = self.system.available_memory() * 1024;
        let free = self.system.free_memory() * 1024;
        
        let swap_total = self.system.total_swap() * 1024;
        let swap_used = self.system.used_swap() * 1024;
        let swap_free = self.system.free_swap() * 1024;
        
        // Note: macOS doesn't provide cached/buffer separately through sysinfo
        // These would need platform-specific implementations
        let cached = 0;
        let buffer = 0;
        
        let usage_percent = if total > 0 {
            (used as f32 / total as f32) * 100.0
        } else {
            0.0
        };
        
        let swap_usage_percent = if swap_total > 0 {
            (swap_used as f32 / swap_total as f32) * 100.0
        } else {
            0.0
        };
        
        MemoryInfo {
            total_bytes: total,
            used_bytes: used,
            available_bytes: available,
            free_bytes: free,
            swap_total_bytes: swap_total,
            swap_used_bytes: swap_used,
            swap_free_bytes: swap_free,
            cached_bytes: cached,
            buffer_bytes: buffer,
            usage_percent,
            swap_usage_percent,
            memory_pressure: MemoryPressureLevel::from_usage_percent(usage_percent),
        }
    }
    
    pub fn get_process_memory_info(&self) -> Vec<ProcessMemoryInfo> {
        let total_memory = self.system.total_memory() as f32;
        
        self.system.processes()
            .iter()
            .map(|(pid, process)| {
                let pid_u32 = pid.as_u32();
                let memory_bytes = process.memory() * 1024;  // KB to bytes
                let virtual_memory_bytes = process.virtual_memory() * 1024;
                
                let memory_percent = if total_memory > 0.0 {
                    (process.memory() as f32 / total_memory) * 100.0
                } else {
                    0.0
                };
                
                // Calculate growth rate
                let (is_growing, growth_rate) = self.calculate_growth_rate(pid_u32);
                
                ProcessMemoryInfo {
                    pid: pid_u32,
                    name: process.name().to_string(),
                    memory_bytes,
                    virtual_memory_bytes,
                    memory_percent,
                    is_growing,
                    growth_rate_mb_per_min: growth_rate,
                }
            })
            .collect()
    }
    
    pub fn get_top_memory_processes(&self, limit: usize) -> Vec<ProcessMemoryInfo> {
        let mut processes = self.get_process_memory_info();
        processes.sort_by(|a, b| b.memory_bytes.cmp(&a.memory_bytes));
        processes.truncate(limit);
        processes
    }
    
    pub fn detect_memory_leaks(&self) -> Vec<ProcessMemoryInfo> {
        self.get_process_memory_info()
            .into_iter()
            .filter(|p| p.is_growing && p.growth_rate_mb_per_min > 1.0)  // Growing > 1MB/min
            .collect()
    }
    
    fn calculate_growth_rate(&self, pid: u32) -> (bool, f32) {
        if let Some(history) = self.process_memory_history.get(&pid) {
            if history.len() < 10 {
                return (false, 0.0);
            }
            
            // Calculate linear regression for trend
            let n = history.len() as f32;
            let mut sum_x = 0.0;
            let mut sum_y = 0.0;
            let mut sum_xy = 0.0;
            let mut sum_x2 = 0.0;
            
            for (i, &memory) in history.iter().enumerate() {
                let x = i as f32;
                let y = memory as f32 / 1024.0 / 1024.0;  // Convert to MB
                
                sum_x += x;
                sum_y += y;
                sum_xy += x * y;
                sum_x2 += x * x;
            }
            
            let slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x);
            
            // slope is MB per sample, convert to MB per minute (60 samples)
            let growth_rate = slope * 60.0;
            let is_growing = growth_rate > 0.1;  // Growing if > 0.1 MB/min
            
            (is_growing, growth_rate)
        } else {
            (false, 0.0)
        }
    }
    
    pub fn get_memory_pressure(&self) -> MemoryPressureLevel {
        let info = self.get_memory_info();
        info.memory_pressure
    }
}