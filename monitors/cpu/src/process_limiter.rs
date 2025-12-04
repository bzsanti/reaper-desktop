use std::collections::HashMap;
use std::process::Command;
use libc::c_int;

/// Process CPU Limiter - Controls CPU usage of external processes
/// Uses nice values, CPU affinity, and optional cpulimit tool
#[derive(Debug)]
pub struct ProcessCpuLimiter {
    /// Active CPU limits by PID
    limits: HashMap<u32, CpuLimit>,
    /// Check if cpulimit tool is available
    cpulimit_available: Option<bool>,
}

#[derive(Debug, Clone)]
pub struct CpuLimit {
    pub pid: u32,
    pub max_cpu_percent: f32,
    pub nice_value: i32,
    pub original_nice: Option<i32>,
    pub affinity_mask: Option<u64>,
    pub limit_type: LimitType,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LimitType {
    Nice,           // Only nice value changed
    Affinity,       // CPU affinity set
    CpuLimit,       // Using cpulimit tool
    Combined,       // Multiple methods
}

#[derive(Debug)]
pub enum LimitError {
    PermissionDenied,
    ProcessNotFound,
    InvalidLimit,
    SystemError(String),
}

impl ProcessCpuLimiter {
    pub fn new() -> Self {
        Self {
            limits: HashMap::new(),
            cpulimit_available: None,
        }
    }

    /// Limit CPU usage of a process
    pub fn limit_process(&mut self, pid: u32, max_percent: f32) -> Result<(), LimitError> {
        // Validate limit
        if max_percent < 1.0 || max_percent > 100.0 {
            return Err(LimitError::InvalidLimit);
        }

        // Get current nice value
        let original_nice = self.get_nice_value(pid)?;
        
        // Calculate appropriate nice value based on limit
        let nice_value = self.calculate_nice_from_limit(max_percent);
        
        // Try multiple methods in order of preference
        let mut limit_type = LimitType::Nice;
        
        // 1. Try cpulimit if available (most precise)
        if self.check_cpulimit_available() {
            if self.apply_cpulimit(pid, max_percent).is_ok() {
                limit_type = LimitType::CpuLimit;
            }
        }
        
        // 2. Always apply nice value (works on all systems)
        self.set_nice_value(pid, nice_value)?;
        
        // 3. Try CPU affinity on multi-core systems
        if let Ok(cores) = self.get_cpu_count() {
            if cores > 1 {
                let allowed_cores = self.calculate_allowed_cores(max_percent, cores);
                if let Ok(_mask) = self.set_cpu_affinity(pid, allowed_cores) {
                    if limit_type == LimitType::CpuLimit {
                        limit_type = LimitType::Combined;
                    } else {
                        limit_type = LimitType::Affinity;
                    }
                }
            }
        }
        
        // Store limit info
        let limit = CpuLimit {
            pid,
            max_cpu_percent: max_percent,
            nice_value,
            original_nice: Some(original_nice),
            affinity_mask: None,
            limit_type,
        };
        
        self.limits.insert(pid, limit);
        Ok(())
    }

    /// Remove CPU limit from a process
    pub fn remove_limit(&mut self, pid: u32) -> Result<(), LimitError> {
        if let Some(limit) = self.limits.remove(&pid) {
            // Restore original nice value
            if let Some(original) = limit.original_nice {
                self.set_nice_value(pid, original)?;
            }
            
            // Kill cpulimit if it was used
            if limit.limit_type == LimitType::CpuLimit || limit.limit_type == LimitType::Combined {
                self.kill_cpulimit(pid);
            }
            
            // Note: CPU affinity is not restored as we don't track original
            Ok(())
        } else {
            Err(LimitError::ProcessNotFound)
        }
    }

    /// Set nice value for a process
    fn set_nice_value(&self, pid: u32, nice: i32) -> Result<(), LimitError> {
        unsafe {
            let result = libc::setpriority(
                libc::PRIO_PROCESS,
                pid as libc::id_t,
                nice as c_int
            );
            
            if result == 0 {
                Ok(())
            } else {
                let errno = *libc::__error();
                match errno {
                    libc::EPERM => Err(LimitError::PermissionDenied),
                    libc::ESRCH => Err(LimitError::ProcessNotFound),
                    _ => Err(LimitError::SystemError(format!("errno: {}", errno))),
                }
            }
        }
    }

    /// Get current nice value of a process
    fn get_nice_value(&self, pid: u32) -> Result<i32, LimitError> {
        unsafe {
            // Reset errno before call
            *libc::__error() = 0;
            
            let nice = libc::getpriority(
                libc::PRIO_PROCESS,
                pid as libc::id_t
            );
            
            let errno = *libc::__error();
            if errno != 0 {
                match errno {
                    libc::EPERM => Err(LimitError::PermissionDenied),
                    libc::ESRCH => Err(LimitError::ProcessNotFound),
                    _ => Err(LimitError::SystemError(format!("errno: {}", errno))),
                }
            } else {
                Ok(nice as i32)
            }
        }
    }

