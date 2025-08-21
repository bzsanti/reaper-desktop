//! Platform abstraction layer for cross-platform support
//! 
//! This module provides traits and implementations for platform-specific
//! operations, allowing the core functionality to work across different
//! operating systems while maintaining native performance.

use std::collections::HashMap;

#[cfg(test)]
mod tests;

#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "windows")]
pub mod windows;

// Re-export the current platform implementation
#[cfg(target_os = "macos")]
pub use macos::*;

#[cfg(target_os = "windows")]
pub use windows::*;

/// Result type for platform operations
pub type PlatformResult<T> = Result<T, PlatformError>;

/// Platform-specific errors
#[derive(Debug, Clone)]
pub enum PlatformError {
    /// Process not found
    ProcessNotFound(u32),
    /// Permission denied for operation
    PermissionDenied(String),
    /// Process cannot be killed (kernel process, etc.)
    ProcessUnkillable(String),
    /// System call failed
    SystemCallFailed(String),
    /// Feature not supported on this platform
    NotSupported(String),
    /// Generic error with code
    Unknown(i32, String),
}

impl std::fmt::Display for PlatformError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ProcessNotFound(pid) => write!(f, "Process {} not found", pid),
            Self::PermissionDenied(msg) => write!(f, "Permission denied: {}", msg),
            Self::ProcessUnkillable(reason) => write!(f, "Process unkillable: {}", reason),
            Self::SystemCallFailed(call) => write!(f, "System call failed: {}", call),
            Self::NotSupported(feature) => write!(f, "Not supported: {}", feature),
            Self::Unknown(code, msg) => write!(f, "Unknown error {}: {}", code, msg),
        }
    }
}

impl std::error::Error for PlatformError {}

/// Process information structure
#[derive(Debug, Clone)]
pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
    pub cpu_usage: f32,
    pub memory_bytes: u64,
    pub virtual_memory_bytes: u64,
    pub status: ProcessStatus,
    pub parent_pid: Option<u32>,
    pub thread_count: usize,
    pub run_time_seconds: u64,
    pub user_time_seconds: f32,
    pub system_time_seconds: f32,
    pub executable_path: Option<String>,
    pub command_line: Vec<String>,
    pub environment: HashMap<String, String>,
    
    // Advanced analysis fields
    /// Time spent in uninterruptible sleep (I/O wait)
    pub io_wait_time_ms: u64,
    /// Number of context switches (voluntary + involuntary)
    pub context_switches: u64,
    /// Number of minor page faults
    pub minor_faults: u64,
    /// Number of major page faults
    pub major_faults: u64,
    /// Process priority/nice value
    pub priority: i32,
    /// Whether process has been detected as unkillable
    pub is_unkillable: bool,
    /// Time since last successful signal response (for unkillable detection)
    pub last_signal_response_ms: Option<u64>,
}

/// Process status enumeration
#[derive(Debug, Clone, PartialEq)]
pub enum ProcessStatus {
    Running,
    Sleeping,
    Waiting,
    Zombie,
    Stopped,
    Idle,
    /// Uninterruptible sleep (usually IO wait)
    UninterruptibleSleep,
    /// Process is unkillable
    Unkillable,
    Unknown,
}

impl ProcessStatus {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Running => "Running",
            Self::Sleeping => "Sleeping",
            Self::Waiting => "Waiting",
            Self::Zombie => "Zombie",
            Self::Stopped => "Stopped",
            Self::Idle => "Idle",
            Self::UninterruptibleSleep => "Uninterruptible",
            Self::Unkillable => "Unkillable",
            Self::Unknown => "Unknown",
        }
    }
    
    /// Returns true if this process status indicates a problematic state
    pub fn is_problematic(&self) -> bool {
        matches!(self, Self::UninterruptibleSleep | Self::Unkillable | Self::Zombie)
    }
    
    /// Returns true if this process is likely unkillable
    pub fn is_unkillable(&self) -> bool {
        matches!(self, Self::Unkillable | Self::UninterruptibleSleep)
    }
}

