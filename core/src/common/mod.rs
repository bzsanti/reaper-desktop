use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemInfo {
    pub hostname: String,
    pub os_version: String,
    pub kernel_version: String,
    pub cpu_count: usize,
    pub total_memory: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MonitorType {
    CPU,
    Memory,
    Disk,
    Network,
}

pub trait Monitor {
    fn name(&self) -> &str;
    fn monitor_type(&self) -> MonitorType;
    fn refresh(&mut self);
}