//! macOS process analysis implementation

use crate::platform::{
    ProcessAnalyzer, ProcessState, IoWaitInfo, ProcessResponsiveness, ContextSwitchInfo,
    DeadlockInfo, DeadlockType, PlatformError, PlatformResult, StackTrace, StackFrame
};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use std::mem;
use libc::{kill, pid_t, SIGTERM, SIGCONT, c_int, c_void};

// macOS task_info structures and constants
#[repr(C)]
struct TaskEventsInfo {
    faults: u64,
    pageins: u64,
    cow_faults: u64,
    messages_sent: u64,
    messages_received: u64,
    syscalls_mach: u64,
    syscalls_unix: u64,
    csw: u64, // context switches
}

const TASK_EVENTS_INFO: c_int = 2;
const TASK_EVENTS_INFO_COUNT: u32 = (mem::size_of::<TaskEventsInfo>() / mem::size_of::<u32>()) as u32;

extern "C" {
    fn task_for_pid(target_task: u32, pid: c_int, task: *mut u32) -> c_int;
    fn task_info(task: u32, flavor: c_int, task_info: *mut c_void, task_info_count: *mut u32) -> c_int;
    fn mach_task_self() -> u32;
}

pub struct MacOSProcessAnalyzer {
    // Cache for tracking process responsiveness over time
    response_cache: std::sync::RwLock<HashMap<u32, ResponseHistory>>,
    // Cache for context switch tracking
    context_switch_cache: std::sync::RwLock<HashMap<u32, ContextSwitchHistory>>,
}

#[derive(Debug, Clone)]
struct ResponseHistory {
    last_test_time: Instant,
    response_times: Vec<Duration>,
    failed_signals: Vec<i32>,
    is_marked_unkillable: bool,
}

#[derive(Debug, Clone)]
struct ContextSwitchHistory {
    last_measurement: Instant,
    last_context_switches: u64,
    samples: Vec<(Instant, u64)>,
}

impl MacOSProcessAnalyzer {
    pub fn new() -> Self {
        Self {
            response_cache: std::sync::RwLock::new(HashMap::new()),
            context_switch_cache: std::sync::RwLock::new(HashMap::new()),
        }
    }
    