    /// Calculate nice value based on CPU limit percentage
    fn calculate_nice_from_limit(&self, max_percent: f32) -> i32 {
        match max_percent {
            p if p >= 75.0 => 0,   // Normal priority
            p if p >= 50.0 => 5,   // Slightly lower
            p if p >= 25.0 => 10,  // Lower priority
            p if p >= 10.0 => 15,  // Much lower
            _ => 19,               // Minimum priority
        }
    }

    /// Calculate how many CPU cores to allow based on limit
    fn calculate_allowed_cores(&self, max_percent: f32, total_cores: usize) -> usize {
        let allowed = ((max_percent / 100.0) * total_cores as f32).ceil() as usize;
        allowed.max(1).min(total_cores)
    }

    /// Set CPU affinity for a process (macOS specific implementation)
    fn set_cpu_affinity(&self, _pid: u32, _allowed_cores: usize) -> Result<u64, LimitError> {
        // Note: macOS doesn't have standard CPU affinity APIs like Linux
        // This would require using thread_policy_set with THREAD_AFFINITY_POLICY
        // For now, return error indicating not supported
        Err(LimitError::SystemError("CPU affinity not fully supported on macOS".to_string()))
    }

    /// Get number of CPU cores
    fn get_cpu_count(&self) -> Result<usize, LimitError> {
        unsafe {
            let mut count: c_int = 0;
            let mut size = std::mem::size_of::<c_int>();
            let mib = [libc::CTL_HW, libc::HW_NCPU];
            
            let result = libc::sysctl(
                mib.as_ptr() as *mut c_int,
                2,
                &mut count as *mut _ as *mut libc::c_void,
                &mut size,
                std::ptr::null_mut(),
                0
            );
            
            if result == 0 {
                Ok(count as usize)
            } else {
                Err(LimitError::SystemError("Failed to get CPU count".to_string()))
            }
        }
    }

    /// Check if cpulimit tool is available
    fn check_cpulimit_available(&mut self) -> bool {
        if let Some(available) = self.cpulimit_available {
            return available;
        }
        
        let result = Command::new("which")
            .arg("cpulimit")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false);
        
        self.cpulimit_available = Some(result);
        result
    }

    /// Apply CPU limit using cpulimit tool
    fn apply_cpulimit(&self, pid: u32, limit: f32) -> Result<(), LimitError> {
        let output = Command::new("cpulimit")
            .args(&[
                "-p", &pid.to_string(),
                "-l", &(limit as i32).to_string(),
                "-b", // Background mode
            ])
            .output()
            .map_err(|e| LimitError::SystemError(e.to_string()))?;
        
        if output.status.success() {
            Ok(())
        } else {
            Err(LimitError::SystemError(
                String::from_utf8_lossy(&output.stderr).to_string()
            ))
        }
    }

    /// Kill cpulimit process for a PID
    fn kill_cpulimit(&self, target_pid: u32) {
        // Find and kill cpulimit process targeting this PID
        let _ = Command::new("pkill")
            .args(&["-f", &format!("cpulimit.*-p {}", target_pid)])
            .output();
    }

    /// Get all active limits
    pub fn get_limits(&self) -> Vec<&CpuLimit> {
        self.limits.values().collect()
    }

    /// Check if a process has a limit
    pub fn has_limit(&self, pid: u32) -> bool {
        self.limits.contains_key(&pid)
    }

    /// Quick preset limits
    pub fn limit_to_preset(&mut self, pid: u32, preset: LimitPreset) -> Result<(), LimitError> {
        let percent = match preset {
            LimitPreset::High => 75.0,
            LimitPreset::Medium => 50.0,
            LimitPreset::Low => 25.0,
            LimitPreset::Minimal => 10.0,
        };
        self.limit_process(pid, percent)
    }
}

#[derive(Debug, Clone, Copy)]
pub enum LimitPreset {
    High,    // 75% CPU
    Medium,  // 50% CPU
    Low,     // 25% CPU
    Minimal, // 10% CPU
}

/// C FFI exports for Swift integration
#[repr(C)]
pub struct CCpuLimit {
    pub pid: u32,
    pub max_cpu_percent: f32,
    pub nice_value: i32,
    pub limit_type: u8,
}

#[repr(C)]
pub struct CCpuLimitList {
    pub limits: *mut CCpuLimit,
    pub count: usize,
}

