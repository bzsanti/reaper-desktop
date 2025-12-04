//! macOS platform implementation

mod process;
mod system;
mod kernel;
mod analyzer;

pub use process::MacOSProcessManager;
pub use system::MacOSSystemMonitor;
pub use kernel::MacOSKernelOps;
pub use analyzer::MacOSProcessAnalyzer;

use super::{ProcessManager, SystemMonitor, KernelOperations, ProcessAnalyzer};

/// Main platform implementation for macOS
pub struct MacOSPlatform {
    process_manager: MacOSProcessManager,
    system_monitor: MacOSSystemMonitor,
    kernel_ops: MacOSKernelOps,
    process_analyzer: MacOSProcessAnalyzer,
}

impl MacOSPlatform {
    pub fn new() -> Self {
        Self {
            process_manager: MacOSProcessManager::new(),
            system_monitor: MacOSSystemMonitor::new(),
            kernel_ops: MacOSKernelOps::new(),
            process_analyzer: MacOSProcessAnalyzer::new(),
        }
    }
    
    pub fn process_manager(&self) -> &dyn ProcessManager {
        &self.process_manager
    }
    
    pub fn system_monitor(&self) -> &dyn SystemMonitor {
        &self.system_monitor
    }
    
    pub fn kernel_ops(&self) -> &dyn KernelOperations {
        &self.kernel_ops
    }
    
    pub fn process_analyzer(&self) -> &dyn ProcessAnalyzer {
        &self.process_analyzer
    }
}

impl Default for MacOSPlatform {
    fn default() -> Self {
        Self::new()
    }
}