/// System metrics information
#[derive(Debug, Clone)]
pub struct SystemMetrics {
    pub cpu_count: usize,
    pub cpu_frequency_mhz: f64,
    pub cpu_usage_percent: f32,
    pub memory_total_bytes: u64,
    pub memory_used_bytes: u64,
    pub memory_available_bytes: u64,
    pub swap_total_bytes: u64,
    pub swap_used_bytes: u64,
    pub load_average_1min: f64,
    pub load_average_5min: f64,
    pub load_average_15min: f64,
    pub uptime_seconds: u64,
}

/// Signal types for process control
#[derive(Debug, Clone, Copy)]
pub enum Signal {
    Terminate,  // SIGTERM equivalent
    Kill,       // SIGKILL equivalent
    Stop,       // SIGSTOP equivalent
    Continue,   // SIGCONT equivalent
    Interrupt,  // SIGINT equivalent
}

/// Trait for process management operations
pub trait ProcessManager: Send + Sync {
    /// List all processes
    fn list_processes(&self) -> PlatformResult<Vec<ProcessInfo>>;
    
    /// Get detailed information about a specific process
    fn get_process_info(&self, pid: u32) -> PlatformResult<ProcessInfo>;
    
    /// Send a signal to a process
    fn send_signal(&self, pid: u32, signal: Signal) -> PlatformResult<()>;
    
    /// Check if a process is responsive
    fn is_process_responsive(&self, pid: u32) -> PlatformResult<bool>;
    
    /// Get child processes of a given process
    fn get_child_processes(&self, pid: u32) -> PlatformResult<Vec<u32>>;
    
    /// Check if process can be terminated
    fn can_terminate_process(&self, pid: u32) -> PlatformResult<bool>;
}

/// Trait for system metrics collection
pub trait SystemMonitor: Send + Sync {
    /// Get current system metrics
    fn get_system_metrics(&self) -> PlatformResult<SystemMetrics>;
    
    /// Get CPU temperature if available
    fn get_cpu_temperature(&self) -> PlatformResult<Option<f32>>;
    
    /// Get disk I/O statistics
    fn get_disk_io_stats(&self) -> PlatformResult<HashMap<String, (u64, u64)>>;
    
    /// Get network I/O statistics
    fn get_network_io_stats(&self) -> PlatformResult<HashMap<String, (u64, u64)>>;
}

/// Trait for kernel-level operations
pub trait KernelOperations: Send + Sync {
    /// Force kill a process at kernel level
    fn force_kill(&self, pid: u32) -> PlatformResult<()>;
    
    /// Suspend a process
    fn suspend_process(&self, pid: u32) -> PlatformResult<()>;
    
    /// Resume a suspended process
    fn resume_process(&self, pid: u32) -> PlatformResult<()>;
    
    /// Check if process is a kernel process
    fn is_kernel_process(&self, pid: u32) -> bool;
    
    /// Get process priority
    fn get_process_priority(&self, pid: u32) -> PlatformResult<i32>;
    
    /// Set process priority
    fn set_process_priority(&self, pid: u32, priority: i32) -> PlatformResult<()>;
}

/// Trait for advanced process analysis
pub trait ProcessAnalyzer: Send + Sync {
    /// Analyze if a process is unkillable
    fn analyze_unkillable(&self, pid: u32) -> PlatformResult<bool>;
    
    /// Get detailed process state information
    fn get_process_state(&self, pid: u32) -> PlatformResult<ProcessState>;
    
    /// Detect processes in uninterruptible sleep
    fn find_uninterruptible_processes(&self) -> PlatformResult<Vec<u32>>;
    
    /// Analyze I/O wait for a process
    fn analyze_io_wait(&self, pid: u32) -> PlatformResult<IoWaitInfo>;
    
    /// Test process responsiveness
    fn test_process_responsiveness(&self, pid: u32) -> PlatformResult<ProcessResponsiveness>;
    
    /// Get context switch information
    fn get_context_switches(&self, pid: u32) -> PlatformResult<ContextSwitchInfo>;
    
