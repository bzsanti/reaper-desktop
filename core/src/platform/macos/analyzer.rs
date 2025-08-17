//! macOS process analysis implementation

use crate::platform::{
    ProcessAnalyzer, ProcessState, IoWaitInfo, ProcessResponsiveness, ContextSwitchInfo,
    DeadlockInfo, DeadlockType, PlatformError, PlatformResult, Signal
};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use libc::{kill, pid_t, SIGTERM, SIGKILL, SIGCONT};

pub struct MacOSProcessAnalyzer {
    // Cache for tracking process responsiveness over time
    response_cache: std::sync::RwLock<HashMap<u32, ResponseHistory>>,
}

#[derive(Debug, Clone)]
struct ResponseHistory {
    last_test_time: Instant,
    response_times: Vec<Duration>,
    failed_signals: Vec<i32>,
    is_marked_unkillable: bool,
}

impl MacOSProcessAnalyzer {
    pub fn new() -> Self {
        Self {
            response_cache: std::sync::RwLock::new(HashMap::new()),
        }
    }
    
    /// Test if a process responds to a signal within a timeout
    fn test_signal_response(&self, pid: u32, signal: i32, timeout_ms: u64) -> bool {
        let start = Instant::now();
        
        // Send signal (use 0 for existence check, actual signal for response test)
        let result = unsafe { kill(pid as pid_t, signal) };
        
        if result != 0 {
            return false; // Process doesn't exist or permission denied
        }
        
        // For signal 0, if kill succeeds, process exists and is responsive
        if signal == 0 {
            return true;
        }
        
        // For other signals, check if process is still running after a brief delay
        std::thread::sleep(Duration::from_millis(50));
        
        let check_result = unsafe { kill(pid as pid_t, 0) };
        let elapsed = start.elapsed();
        
        // If process still exists and responded quickly, it's responsive
        check_result == 0 && elapsed.as_millis() < timeout_ms as u128
    }
    
    /// Get process information from /proc filesystem equivalent (sysctl on macOS)
    fn get_process_sysctl_info(&self, pid: u32) -> PlatformResult<ProcessSysctlInfo> {
        use std::process::Command;
        
        // Use ps command to get detailed process information
        let output = Command::new("ps")
            .args(&["-o", "pid,ppid,state,wchan,ni,time", "-p", &pid.to_string()])
            .output()
            .map_err(|e| PlatformError::SystemCallFailed(format!("ps command failed: {}", e)))?;
        
        let output_str = String::from_utf8_lossy(&output.stdout);
        let lines: Vec<&str> = output_str.lines().collect();
        
        if lines.len() < 2 {
            return Err(PlatformError::ProcessNotFound(pid));
        }
        
        let data_line = lines[1];
        let fields: Vec<&str> = data_line.split_whitespace().collect();
        
        if fields.len() < 6 {
            return Err(PlatformError::SystemCallFailed("Invalid ps output".to_string()));
        }
        
        Ok(ProcessSysctlInfo {
            pid,
            state_char: fields[2].chars().next().unwrap_or('?'),
            wchan: if fields[3] == "-" { None } else { Some(fields[3].to_string()) },
            nice: fields[4].parse().unwrap_or(0),
            cpu_time: fields[5].to_string(),
        })
    }
}

#[derive(Debug)]
struct ProcessSysctlInfo {
    pid: u32,
    state_char: char,
    wchan: Option<String>,
    nice: i32,
    cpu_time: String,
}

impl ProcessAnalyzer for MacOSProcessAnalyzer {
    fn analyze_unkillable(&self, pid: u32) -> PlatformResult<bool> {
        // Test responsiveness to different signals
        let signals_to_test = vec![0, SIGTERM, SIGCONT]; // 0 = existence check, SIGTERM, SIGCONT
        let mut failed_signals = 0;
        
        for &signal in &signals_to_test {
            if !self.test_signal_response(pid, signal, 1000) {
                failed_signals += 1;
            }
        }
        
        // If process fails to respond to multiple signals, it's likely unkillable
        let is_unkillable = failed_signals >= 2;
        
        // Update cache
        if let Ok(mut cache) = self.response_cache.write() {
            let history = cache.entry(pid).or_insert_with(|| ResponseHistory {
                last_test_time: Instant::now(),
                response_times: Vec::new(),
                failed_signals: Vec::new(),
                is_marked_unkillable: false,
            });
            
            history.last_test_time = Instant::now();
            history.is_marked_unkillable = is_unkillable;
            
            if is_unkillable {
                for &signal in &signals_to_test {
                    if !self.test_signal_response(pid, signal, 100) {
                        history.failed_signals.push(signal);
                    }
                }
            }
        }
        
        Ok(is_unkillable)
    }
    
