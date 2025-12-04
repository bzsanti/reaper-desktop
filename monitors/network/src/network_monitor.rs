use crate::connection_tracker::{ConnectionTracker, NetworkConnection};
use crate::bandwidth_monitor::{BandwidthMonitor, BandwidthStats};
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct NetworkMetrics {
    pub connections: Vec<NetworkConnection>,
    pub bandwidth: BandwidthStats,
    pub total_bytes_sent: u64,
    pub total_bytes_received: u64,
    pub packets_sent: u64,
    pub packets_received: u64,
    pub active_interfaces: Vec<String>,
}

pub struct NetworkMonitor {
    connection_tracker: ConnectionTracker,
    bandwidth_monitor: BandwidthMonitor,
    last_update: Instant,
    cache_duration: Duration,
    cached_metrics: Option<NetworkMetrics>,
}

impl NetworkMonitor {
    pub fn new() -> Self {
        Self {
            connection_tracker: ConnectionTracker::new(),
            bandwidth_monitor: BandwidthMonitor::new(),
            last_update: Instant::now(),
            cache_duration: Duration::from_millis(1500), // 1.5 second cache
            cached_metrics: None,
        }
    }
    
    pub fn get_metrics(&mut self) -> NetworkMetrics {
        // Use cache if available and fresh
        if let Some(ref metrics) = self.cached_metrics {
            if self.last_update.elapsed() < self.cache_duration {
                return metrics.clone();
            }
        }
        
        // Refresh all data
        let connections = self.connection_tracker.get_connections();
        let bandwidth = self.bandwidth_monitor.get_current_bandwidth();
        let interface_stats = self.bandwidth_monitor.get_interface_stats();
        
        // Calculate totals
        let (total_sent, total_received, packets_sent, packets_received) = 
            self.calculate_totals(&interface_stats);
        
        // Get active interfaces
        let active_interfaces = interface_stats
            .iter()
            .filter(|i| i.is_active)
            .map(|i| i.name.clone())
            .collect();
        
        let metrics = NetworkMetrics {
            connections,
            bandwidth,
            total_bytes_sent: total_sent,
            total_bytes_received: total_received,
            packets_sent,
            packets_received,
            active_interfaces,
        };
        
        // Update cache
        self.cached_metrics = Some(metrics.clone());
        self.last_update = Instant::now();
        
        metrics
    }
    
    pub fn get_connections_for_process(&mut self, pid: u32) -> Vec<NetworkConnection> {
        self.connection_tracker.get_connections_for_pid(pid)
    }
    
    pub fn get_bandwidth_for_process(&mut self, pid: u32) -> Option<(u64, u64)> {
        self.bandwidth_monitor.get_process_bandwidth(pid)
    }
    
    fn calculate_totals(&self, interfaces: &[crate::bandwidth_monitor::InterfaceStats]) 
        -> (u64, u64, u64, u64) 
    {
        let mut total_sent = 0u64;
        let mut total_received = 0u64;
        let mut packets_sent = 0u64;
        let mut packets_received = 0u64;
        
        for interface in interfaces {
            total_sent += interface.bytes_sent;
            total_received += interface.bytes_received;
            packets_sent += interface.packets_sent;
            packets_received += interface.packets_received;
        }
        
        (total_sent, total_received, packets_sent, packets_received)
    }
    
    pub fn refresh(&mut self) {
        // Force refresh by clearing cache
        self.cached_metrics = None;
        self.connection_tracker.refresh();
        self.bandwidth_monitor.refresh();
    }
}