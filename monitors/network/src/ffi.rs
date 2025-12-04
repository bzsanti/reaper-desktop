use crate::NETWORK_MONITOR;
use std::ffi::CString;
use std::os::raw::c_char;

#[repr(C)]
pub struct CNetworkConnection {
    pub pid: i32, // -1 for None
    pub process_name: *mut c_char,
    pub local_address: *mut c_char,
    pub local_port: u16,
    pub remote_address: *mut c_char,
    pub remote_port: u16,
    pub network_protocol: *mut c_char,
    pub state: *mut c_char,
    pub bytes_sent: u64,
    pub bytes_received: u64,
}

#[repr(C)]
pub struct CNetworkConnectionList {
    pub connections: *mut CNetworkConnection,
    pub count: usize,
}

#[repr(C)]
pub struct CBandwidthStats {
    pub current_upload_bps: u64,
    pub current_download_bps: u64,
    pub peak_upload_bps: u64,
    pub peak_download_bps: u64,
    pub average_upload_bps: u64,
    pub average_download_bps: u64,
}

#[repr(C)]
pub struct CNetworkMetrics {
    pub connections: CNetworkConnectionList,
    pub bandwidth: CBandwidthStats,
    pub total_bytes_sent: u64,
    pub total_bytes_received: u64,
    pub packets_sent: u64,
    pub packets_received: u64,
    pub active_interfaces: *mut *mut c_char,
    pub interface_count: usize,
}

/// Initialize the network monitor
#[no_mangle]
pub extern "C" fn network_monitor_init() {
    // Force initialization of the lazy static
    let _guard = NETWORK_MONITOR.lock().unwrap();
}