    /// Get task information using Mach APIs
    fn get_task_events_info(&self, pid: u32) -> PlatformResult<TaskEventsInfo> {
        unsafe {
            let mut task: u32 = 0;
            let task_result = task_for_pid(mach_task_self(), pid as c_int, &mut task);
            
            if task_result != 0 {
                return Err(PlatformError::PermissionDenied(
                    "Cannot get task port for process".to_string()
                ));
            }
            
            let mut events_info = TaskEventsInfo {
                faults: 0,
                pageins: 0,
                cow_faults: 0,
                messages_sent: 0,
                messages_received: 0,
                syscalls_mach: 0,
                syscalls_unix: 0,
                csw: 0,
            };
            
            let mut count = TASK_EVENTS_INFO_COUNT;
            let info_result = task_info(
                task,
                TASK_EVENTS_INFO,
                &mut events_info as *mut _ as *mut c_void,
                &mut count
            );
            
            if info_result != 0 {
                return Err(PlatformError::SystemCallFailed(
                    "task_info failed".to_string()
                ));
            }
            
            Ok(events_info)
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
        // Get task events info which contains context switch count
        let events_info = match self.get_task_events_info(pid) {
            Ok(info) => info,
            Err(_) => {
                // Fallback: return empty info if we can't get task port (common for system processes)
                return Ok(ContextSwitchInfo {
                    voluntary_switches: 0,
                    involuntary_switches: 0,
                    switches_per_second: 0.0,
                    is_high_frequency: false,
                });
            }
        };
        
        let current_switches = events_info.csw;
        let now = Instant::now();
        
        // Calculate switches per second using cached data
        let (switches_per_second, is_high_frequency) = {
            let mut cache = self.context_switch_cache.write()
                .map_err(|_| PlatformError::SystemCallFailed("Lock poisoned".to_string()))?;
                
            let history = cache.entry(pid).or_insert_with(|| ContextSwitchHistory {
                last_measurement: now,
                last_context_switches: current_switches,
                samples: Vec::new(),
            });
            
            let elapsed = now.duration_since(history.last_measurement).as_secs_f64();
            let switches_diff = current_switches.saturating_sub(history.last_context_switches);
            
            let rate = if elapsed > 0.0 {
                switches_diff as f64 / elapsed
            } else {
                0.0
            };
            
            // Keep sample history for better average calculation
            history.samples.push((now, current_switches));
            if history.samples.len() > 10 {
                history.samples.remove(0);
            }
            
            // Update cache
            history.last_measurement = now;
            history.last_context_switches = current_switches;
            
            // Consider high frequency if > 100 switches/second
            let is_high = rate > 100.0;
            
            (rate, is_high)
        };
        
        // macOS task_info doesn't distinguish voluntary vs involuntary,
        // so we estimate based on typical patterns
        let estimated_voluntary = (current_switches as f64 * 0.7) as u64;
        let estimated_involuntary = current_switches - estimated_voluntary;
        
        Ok(ContextSwitchInfo {
            voluntary_switches: estimated_voluntary,
            involuntary_switches: estimated_involuntary,
            switches_per_second,
            is_high_frequency,
        })
    }
    
    fn detect_deadlock(&self, pid: u32) -> PlatformResult<Option<DeadlockInfo>> {
        let sysctl_info = self.get_process_sysctl_info(pid)?;
        
        // Multiple deadlock detection strategies
        let mut detection_confidence = 0.0;
        let mut deadlock_type = DeadlockType::ResourceDeadlock;
        let mut involved_processes = vec![pid];
        
        // Strategy 1: Uninterruptible sleep + time
        if sysctl_info.state_char == 'D' {
            detection_confidence += 0.4;
            
            // Check if it's been unresponsive for a significant time
            if let Ok(cache) = self.response_cache.read() {
                if let Some(history) = cache.get(&pid) {
                    let elapsed_secs = history.last_test_time.elapsed().as_secs();
                    
                    if history.is_marked_unkillable {
                        detection_confidence += 0.3;
                        
                        // Longer unresponsiveness = higher confidence
                        if elapsed_secs > 60 {
                            detection_confidence += 0.2;
                        } else if elapsed_secs > 30 {
                            detection_confidence += 0.1;
                        }
                    }
                }
            }
            
            // Analyze wait channel for deadlock type
            if let Some(ref wchan) = sysctl_info.wchan {
                deadlock_type = self.classify_deadlock_type(wchan);
            }
        }
        
        // Strategy 2: Analyze context switches - stuck processes have very low switch rates
        if let Ok(context_info) = self.get_context_switches(pid) {
            if context_info.switches_per_second < 0.1 && detection_confidence > 0.3 {
                detection_confidence += 0.1;
            }
        }
        
        // Strategy 3: Check for circular wait patterns with lsof
        if detection_confidence > 0.4 {
            if let Ok(related_pids) = self.find_related_waiting_processes(pid) {
                if related_pids.len() > 1 {
                    detection_confidence += 0.2;
                    involved_processes = related_pids;
                }
            }
        }
        
        // Return deadlock info if confidence is high enough
        if detection_confidence > 0.6 {
            Ok(Some(DeadlockInfo {
                involved_processes,
                deadlock_type,
                resource_info: sysctl_info.wchan.unwrap_or("unknown".to_string()),
                detection_confidence,
            }))
        } else {
            Ok(None)
        }
    }
    
    fn collect_stack_trace(&self, pid: u32, duration_ms: u64) -> PlatformResult<StackTrace> {
        use std::process::Command;
        
        let start_time = std::time::SystemTime::now();
        
        // Use macOS `sample` command to collect stack trace
        let sample_duration_secs = (duration_ms as f64 / 1000.0).max(0.1);
        let output = Command::new("sample")
            .args(&[
                &pid.to_string(),
                &sample_duration_secs.to_string(),
                "-f", "profiler.txt", // Output format similar to profiler
                "-mayDie" // Allow sampling processes that might exit
            ])
            .output();
        
        let mut frames = Vec::new();
        let mut is_complete = false;
        
        match output {
            Ok(result) if result.status.success() => {
                let output_str = String::from_utf8_lossy(&result.stdout);
                frames = self.parse_sample_output(&output_str);
                is_complete = true;
            },
            Ok(result) => {
                // Try to parse partial output even if command failed
                let output_str = String::from_utf8_lossy(&result.stderr);
                if !output_str.is_empty() {
                    frames = self.parse_sample_output(&output_str);
                }
                // Return partial results
            },
            Err(_) => {
                // Fallback: try using spindump for kernel-level stack traces
                frames = self.collect_stack_trace_fallback(pid)?;
            }
        }
        
        Ok(StackTrace {
            pid,
            thread_id: None, // sample command aggregates all threads
            timestamp: start_time,
            frames,
            sample_duration_ms: duration_ms,
            is_complete,
        })
    }
}

impl MacOSProcessAnalyzer {
    /// Classify deadlock type based on wait channel
    fn classify_deadlock_type(&self, wchan: &str) -> DeadlockType {
        if wchan.contains("net") || wchan.contains("sock") || wchan.contains("tcp") || wchan.contains("udp") {
            DeadlockType::NetworkDeadlock
        } else if wchan.contains("bio") || wchan.contains("disk") || wchan.contains("vfs") || 
                  wchan.contains("read") || wchan.contains("write") || wchan.contains("buf") {
            DeadlockType::IoDeadlock
        } else {
            DeadlockType::ResourceDeadlock
        }
    }
    
