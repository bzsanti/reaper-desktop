use serde::{Deserialize, Serialize};
use std::time::Instant;
use sysinfo::System;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuMetrics {
    pub total_usage: f32,
    pub per_core_usage: Vec<f32>,
    pub load_average: LoadAverage,
    pub frequency_mhz: u64,
    pub temperature: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadAverage {
    pub one_minute: f64,
    pub five_minutes: f64,
    pub fifteen_minutes: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuBottleneck {
    pub bottleneck_type: BottleneckType,
    pub severity: f32,
    pub affected_processes: Vec<u32>,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BottleneckType {
    HighCpuUsage,
    HighIoWait,
    ExcessiveContextSwitching,
    ThermalThrottling,
    MemoryPressure,
}

pub struct CpuAnalyzer {
    system: System,
    last_update: Instant,
    history: Vec<CpuMetrics>,
    max_history_size: usize,
}

impl CpuAnalyzer {
    pub fn new() -> Self {
        let mut system = System::new();
        // Only refresh what we need initially
        system.refresh_cpu();
        system.refresh_memory();
        
        CpuAnalyzer {
            system,
            last_update: Instant::now(),
            history: Vec::with_capacity(60), // Pre-allocate
            max_history_size: 60,
        }
    }
    
    pub fn refresh(&mut self) {
        // Only refresh if enough time has passed (avoid too frequent updates)
        if self.last_update.elapsed().as_millis() < 500 {
            return;
        }
        
        self.system.refresh_cpu();
        self.system.refresh_memory();
        
        let metrics = self.get_current_metrics();
        
        // Use VecDeque would be better, but for now optimize with swap_remove
        if self.history.len() >= self.max_history_size {
            self.history.remove(0);
        }
        self.history.push(metrics);
        
        self.last_update = Instant::now();
    }
    
    pub fn get_current_metrics(&self) -> CpuMetrics {
        let load_avg = System::load_average();
        
        CpuMetrics {
            total_usage: self.system.global_cpu_info().cpu_usage(),
            per_core_usage: self.system.cpus().iter().map(|cpu| cpu.cpu_usage()).collect(),
            load_average: LoadAverage {
                one_minute: load_avg.one,
                five_minutes: load_avg.five,
                fifteen_minutes: load_avg.fifteen,
            },
            frequency_mhz: self.system.global_cpu_info().frequency(),
            temperature: None,
        }
    }
    
    pub fn detect_bottlenecks(&self) -> Vec<CpuBottleneck> {
        let mut bottlenecks = Vec::new();
        let metrics = self.get_current_metrics();
        
        if metrics.total_usage > 90.0 {
            bottlenecks.push(CpuBottleneck {
                bottleneck_type: BottleneckType::HighCpuUsage,
                severity: metrics.total_usage / 100.0,
                affected_processes: vec![],
                description: format!("CPU usage is critically high at {:.1}%", metrics.total_usage),
            });
        }
        
        if metrics.load_average.one_minute > self.system.cpus().len() as f64 * 2.0 {
            bottlenecks.push(CpuBottleneck {
                bottleneck_type: BottleneckType::ExcessiveContextSwitching,
                severity: ((metrics.load_average.one_minute / self.system.cpus().len() as f64) / 3.0) as f32,
                affected_processes: vec![],
                description: format!(
                    "System load ({:.2}) is significantly higher than CPU count ({})",
                    metrics.load_average.one_minute,
                    self.system.cpus().len()
                ),
            });
        }
        
        let memory_usage = (self.system.used_memory() as f64 / self.system.total_memory() as f64) * 100.0;
        if memory_usage > 90.0 {
            bottlenecks.push(CpuBottleneck {
                bottleneck_type: BottleneckType::MemoryPressure,
                severity: memory_usage as f32 / 100.0,
                affected_processes: vec![],
                description: format!("Memory usage is critically high at {:.1}%", memory_usage),
            });
        }
        
        bottlenecks
    }
    
    pub fn get_cpu_trend(&self) -> Option<f32> {
        if self.history.len() < 2 {
            return None;
        }
        
        let recent_avg: f32 = self.history.iter()
            .rev()
            .take(5)
            .map(|m| m.total_usage)
            .sum::<f32>() / 5.0_f32.min(self.history.len() as f32);
        
        let older_avg: f32 = self.history.iter()
            .rev()
            .skip(5)
            .take(5)
            .map(|m| m.total_usage)
            .sum::<f32>() / 5.0_f32.min((self.history.len() - 5).max(1) as f32);
        
        Some(recent_avg - older_avg)
    }
}