#[no_mangle]
pub extern "C" fn limit_process_cpu(pid: u32, max_percent: f32) -> i32 {
    use once_cell::sync::Lazy;
    use std::sync::Mutex;
    
    static LIMITER: Lazy<Mutex<ProcessCpuLimiter>> = Lazy::new(|| {
        Mutex::new(ProcessCpuLimiter::new())
    });
    
    match LIMITER.lock() {
        Ok(mut limiter) => {
            match limiter.limit_process(pid, max_percent) {
                Ok(_) => 0,
                Err(LimitError::PermissionDenied) => -1,
                Err(LimitError::ProcessNotFound) => -2,
                Err(LimitError::InvalidLimit) => -3,
                Err(_) => -4,
            }
        }
        Err(_) => -5,
    }
}

#[no_mangle]
pub extern "C" fn remove_process_limit(pid: u32) -> i32 {
    use once_cell::sync::Lazy;
    use std::sync::Mutex;
    
    static LIMITER: Lazy<Mutex<ProcessCpuLimiter>> = Lazy::new(|| {
        Mutex::new(ProcessCpuLimiter::new())
    });
    
    match LIMITER.lock() {
        Ok(mut limiter) => {
            match limiter.remove_limit(pid) {
                Ok(_) => 0,
                Err(_) => -1,
            }
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn set_process_nice(pid: u32, nice_value: i32) -> i32 {
    let limiter = ProcessCpuLimiter::new();
    match limiter.set_nice_value(pid, nice_value) {
        Ok(_) => 0,
        Err(LimitError::PermissionDenied) => -1,
        Err(LimitError::ProcessNotFound) => -2,
        Err(_) => -3,
    }
}

#[no_mangle]
pub extern "C" fn get_all_cpu_limits() -> *mut CCpuLimitList {
    use once_cell::sync::Lazy;
    use std::sync::Mutex;
    
    static LIMITER: Lazy<Mutex<ProcessCpuLimiter>> = Lazy::new(|| {
        Mutex::new(ProcessCpuLimiter::new())
    });
    
    match LIMITER.lock() {
        Ok(limiter) => {
            let limits = limiter.get_limits();
            let count = limits.len();
            
            if count == 0 {
                return Box::into_raw(Box::new(CCpuLimitList {
                    limits: std::ptr::null_mut(),
                    count: 0,
                }));
            }
            
            let mut c_limits = Vec::with_capacity(count);
            
            for limit in limits {
                let limit_type = match limit.limit_type {
                    LimitType::Nice => 0,
                    LimitType::Affinity => 1,
                    LimitType::CpuLimit => 2,
                    LimitType::Combined => 3,
                };
                
                c_limits.push(CCpuLimit {
                    pid: limit.pid,
                    max_cpu_percent: limit.max_cpu_percent,
                    nice_value: limit.nice_value,
                    limit_type,
                });
            }
            
            let mut c_limits = c_limits.into_boxed_slice();
            let limits_ptr = c_limits.as_mut_ptr();
            
            let list = Box::new(CCpuLimitList {
                limits: limits_ptr,
                count,
            });
            
            std::mem::forget(c_limits);
            Box::into_raw(list)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn free_cpu_limits(list: *mut CCpuLimitList) {
    if !list.is_null() {
        unsafe {
            let list = Box::from_raw(list);
            if !list.limits.is_null() && list.count > 0 {
                let _ = Vec::from_raw_parts(list.limits, list.count, list.count);
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn has_process_limit(pid: u32) -> u8 {
    use once_cell::sync::Lazy;
    use std::sync::Mutex;
    
    static LIMITER: Lazy<Mutex<ProcessCpuLimiter>> = Lazy::new(|| {
        Mutex::new(ProcessCpuLimiter::new())
    });
    
    match LIMITER.lock() {
        Ok(limiter) => {
            if limiter.has_limit(pid) { 1 } else { 0 }
        }
        Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nice_calculation() {
        let limiter = ProcessCpuLimiter::new();
        
        assert_eq!(limiter.calculate_nice_from_limit(80.0), 0);
        assert_eq!(limiter.calculate_nice_from_limit(60.0), 5);
        assert_eq!(limiter.calculate_nice_from_limit(30.0), 10);
        assert_eq!(limiter.calculate_nice_from_limit(15.0), 15);
        assert_eq!(limiter.calculate_nice_from_limit(5.0), 19);
    }

    #[test]
    fn test_core_calculation() {
        let limiter = ProcessCpuLimiter::new();
        
        assert_eq!(limiter.calculate_allowed_cores(100.0, 8), 8);
        assert_eq!(limiter.calculate_allowed_cores(50.0, 8), 4);
        assert_eq!(limiter.calculate_allowed_cores(25.0, 8), 2);
        assert_eq!(limiter.calculate_allowed_cores(10.0, 8), 1);
    }

    #[test]
    fn test_cpu_count() {
        let limiter = ProcessCpuLimiter::new();
        let cores = limiter.get_cpu_count();
        assert!(cores.is_ok());
        assert!(cores.unwrap() > 0);
    }
}