    /// Find processes that might be involved in the same deadlock
    fn find_related_waiting_processes(&self, pid: u32) -> PlatformResult<Vec<u32>> {
        use std::process::Command;
        
        let mut related_pids = vec![pid];
        
        // Get all processes in uninterruptible sleep
        let uninterruptible = self.find_uninterruptible_processes()?;
        
        if uninterruptible.len() <= 1 {
            return Ok(related_pids);
        }
        
        // Use lsof to find processes sharing resources
        let output = Command::new("lsof")
            .args(&["-p", &pid.to_string(), "+f", "g"])
            .output();
            
        if let Ok(output) = output {
            if output.status.success() {
                let lsof_output = String::from_utf8_lossy(&output.stdout);
                let mut target_files = std::collections::HashSet::new();
                
                // Collect files/resources used by target process
                for line in lsof_output.lines().skip(1) {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 9 {
                        let file_type = parts[4];
                        let name = parts[8..].join(" ");
                        
                        // Focus on files that could cause deadlocks
                        if ["REG", "BLK", "CHR", "PIPE", "FIFO"].contains(&file_type) {
                            target_files.insert(name);
                        }
                    }
                }
                
                // Check other uninterruptible processes for shared resources
                for &other_pid in &uninterruptible {
                    if other_pid == pid {
                        continue;
                    }
                    
                    if self.shares_resources_with(other_pid, &target_files) {
                        related_pids.push(other_pid);
                    }
                }
            }
        }
        
        Ok(related_pids)
    }
    
    /// Check if a process shares resources that could cause deadlock
    fn shares_resources_with(&self, pid: u32, target_files: &std::collections::HashSet<String>) -> bool {
        use std::process::Command;
        
        let output = Command::new("lsof")
            .args(&["-p", &pid.to_string(), "+f", "g"])
            .output();
            
        if let Ok(output) = output {
            if output.status.success() {
                let lsof_output = String::from_utf8_lossy(&output.stdout);
                
                for line in lsof_output.lines().skip(1) {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 9 {
                        let name = parts[8..].join(" ");
                        
                        if target_files.contains(&name) {
                            return true;
                        }
                    }
                }
            }
        }
        
        false
    }
    
    /// Parse output from macOS `sample` command
    fn parse_sample_output(&self, output: &str) -> Vec<StackFrame> {
        let mut frames = Vec::new();
        let mut in_stack = false;
        
        for line in output.lines() {
            let line = line.trim();
            
            // Look for stack trace section
            if line.contains("Call graph:") || line.contains("Heavy hitters:") {
                in_stack = true;
                continue;
            }
            
            if !in_stack {
                continue;
            }
            
            // Parse stack frame lines (format varies)
            if let Some(frame) = self.parse_stack_frame_line(line) {
                frames.push(frame);
            }
            
            // Stop at next section
            if line.is_empty() && frames.len() > 0 {
                break;
            }
        }
        
        frames
    }
    