    /// Detect potential deadlock involving this process
    fn detect_deadlock(&self, pid: u32) -> PlatformResult<Option<DeadlockInfo>>;
    
    /// Collect stack trace for a process
    fn collect_stack_trace(&self, pid: u32, duration_ms: u64) -> PlatformResult<StackTrace>;
}

/// Detailed process state information
#[derive(Debug, Clone)]
pub struct ProcessState {
    pub state_char: char,
    pub wchan: Option<String>,
    pub flags: u64,
    pub nice: i32,
    pub num_threads: usize,
    pub tgid: u32,
    pub blocked_signals: u64,
    pub pending_signals: u64,
}

/// I/O wait analysis information
#[derive(Debug, Clone)]
pub struct IoWaitInfo {
    pub total_wait_time_ms: u64,
    pub current_wait_operation: Option<String>,
    pub blocked_on_device: Option<String>,
    pub io_operations_pending: u32,
}

/// Process responsiveness test results
#[derive(Debug, Clone)]
pub struct ProcessResponsiveness {
    pub responds_to_signals: bool,
    pub last_response_time_ms: Option<u64>,
    pub signal_test_results: HashMap<i32, bool>,
    pub is_likely_unkillable: bool,
}

/// Context switch analysis
#[derive(Debug, Clone)]
pub struct ContextSwitchInfo {
    pub voluntary_switches: u64,
    pub involuntary_switches: u64,
    pub switches_per_second: f64,
    pub is_high_frequency: bool,
}

/// Deadlock detection information
#[derive(Debug, Clone)]
pub struct DeadlockInfo {
    pub involved_processes: Vec<u32>,
    pub deadlock_type: DeadlockType,
    pub resource_info: String,
    pub detection_confidence: f32,
}

/// Types of deadlocks that can be detected
#[derive(Debug, Clone, PartialEq)]
pub enum DeadlockType {
    ResourceDeadlock,
    IoDeadlock,
    NetworkDeadlock,
    Unknown,
}

/// Stack trace information for a process
#[derive(Debug, Clone)]
pub struct StackTrace {
    pub pid: u32,
    pub thread_id: Option<u64>,
    pub timestamp: std::time::SystemTime,
    pub frames: Vec<StackFrame>,
    pub sample_duration_ms: u64,
    pub is_complete: bool,
}

/// Individual stack frame
#[derive(Debug, Clone)]
pub struct StackFrame {
    pub address: u64,
    pub symbol: Option<String>,
    pub module: Option<String>,
    pub file: Option<String>,
    pub line: Option<u32>,
    pub offset: Option<u64>,
}

/// Platform capability detection
pub struct PlatformCapabilities {
    pub can_kill_processes: bool,
    pub can_suspend_processes: bool,
    pub can_set_priority: bool,
    pub has_temperature_sensors: bool,
    pub supports_process_groups: bool,
    pub requires_elevation: bool,
}

impl Default for PlatformCapabilities {
    fn default() -> Self {
        Self {
            can_kill_processes: true,
            can_suspend_processes: true,
            can_set_priority: true,
            has_temperature_sensors: false,
            supports_process_groups: true,
            requires_elevation: false,
        }
    }
}

/// Get current platform capabilities
pub fn get_platform_capabilities() -> PlatformCapabilities {
    #[cfg(target_os = "macos")]
    {
        PlatformCapabilities {
            can_kill_processes: true,
            can_suspend_processes: true,
            can_set_priority: true,
            has_temperature_sensors: true,  // Via IOKit
            supports_process_groups: true,
            requires_elevation: false,  // For some operations
        }
    }
    
    #[cfg(target_os = "windows")]
    {
        PlatformCapabilities {
            can_kill_processes: true,
            can_suspend_processes: true,
            can_set_priority: true,
            has_temperature_sensors: true,  // Via WMI
            supports_process_groups: false,  // Job objects instead
            requires_elevation: true,  // For many operations
        }
    }
    
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        PlatformCapabilities::default()
    }
}