use libc::{kill, pid_t, SIGKILL, SIGTERM, SIGSTOP, SIGCONT};
use sysinfo::{System, Pid, ProcessStatus};

#[derive(Debug)]
pub struct KernelInterface {
    system: System,
}

#[derive(Debug, Clone)]
pub struct TaskInfo {
    pub pid: u32,
    pub virtual_size: u64,
    pub resident_size: u64,
    pub user_time: f64,
    pub system_time: f64,
    pub suspend_count: u32,
}

#[derive(Debug, Clone)]
pub enum ProcessAction {
    Terminate,
    Kill,
    Suspend,
    Resume,
}

#[derive(Debug, Clone)]
pub enum ActionResult {
    Success(String),
    ProcessNotFound,
    PermissionDenied(String),
    ProcessUnkillable(String),
    AlreadyInState(String),
    UnknownError(String),
}


impl KernelInterface {
    pub fn new() -> Self {
        let mut system = System::new_all();
        system.refresh_all();
        KernelInterface { system }
    }
    
    pub fn execute_action(&mut self, pid: u32, action: ProcessAction) -> ActionResult {
        // Refresh process info
        self.system.refresh_process(Pid::from_u32(pid));
        
        // Check if process exists
        if !self.system.process(Pid::from_u32(pid)).is_some() {
            return ActionResult::ProcessNotFound;
        }
        
        // Check for protected processes
        if self.is_protected_process(pid) {
            return ActionResult::PermissionDenied(
                format!("Process {} is protected and cannot be modified", pid)
            );
        }
        
        match action {
            ProcessAction::Terminate => self.terminate_process_internal(pid),
            ProcessAction::Kill => self.force_kill_process_internal(pid),
            ProcessAction::Suspend => self.suspend_process_internal(pid),
            ProcessAction::Resume => self.resume_process_internal(pid),
        }
    }
    
    fn terminate_process_internal(&self, pid: u32) -> ActionResult {
        let result = unsafe { kill(pid as pid_t, SIGTERM) };
        
        if result == 0 {
            ActionResult::Success(format!("Process {} terminated successfully", pid))
        } else {
            self.handle_kill_error(pid, "terminate")
        }
    }
    
    fn force_kill_process_internal(&self, pid: u32) -> ActionResult {
        let result = unsafe { kill(pid as pid_t, SIGKILL) };
        
        if result == 0 {
            ActionResult::Success(format!("Process {} killed successfully", pid))
        } else {
            self.handle_kill_error(pid, "kill")
        }
    }
    
    fn suspend_process_internal(&self, pid: u32) -> ActionResult {
        let result = unsafe { kill(pid as pid_t, SIGSTOP) };
        
        if result == 0 {
            ActionResult::Success(format!("Process {} suspended successfully", pid))
        } else {
            self.handle_kill_error(pid, "suspend")
        }
    }
    
    fn resume_process_internal(&self, pid: u32) -> ActionResult {
        let result = unsafe { kill(pid as pid_t, SIGCONT) };
        
        if result == 0 {
            ActionResult::Success(format!("Process {} resumed successfully", pid))
        } else {
            self.handle_kill_error(pid, "resume")
        }
    }
    
    
    pub fn get_task_info(&self, pid: u32) -> Option<TaskInfo> {
        let process = self.system.process(Pid::from_u32(pid))?;
        
        Some(TaskInfo {
            pid,
            virtual_size: process.virtual_memory(),
            resident_size: process.memory(),
            user_time: process.cpu_usage() as f64,
            system_time: 0.0, // Would need more platform-specific code
            suspend_count: 0, // Would need mach-specific code on macOS
        })
    }
    
    fn handle_kill_error(&self, pid: u32, action: &str) -> ActionResult {
        let errno = unsafe { *libc::__error() };
        match errno {
            libc::ESRCH => ActionResult::ProcessNotFound,
            libc::EPERM => ActionResult::PermissionDenied(
                format!("Permission denied to {} process {}", action, pid)
            ),
            libc::EINVAL => ActionResult::UnknownError(
                format!("Invalid signal for {} operation", action)
            ),
            _ => {
                if self.is_kernel_process(pid) {
                    ActionResult::ProcessUnkillable(
                        format!("Process {} is a kernel process and cannot be modified", pid)
                    )
                } else if self.has_pending_io(pid) {
                    ActionResult::ProcessUnkillable(
                        format!("Process {} has pending I/O operations", pid)
                    )
                } else {
                    ActionResult::UnknownError(
                        format!("Failed to {} process {}: error code {}", action, pid, errno)
                    )
                }
            }
        }
    }
    
    fn is_kernel_process(&self, pid: u32) -> bool {
        // PID 0 is the kernel, PID 1 is launchd on macOS
        pid == 0 || pid == 1
    }
    
    fn is_protected_process(&self, pid: u32) -> bool {
        // Protect critical system processes
        match pid {
            0 | 1 => true, // kernel and launchd
            _ => {
                // Check if it's a system process by name
                if let Some(process) = self.system.process(Pid::from_u32(pid)) {
                    let name = process.name();
                    name == "kernel_task" || 
                    name == "launchd" || 
                    name == "systemd" ||
                    name == "WindowServer" ||
                    name == "loginwindow"
                } else {
                    false
                }
            }
        }
    }
    
    fn has_pending_io(&self, pid: u32) -> bool {
        // Check if process is in uninterruptible sleep (D state)
        if let Some(process) = self.system.process(Pid::from_u32(pid)) {
            matches!(process.status(), ProcessStatus::UninterruptibleDiskSleep)
        } else {
            false
        }
    }
    
    #[allow(dead_code)] // Reserved for future file descriptor monitoring feature
    fn count_open_files(&self, pid: u32) -> Option<usize> {
        // macOS specific: use lsof command or proc info
        // This is a simplified version
        #[cfg(target_os = "macos")]
        {
            use std::process::Command;
            
            let output = Command::new("lsof")
                .arg("-p")
                .arg(pid.to_string())
                .output()
                .ok()?;
            
            if output.status.success() {
                let lines = String::from_utf8_lossy(&output.stdout)
                    .lines()
                    .count();
                // Subtract 1 for header line
                Some(lines.saturating_sub(1))
            } else {
                Some(0)
            }
        }
        
        #[cfg(not(target_os = "macos"))]
        {
            None
        }
    }
}