    /// Parse individual stack frame line
    fn parse_stack_frame_line(&self, line: &str) -> Option<StackFrame> {
        if line.is_empty() || line.starts_with("Process:") || line.starts_with("Date/Time:") {
            return None;
        }
        
        // Try to extract symbol information from various formats
        // Format 1: "  1234  function_name (in module_name) [0x123456]"
        if let Some(captures) = self.extract_sample_frame_info(line) {
            return Some(StackFrame {
                address: captures.0,
                symbol: captures.1,
                module: captures.2,
                file: None,
                line: None,
                offset: None,
            });
        }
        
        None
    }
    
    /// Extract frame info from sample output line
    fn extract_sample_frame_info(&self, line: &str) -> Option<(u64, Option<String>, Option<String>)> {
        // Simple regex-like parsing for sample output
        if let Some(addr_start) = line.rfind("[0x") {
            if let Some(addr_end) = line[addr_start..].find("]") {
                let addr_str = &line[addr_start+3..addr_start+addr_end];
                if let Ok(address) = u64::from_str_radix(addr_str, 16) {
                    
                    // Extract symbol (everything before address bracket)
                    let symbol_part = line[..addr_start].trim();
                    let mut symbol = None;
                    let mut module = None;
                    
                    // Look for " (in module_name)" pattern
                    if let Some(in_pos) = symbol_part.rfind(" (in ") {
                        if let Some(paren_end) = symbol_part[in_pos..].find(")") {
                            module = Some(symbol_part[in_pos+5..in_pos+paren_end].to_string());
                            symbol = Some(symbol_part[..in_pos].trim().to_string());
                        }
                    } else {
                        symbol = Some(symbol_part.to_string());
                    }
                    
                    return Some((address, symbol, module));
                }
            }
        }
        
        None
    }
    
    /// Fallback stack trace collection using spindump
    fn collect_stack_trace_fallback(&self, pid: u32) -> PlatformResult<Vec<StackFrame>> {
        use std::process::Command;
        
        let output = Command::new("spindump")
            .args(&[&pid.to_string(), "-stdout"])
            .output();
            
        match output {
            Ok(result) if result.status.success() => {
                let output_str = String::from_utf8_lossy(&result.stdout);
                Ok(self.parse_spindump_output(&output_str))
            },
            _ => {
                // Return empty stack trace if all methods fail
                Ok(Vec::new())
            }
        }
    }
    
    /// Parse spindump output (simpler format)
    fn parse_spindump_output(&self, output: &str) -> Vec<StackFrame> {
        let mut frames = Vec::new();
        let mut in_stack = false;
        
        for line in output.lines() {
            let line = line.trim();
            
            if line.contains("Thread ") && line.contains("dispatch queue") {
                in_stack = true;
                continue;
            }
            
            if !in_stack {
                continue;
            }
            
            // Stop at next thread or end
            if line.starts_with("Thread ") && !frames.is_empty() {
                break;
            }
            
            // Parse frame (spindump format is usually simpler)
            if let Some(frame) = self.parse_spindump_frame_line(line) {
                frames.push(frame);
            }
        }
        
        frames
    }
    
    /// Parse spindump frame line
    fn parse_spindump_frame_line(&self, line: &str) -> Option<StackFrame> {
        if line.is_empty() || !line.contains("0x") {
            return None;
        }
        
        // Very basic parsing for spindump
        if let Some(addr_start) = line.find("0x") {
            if let Some(space_pos) = line[addr_start..].find(" ") {
                let addr_str = &line[addr_start+2..addr_start+space_pos];
                if let Ok(address) = u64::from_str_radix(addr_str, 16) {
                    let symbol = if space_pos < line.len() - addr_start {
                        Some(line[addr_start+space_pos+1..].trim().to_string())
                    } else {
                        None
                    };
                    
                    return Some(StackFrame {
                        address,
                        symbol,
                        module: None,
                        file: None,
                        line: None,
                        offset: None,
                    });
                }
            }
        }
        
        None
    }
}