/// Get current network metrics
#[no_mangle]
pub extern "C" fn get_network_metrics() -> *mut CNetworkMetrics {
    let mut monitor = match NETWORK_MONITOR.lock() {
        Ok(m) => m,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let metrics = monitor.get_metrics();
    
    // Convert connections
    let connections_count = metrics.connections.len();
    let connections_ptr = if connections_count > 0 {
        let mut c_connections = Vec::with_capacity(connections_count);
        
        for conn in metrics.connections {
            c_connections.push(CNetworkConnection {
                pid: conn.pid.map(|p| p as i32).unwrap_or(-1),
                process_name: CString::new(conn.process_name).unwrap().into_raw(),
                local_address: CString::new(conn.local_address).unwrap().into_raw(),
                local_port: conn.local_port,
                remote_address: CString::new(conn.remote_address).unwrap().into_raw(),
                remote_port: conn.remote_port,
                network_protocol: CString::new(conn.protocol.display_name()).unwrap().into_raw(),
                state: CString::new(conn.state.display_name()).unwrap().into_raw(),
                bytes_sent: conn.bytes_sent,
                bytes_received: conn.bytes_received,
            });
        }
        
        let ptr = c_connections.as_mut_ptr();
        std::mem::forget(c_connections);
        ptr
    } else {
        std::ptr::null_mut()
    };
    
    // Convert interfaces
    let interface_count = metrics.active_interfaces.len();
    let interfaces_ptr = if interface_count > 0 {
        let mut c_interfaces = Vec::with_capacity(interface_count);
        
        for interface in metrics.active_interfaces {
            c_interfaces.push(CString::new(interface).unwrap().into_raw());
        }
        
        let ptr = c_interfaces.as_mut_ptr();
        std::mem::forget(c_interfaces);
        ptr
    } else {
        std::ptr::null_mut()
    };
    
    // Create metrics structure
    let c_metrics = Box::new(CNetworkMetrics {
        connections: CNetworkConnectionList {
            connections: connections_ptr,
            count: connections_count,
        },
        bandwidth: CBandwidthStats {
            current_upload_bps: metrics.bandwidth.current_upload_bps,
            current_download_bps: metrics.bandwidth.current_download_bps,
            peak_upload_bps: metrics.bandwidth.peak_upload_bps,
            peak_download_bps: metrics.bandwidth.peak_download_bps,
            average_upload_bps: metrics.bandwidth.average_upload_bps,
            average_download_bps: metrics.bandwidth.average_download_bps,
        },
        total_bytes_sent: metrics.total_bytes_sent,
        total_bytes_received: metrics.total_bytes_received,
        packets_sent: metrics.packets_sent,
        packets_received: metrics.packets_received,
        active_interfaces: interfaces_ptr,
        interface_count,
    });
    
    Box::into_raw(c_metrics)
}

/// Get connections for a specific process
#[no_mangle]
pub extern "C" fn get_process_connections(pid: u32) -> *mut CNetworkConnectionList {
    let mut monitor = match NETWORK_MONITOR.lock() {
        Ok(m) => m,
        Err(_) => return std::ptr::null_mut(),
    };
    
    let connections = monitor.get_connections_for_process(pid);
    let count = connections.len();
    
    let connections_ptr = if count > 0 {
        let mut c_connections = Vec::with_capacity(count);
        
        for conn in connections {
            c_connections.push(CNetworkConnection {
                pid: conn.pid.map(|p| p as i32).unwrap_or(-1),
                process_name: CString::new(conn.process_name).unwrap().into_raw(),
                local_address: CString::new(conn.local_address).unwrap().into_raw(),
                local_port: conn.local_port,
                remote_address: CString::new(conn.remote_address).unwrap().into_raw(),
                remote_port: conn.remote_port,
                network_protocol: CString::new(conn.protocol.display_name()).unwrap().into_raw(),
                state: CString::new(conn.state.display_name()).unwrap().into_raw(),
                bytes_sent: conn.bytes_sent,
                bytes_received: conn.bytes_received,
            });
        }
        
        let ptr = c_connections.as_mut_ptr();
        std::mem::forget(c_connections);
        ptr
    } else {
        std::ptr::null_mut()
    };
    
    let list = Box::new(CNetworkConnectionList {
        connections: connections_ptr,
        count,
    });
    
    Box::into_raw(list)
}

/// Get bandwidth stats for a specific process
#[no_mangle]
pub extern "C" fn get_process_bandwidth(pid: u32) -> CBandwidthStats {
    let mut monitor = match NETWORK_MONITOR.lock() {
        Ok(m) => m,
        Err(_) => {
            return CBandwidthStats {
                current_upload_bps: 0,
                current_download_bps: 0,
                peak_upload_bps: 0,
                peak_download_bps: 0,
                average_upload_bps: 0,
                average_download_bps: 0,
            }
        }
    };
    
    if let Some((upload, download)) = monitor.get_bandwidth_for_process(pid) {
        CBandwidthStats {
            current_upload_bps: upload,
            current_download_bps: download,
            peak_upload_bps: 0,
            peak_download_bps: 0,
            average_upload_bps: 0,
            average_download_bps: 0,
        }
    } else {
        CBandwidthStats {
            current_upload_bps: 0,
            current_download_bps: 0,
            peak_upload_bps: 0,
            peak_download_bps: 0,
            average_upload_bps: 0,
            average_download_bps: 0,
        }
    }
}

/// Free network metrics
#[no_mangle]
pub extern "C" fn free_network_metrics(metrics: *mut CNetworkMetrics) {
    if metrics.is_null() {
        return;
    }
    
    unsafe {
        let metrics = Box::from_raw(metrics);
        
        // Free connections
        if !metrics.connections.connections.is_null() {
            let connections = std::slice::from_raw_parts_mut(
                metrics.connections.connections,
                metrics.connections.count
            );
            
            for conn in connections {
                if !conn.process_name.is_null() {
                    let _ = CString::from_raw(conn.process_name);
                }
                if !conn.local_address.is_null() {
                    let _ = CString::from_raw(conn.local_address);
                }
                if !conn.remote_address.is_null() {
                    let _ = CString::from_raw(conn.remote_address);
                }
                if !conn.network_protocol.is_null() {
                    let _ = CString::from_raw(conn.network_protocol);
                }
                if !conn.state.is_null() {
                    let _ = CString::from_raw(conn.state);
                }
            }
            
            Vec::from_raw_parts(
                metrics.connections.connections,
                metrics.connections.count,
                metrics.connections.count
            );
        }
        
        // Free interfaces
        if !metrics.active_interfaces.is_null() {
            let interfaces = std::slice::from_raw_parts_mut(
                metrics.active_interfaces,
                metrics.interface_count
            );
            
            for interface in interfaces {
                if !interface.is_null() {
                    let _ = CString::from_raw(*interface);
                }
            }
            
            Vec::from_raw_parts(
                metrics.active_interfaces,
                metrics.interface_count,
                metrics.interface_count
            );
        }
    }
}

/// Free connection list
#[no_mangle]
pub extern "C" fn free_connection_list(list: *mut CNetworkConnectionList) {
    if list.is_null() {
        return;
    }
    
    unsafe {
        let list = Box::from_raw(list);
        
        if !list.connections.is_null() {
            let connections = std::slice::from_raw_parts_mut(
                list.connections,
                list.count
            );
            
            for conn in connections {
                if !conn.process_name.is_null() {
                    let _ = CString::from_raw(conn.process_name);
                }
                if !conn.local_address.is_null() {
                    let _ = CString::from_raw(conn.local_address);
                }
                if !conn.remote_address.is_null() {
                    let _ = CString::from_raw(conn.remote_address);
                }
                if !conn.network_protocol.is_null() {
                    let _ = CString::from_raw(conn.network_protocol);
                }
                if !conn.state.is_null() {
                    let _ = CString::from_raw(conn.state);
                }
            }
            
            Vec::from_raw_parts(
                list.connections,
                list.count,
                list.count
            );
        }
    }
}

/// Force refresh network data
#[no_mangle]
pub extern "C" fn refresh_network_data() {
    if let Ok(mut monitor) = NETWORK_MONITOR.lock() {
        monitor.refresh();
    }
}