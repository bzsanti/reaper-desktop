//! macOS process management implementation

use crate::platform::{
    ProcessInfo, ProcessManager, ProcessStatus, PlatformError, PlatformResult, Signal,
};
use sysinfo::{System, Process, Pid, ProcessRefreshKind};

pub struct MacOSProcessManager {
    system: std::sync::Mutex<System>,
}

impl MacOSProcessManager {
    pub fn new() -> Self {
        Self {
            system: std::sync::Mutex::new(System::new()),
        }
    }
    
    fn convert_process_info(&self, pid: &Pid, process: &Process) -> ProcessInfo {
        ProcessInfo {
            pid: pid.as_u32(),
            name: process.name().to_string(),
            cpu_usage: process.cpu_usage(),
            memory_bytes: process.memory() * 1024,  // Convert KB to bytes
            virtual_memory_bytes: process.virtual_memory() * 1024,
            status: self.convert_status(process.status()),
            parent_pid: process.parent().map(|p| p.as_u32()),
            thread_count: process.tasks().map(|t| t.len()).unwrap_or(0),
            run_time_seconds: process.run_time(),
            user_time_seconds: 0.0,  // TODO: Requires process times API
            system_time_seconds: 0.0,  // TODO: Requires process times API
            executable_path: process.exe().map(|p| p.to_string_lossy().to_string()),
            command_line: process.cmd().to_vec(),
            environment: process.environ().iter()
                .map(|s| {
                    let parts: Vec<&str> = s.splitn(2, '=').collect();
                    if parts.len() == 2 {
                        (parts[0].to_string(), parts[1].to_string())
                    } else {
                        (s.to_string(), String::new())
                    }
                })
                .collect(),
            
            // Advanced analysis fields - defaults for now, will implement properly
            io_wait_time_ms: 0,
            context_switches: 0,
            minor_faults: 0,
            major_faults: 0,
            priority: 0,  // TODO: Get actual priority
            is_unkillable: matches!(process.status(), sysinfo::ProcessStatus::UninterruptibleDiskSleep),
            last_signal_response_ms: None,
        }
    }
    
    fn convert_status(&self, status: sysinfo::ProcessStatus) -> ProcessStatus {
        match status {
            sysinfo::ProcessStatus::Run => ProcessStatus::Running,
            sysinfo::ProcessStatus::Sleep => ProcessStatus::Sleeping,
            sysinfo::ProcessStatus::Stop => ProcessStatus::Stopped,
            sysinfo::ProcessStatus::Zombie => ProcessStatus::Zombie,
            sysinfo::ProcessStatus::Idle => ProcessStatus::Idle,
            sysinfo::ProcessStatus::UninterruptibleDiskSleep => ProcessStatus::UninterruptibleSleep,
            _ => ProcessStatus::Unknown,
        }
    }
}

impl ProcessManager for MacOSProcessManager {
    fn list_processes(&self) -> PlatformResult<Vec<ProcessInfo>> {
        let mut system = self.system.lock().unwrap();
        system.refresh_processes();
        
        let processes: Vec<ProcessInfo> = system.processes()
            .iter()
            .map(|(pid, process)| self.convert_process_info(pid, process))
            .collect();
        
        Ok(processes)
    }
    
    fn get_process_info(&self, pid: u32) -> PlatformResult<ProcessInfo> {
        let mut system = self.system.lock().unwrap();
        let pid = Pid::from(pid as usize);
        
        system.refresh_process_specifics(pid, ProcessRefreshKind::everything());
        
        system.process(pid)
            .map(|process| self.convert_process_info(&pid, process))
            .ok_or_else(|| PlatformError::ProcessNotFound(pid.as_u32()))
    }
    
    fn send_signal(&self, pid: u32, signal: Signal) -> PlatformResult<()> {
        use libc::{kill, pid_t, SIGTERM, SIGKILL, SIGSTOP, SIGCONT, SIGINT};
        
        let sig = match signal {
            Signal::Terminate => SIGTERM,
            Signal::Kill => SIGKILL,
            Signal::Stop => SIGSTOP,
            Signal::Continue => SIGCONT,
            Signal::Interrupt => SIGINT,
        };
        
        let result = unsafe { kill(pid as pid_t, sig) };
        
        if result == 0 {
            Ok(())
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EPERM => Err(PlatformError::PermissionDenied(
                    format!("Cannot send signal to process {}", pid)
                )),
                _ => Err(PlatformError::SystemCallFailed(
                    format!("kill() failed with errno {}", errno)
                )),
            }
        }
    }
    
    fn is_process_responsive(&self, pid: u32) -> PlatformResult<bool> {
        // On macOS, check if process is in uninterruptible sleep
        let system = self.system.lock().unwrap();
        let pid = Pid::from(pid as usize);
        
        system.process(pid)
            .map(|process| {
                // Process is responsive if it's not in uninterruptible sleep
                !matches!(process.status(), sysinfo::ProcessStatus::UninterruptibleDiskSleep)
            })
            .ok_or_else(|| PlatformError::ProcessNotFound(pid.as_u32()))
    }
    
    fn get_child_processes(&self, parent_pid: u32) -> PlatformResult<Vec<u32>> {
        let system = self.system.lock().unwrap();
        let parent = Pid::from(parent_pid as usize);
        
        let children: Vec<u32> = system.processes()
            .iter()
            .filter_map(|(pid, process)| {
                if process.parent() == Some(parent) {
                    Some(pid.as_u32())
                } else {
                    None
                }
            })
            .collect();
        
        Ok(children)
    }
    
    fn can_terminate_process(&self, pid: u32) -> PlatformResult<bool> {
        // Check if it's a critical system process
        if pid == 0 || pid == 1 {
            return Ok(false);  // kernel and launchd
        }
        
        // Check if we have permission
        use libc::{kill, pid_t};
        let result = unsafe { kill(pid as pid_t, 0) };
        
        if result == 0 {
            Ok(true)
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EPERM => Ok(false),  // Process exists but we can't kill it
                _ => Ok(false),
            }
        }
    }
}