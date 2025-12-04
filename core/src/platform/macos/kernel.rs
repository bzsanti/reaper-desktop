//! macOS kernel operations implementation

use crate::platform::{KernelOperations, PlatformError, PlatformResult};
use libc::{kill, pid_t, SIGKILL, SIGSTOP, SIGCONT, getpriority, setpriority};

pub struct MacOSKernelOps;

impl MacOSKernelOps {
    pub fn new() -> Self {
        Self
    }
}

impl KernelOperations for MacOSKernelOps {
    fn force_kill(&self, pid: u32) -> PlatformResult<()> {
        let result = unsafe { kill(pid as pid_t, SIGKILL) };
        
        if result == 0 {
            Ok(())
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EPERM => Err(PlatformError::PermissionDenied(
                    format!("Cannot kill process {}", pid)
                )),
                _ => {
                    if self.is_kernel_process(pid) {
                        Err(PlatformError::ProcessUnkillable(
                            "Kernel process cannot be killed".to_string()
                        ))
                    } else {
                        Err(PlatformError::SystemCallFailed(
                            format!("kill() failed with errno {}", errno)
                        ))
                    }
                }
            }
        }
    }
    
    fn suspend_process(&self, pid: u32) -> PlatformResult<()> {
        let result = unsafe { kill(pid as pid_t, SIGSTOP) };
        
        if result == 0 {
            Ok(())
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EPERM => Err(PlatformError::PermissionDenied(
                    format!("Cannot suspend process {}", pid)
                )),
                _ => Err(PlatformError::SystemCallFailed(
                    format!("kill(SIGSTOP) failed with errno {}", errno)
                )),
            }
        }
    }
    
    fn resume_process(&self, pid: u32) -> PlatformResult<()> {
        let result = unsafe { kill(pid as pid_t, SIGCONT) };
        
        if result == 0 {
            Ok(())
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EPERM => Err(PlatformError::PermissionDenied(
                    format!("Cannot resume process {}", pid)
                )),
                _ => Err(PlatformError::SystemCallFailed(
                    format!("kill(SIGCONT) failed with errno {}", errno)
                )),
            }
        }
    }
    
    fn is_kernel_process(&self, pid: u32) -> bool {
        // On macOS, kernel_task has PID 0, launchd has PID 1
        pid == 0 || pid == 1
    }
    
    fn get_process_priority(&self, pid: u32) -> PlatformResult<i32> {
        let priority = unsafe { 
            getpriority(libc::PRIO_PROCESS, pid as libc::id_t) 
        };
        
        // getpriority returns -1 on error, but -1 is also a valid priority
        // So we need to check errno
        let errno = unsafe { *libc::__error() };
        if errno != 0 && priority == -1 {
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EINVAL => Err(PlatformError::SystemCallFailed(
                    "Invalid priority class".to_string()
                )),
                _ => Err(PlatformError::SystemCallFailed(
                    format!("getpriority() failed with errno {}", errno)
                )),
            }
        } else {
            Ok(priority)
        }
    }
    
    fn set_process_priority(&self, pid: u32, priority: i32) -> PlatformResult<()> {
        // Priority on Unix ranges from -20 (highest) to 19 (lowest)
        let clamped_priority = priority.clamp(-20, 19);
        
        let result = unsafe {
            setpriority(libc::PRIO_PROCESS, pid as libc::id_t, clamped_priority)
        };
        
        if result == 0 {
            Ok(())
        } else {
            let errno = unsafe { *libc::__error() };
            match errno {
                libc::ESRCH => Err(PlatformError::ProcessNotFound(pid)),
                libc::EPERM => Err(PlatformError::PermissionDenied(
                    format!("Cannot set priority for process {}", pid)
                )),
                libc::EACCES => Err(PlatformError::PermissionDenied(
                    "Insufficient privileges to set priority".to_string()
                )),
                _ => Err(PlatformError::SystemCallFailed(
                    format!("setpriority() failed with errno {}", errno)
                )),
            }
        }
    }
}