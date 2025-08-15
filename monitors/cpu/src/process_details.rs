use std::collections::HashMap;
use std::process::Command;
use std::path::PathBuf;
use std::ffi::CStr;
use libc::{proc_pidpath, PROC_PIDPATHINFO_MAXSIZE};

#[derive(Debug, Clone)]
pub struct ProcessDetails {
    pub pid: u32,
    pub executable_path: String,
    pub arguments: Vec<String>,
    pub environment: HashMap<String, String>,
    pub open_files: Vec<String>,
    pub connections: Vec<String>,
    pub user: String,
    pub group: String,
}

impl ProcessDetails {
    pub fn new(pid: u32) -> Option<Self> {
        Some(ProcessDetails {
            pid,
            executable_path: get_process_path(pid).unwrap_or_default(),
            arguments: get_process_arguments(pid),
            environment: get_process_environment(pid),
            open_files: get_open_files(pid),
            connections: get_network_connections(pid),
            user: get_process_user(pid),
            group: get_process_group(pid),
        })
    }
}

/// Get the executable path for a process
fn get_process_path(pid: u32) -> Option<String> {
    let mut path_buf = vec![0u8; PROC_PIDPATHINFO_MAXSIZE as usize];
    
    unsafe {
        let ret = proc_pidpath(
            pid as i32,
            path_buf.as_mut_ptr() as *mut libc::c_void,
            PROC_PIDPATHINFO_MAXSIZE as u32,
        );
        
        if ret <= 0 {
            return None;
        }
        
        // Convert to string
        path_buf.truncate(ret as usize);
        String::from_utf8(path_buf).ok()
    }
}

/// Get command line arguments for a process
fn get_process_arguments(pid: u32) -> Vec<String> {
    // Use ps command to get arguments
    let output = match Command::new("ps")
        .args(&["-p", &pid.to_string(), "-o", "command="])
        .output() {
        Ok(o) => o,
        Err(_) => return vec![],
    };
    
    if output.status.success() {
        let cmd = String::from_utf8_lossy(&output.stdout);
        let cmd = cmd.trim();
        
        // Split by spaces (simple parsing, could be improved)
        cmd.split_whitespace()
            .map(|s| s.to_string())
            .collect()
    } else {
        vec![]
    }
}

/// Get environment variables for a process
fn get_process_environment(pid: u32) -> HashMap<String, String> {
    // This is more complex on macOS, requires elevated permissions
    // For now, return empty or basic env
    let mut env = HashMap::new();
    
    // Try to get basic info via ps
    if let Ok(output) = Command::new("ps")
        .args(&["-p", &pid.to_string(), "-E"])
        .output()
    {
        if output.status.success() {
            let env_str = String::from_utf8_lossy(&output.stdout);
            for line in env_str.lines().skip(1) {
                if let Some((key, value)) = line.split_once('=') {
                    env.insert(key.to_string(), value.to_string());
                }
            }
        }
    }
    
    env
}

/// Get open files for a process using lsof
fn get_open_files(pid: u32) -> Vec<String> {
    let output = match Command::new("lsof")
        .args(&["-p", &pid.to_string()])
        .output() {
        Ok(o) => o,
        Err(_) => return vec![],
    };
    
    if output.status.success() {
        let lsof_output = String::from_utf8_lossy(&output.stdout);
        let mut files = Vec::new();
        
        // Skip header line and parse output
        for line in lsof_output.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            
            // lsof output format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            if parts.len() >= 9 {
                let file_type = parts[4];
                let name = parts[8..].join(" ");
                
                // Filter for regular files, directories, and pipes
                if file_type == "REG" || file_type == "DIR" || file_type == "PIPE" {
                    files.push(name);
                }
            }
        }
        
        // Deduplicate and limit to reasonable number
        files.sort();
        files.dedup();
        files.truncate(50); // Limit to 50 files
        
        files
    } else {
        vec![]
    }
}

/// Get network connections for a process
fn get_network_connections(pid: u32) -> Vec<String> {
    let output = match Command::new("lsof")
        .args(&["-i", "-a", "-p", &pid.to_string()])
        .output() {
        Ok(o) => o,
        Err(_) => return vec![],
    };
    
    if output.status.success() {
        let lsof_output = String::from_utf8_lossy(&output.stdout);
        let mut connections = Vec::new();
        
        for line in lsof_output.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            
            if parts.len() >= 9 {
                let name = parts[8..].join(" ");
                
                // Parse connection info (e.g., "TCP localhost:8080->localhost:53234 (ESTABLISHED)")
                if name.contains("TCP") || name.contains("UDP") {
                    connections.push(name);
                }
            }
        }
        
        connections.truncate(20); // Limit to 20 connections
        connections
    } else {
        vec![]
    }
}

/// Get the user that owns the process
fn get_process_user(pid: u32) -> String {
    if let Ok(output) = Command::new("ps")
        .args(&["-p", &pid.to_string(), "-o", "user="])
        .output()
    {
        if output.status.success() {
            return String::from_utf8_lossy(&output.stdout).trim().to_string();
        }
    }
    
    "unknown".to_string()
}

/// Get the group that owns the process
fn get_process_group(pid: u32) -> String {
    if let Ok(output) = Command::new("ps")
        .args(&["-p", &pid.to_string(), "-o", "group="])
        .output()
    {
        if output.status.success() {
            return String::from_utf8_lossy(&output.stdout).trim().to_string();
        }
    }
    
    "unknown".to_string()
}