use libc::{kill, pid_t, SIGKILL, SIGTERM, SIGSTOP, SIGCONT};

#[derive(Debug)]
pub struct KernelInterface;

#[derive(Debug, Clone)]
pub struct TaskInfo {
    pub pid: u32,
    pub virtual_size: u64,
    pub resident_size: u64,
    pub user_time: f64,
    pub system_time: f64,
    pub suspend_count: u32,
}

#[derive(Debug)]
pub enum KillResult {
    Success,
    ProcessNotFound,
    PermissionDenied,
    ProcessUnkillable(String),
    UnknownError(i32),
}

impl KernelInterface {
    pub fn new() -> Self {
        KernelInterface
    }
    
    pub fn force_kill_process(&self, pid: u32) -> KillResult {
        let result = unsafe { kill(pid as pid_t, SIGKILL) };
        
        if result == 0 {
            KillResult::Success
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => KillResult::ProcessNotFound,
                libc::EPERM => KillResult::PermissionDenied,
                libc::EINVAL => KillResult::UnknownError(errno),
                _ => {
                    if self.is_kernel_process(pid) {
                        KillResult::ProcessUnkillable("Kernel process cannot be killed".to_string())
                    } else if self.has_pending_io(pid) {
                        KillResult::ProcessUnkillable("Process has pending I/O operations".to_string())
                    } else {
                        KillResult::UnknownError(errno)
                    }
                }
            }
        }
    }
    
    pub fn terminate_process(&self, pid: u32) -> KillResult {
        let result = unsafe { kill(pid as pid_t, SIGTERM) };
        
        if result == 0 {
            KillResult::Success
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => KillResult::ProcessNotFound,
                libc::EPERM => KillResult::PermissionDenied,
                _ => KillResult::UnknownError(errno),
            }
        }
    }
    
    pub fn get_task_info(&self, _pid: u32) -> Option<TaskInfo> {
        None
    }
    
    pub fn suspend_process(&self, pid: u32) -> bool {
        unsafe {
            let result = kill(pid as pid_t, libc::SIGSTOP);
            result == 0
        }
    }
    
    pub fn resume_process(&self, pid: u32) -> bool {
        unsafe {
            let result = kill(pid as pid_t, libc::SIGCONT);
            result == 0
        }
    }
    
    fn is_kernel_process(&self, pid: u32) -> bool {
        pid == 0 || pid == 1
    }
    
    fn has_pending_io(&self, _pid: u32) -> bool {
        false
    }
}