    fn get_process_state(&self, pid: u32) -> PlatformResult<ProcessState> {
        let sysctl_info = self.get_process_sysctl_info(pid)?;
        
        Ok(ProcessState {
            state_char: sysctl_info.state_char,
            wchan: sysctl_info.wchan,
            flags: 0, // TODO: Get actual flags from sysctl
            nice: sysctl_info.nice,
            num_threads: 1, // TODO: Get actual thread count
            tgid: pid,
            blocked_signals: 0, // TODO: Get actual blocked signals
            pending_signals: 0, // TODO: Get actual pending signals
        })
    }
    
    fn find_uninterruptible_processes(&self) -> PlatformResult<Vec<u32>> {
        use std::process::Command;
        
        // Use ps to find processes in uninterruptible sleep (state 'D')
        let output = Command::new("ps")
            .args(&["-axo", "pid,state"])
            .output()
            .map_err(|e| PlatformError::SystemCallFailed(format!("ps command failed: {}", e)))?;
        
        let output_str = String::from_utf8_lossy(&output.stdout);
        let mut uninterruptible_pids = Vec::new();
        
        for line in output_str.lines().skip(1) { // Skip header
            let fields: Vec<&str> = line.split_whitespace().collect();
            if fields.len() >= 2 {
                if let Ok(pid) = fields[0].parse::<u32>() {
                    if fields[1].contains('D') { // 'D' = uninterruptible sleep
                        uninterruptible_pids.push(pid);
                    }
                }
            }
        }
        
        Ok(uninterruptible_pids)
    }
    
    fn analyze_io_wait(&self, pid: u32) -> PlatformResult<IoWaitInfo> {
        let sysctl_info = self.get_process_sysctl_info(pid)?;
        
        // Determine if process is waiting on I/O based on wchan and state
        let is_io_wait = sysctl_info.state_char == 'D' || 
                        sysctl_info.wchan.as_ref()
                            .map(|w| w.contains("bio") || w.contains("disk") || w.contains("read") || w.contains("write"))
                            .unwrap_or(false);
        
        Ok(IoWaitInfo {
            total_wait_time_ms: if is_io_wait { 1000 } else { 0 }, // Simplified
            current_wait_operation: sysctl_info.wchan,
            blocked_on_device: None, // TODO: Parse from wchan
            io_operations_pending: if is_io_wait { 1 } else { 0 },
        })
    }
    
    fn test_process_responsiveness(&self, pid: u32) -> PlatformResult<ProcessResponsiveness> {
        let start_time = Instant::now();
        
        // Test with signal 0 (existence check)
        let responds_to_signals = self.test_signal_response(pid, 0, 500);
        let response_time = if responds_to_signals {
            Some(start_time.elapsed().as_millis() as u64)
        } else {
            None
        };
        
        // Test multiple signals
        let test_signals = vec![0, SIGTERM, SIGCONT];
        let mut signal_results = HashMap::new();
        
        for &signal in &test_signals {
            signal_results.insert(signal, self.test_signal_response(pid, signal, 200));
        }
        
        let failed_count = signal_results.values().filter(|&&v| !v).count();
        let is_likely_unkillable = failed_count >= 2;
        
        Ok(ProcessResponsiveness {
            responds_to_signals,
            last_response_time_ms: response_time,
            signal_test_results: signal_results,
            is_likely_unkillable,
        })
    }
    
    fn get_context_switches(&self, pid: u32) -> PlatformResult<ContextSwitchInfo> {
        // macOS doesn't easily expose context switch info via standard APIs
        // This would require more advanced kernel introspection
        
        Ok(ContextSwitchInfo {
            voluntary_switches: 0,
            involuntary_switches: 0,
            switches_per_second: 0.0,
            is_high_frequency: false,
        })
    }
    
    fn detect_deadlock(&self, pid: u32) -> PlatformResult<Option<DeadlockInfo>> {
        // Basic deadlock detection - check if process is stuck in uninterruptible sleep
        // and hasn't responded to signals for an extended period
        
        let sysctl_info = self.get_process_sysctl_info(pid)?;
        
        if sysctl_info.state_char == 'D' {
            // Check if it's been unresponsive for a while
            if let Ok(cache) = self.response_cache.read() {
                if let Some(history) = cache.get(&pid) {
                    if history.is_marked_unkillable && 
                       history.last_test_time.elapsed() > Duration::from_secs(30) {
                        return Ok(Some(DeadlockInfo {
                            involved_processes: vec![pid],
                            deadlock_type: if sysctl_info.wchan.as_ref()
                                .map(|w| w.contains("net") || w.contains("sock"))
                                .unwrap_or(false) {
                                DeadlockType::NetworkDeadlock
                            } else {
                                DeadlockType::IoDeadlock
                            },
                            resource_info: sysctl_info.wchan.unwrap_or("unknown".to_string()),
                            detection_confidence: 0.7,
                        }));
                    }
                }
            }
        }
        
        Ok(None)
    }
}