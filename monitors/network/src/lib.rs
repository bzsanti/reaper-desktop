use once_cell::sync::Lazy;
use std::sync::Mutex;

pub mod network_monitor;
pub mod connection_tracker;
pub mod bandwidth_monitor;
pub mod ffi;

// Re-export main types
pub use network_monitor::{NetworkMonitor, NetworkMetrics};
pub use connection_tracker::{NetworkConnection, ConnectionState, Protocol};
pub use bandwidth_monitor::{BandwidthStats, InterfaceStats};

// Global network monitor instance
static NETWORK_MONITOR: Lazy<Mutex<NetworkMonitor>> = Lazy::new(|| {
    Mutex::new(NetworkMonitor::new())
});