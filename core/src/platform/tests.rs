//! Platform abstraction tests

#[cfg(test)]
mod tests {
    use super::super::*;
    
    #[test]
    fn test_platform_capabilities() {
        let caps = get_platform_capabilities();
        
        // Basic capabilities should be available
        assert!(caps.can_kill_processes);
        assert!(caps.can_suspend_processes);
        assert!(caps.can_set_priority);
        
        #[cfg(target_os = "macos")]
        {
            assert!(caps.has_temperature_sensors);
            assert!(caps.supports_process_groups);
        }
        
        #[cfg(target_os = "windows")]
        {
            assert!(caps.has_temperature_sensors);
            assert!(!caps.supports_process_groups);
            assert!(caps.requires_elevation);
        }
    }
    
    #[test]
    fn test_process_status_conversion() {
        assert_eq!(ProcessStatus::Running.as_str(), "Running");
        assert_eq!(ProcessStatus::Zombie.as_str(), "Zombie");
        assert_eq!(ProcessStatus::Stopped.as_str(), "Stopped");
    }
    
    #[test]
    fn test_platform_error_display() {
        let err = PlatformError::ProcessNotFound(123);
        assert_eq!(format!("{}", err), "Process 123 not found");
        
        let err = PlatformError::PermissionDenied("test".to_string());
        assert_eq!(format!("{}", err), "Permission denied: test");
        
        let err = PlatformError::ProcessUnkillable("kernel".to_string());
        assert_eq!(format!("{}", err), "Process unkillable: kernel");
    }
    
    #[cfg(target_os = "macos")]
    #[test]
    fn test_macos_platform_creation() {
        use super::super::macos::MacOSPlatform;
        
        let platform = MacOSPlatform::new();
        
        // Test that we can get references to managers
        let _pm = platform.process_manager();
        let _sm = platform.system_monitor();
        let _ko = platform.kernel_ops();
    }
    
    #[cfg(target_os = "macos")]
    #[test]
    fn test_kernel_process_detection() {
        use super::super::macos::MacOSKernelOps;
        
        let kernel_ops = MacOSKernelOps::new();
        
        // PID 0 is kernel_task
        assert!(kernel_ops.is_kernel_process(0));
        
        // PID 1 is launchd
        assert!(kernel_ops.is_kernel_process(1));
        
        // Regular PIDs should not be kernel processes
        assert!(!kernel_ops.is_kernel_process(9999));
    }
    
    #[cfg(target_os = "macos")]
    #[test]
    fn test_system_metrics() {
        use super::super::macos::MacOSSystemMonitor;
        
        let monitor = MacOSSystemMonitor::new();
        
        // Get system metrics
        let metrics = monitor.get_system_metrics();
        assert!(metrics.is_ok());
        
        let metrics = metrics.unwrap();
        
        // Basic sanity checks
        assert!(metrics.cpu_count > 0);
        assert!(metrics.memory_total_bytes > 0);
        assert!(metrics.memory_used_bytes > 0);
        assert!(metrics.memory_used_bytes <= metrics.memory_total_bytes);
    }
}