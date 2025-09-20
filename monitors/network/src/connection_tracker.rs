use std::process::Command;
use std::collections::HashMap;
use regex::Regex;

#[derive(Debug, Clone, PartialEq)]
pub enum Protocol {
    TCP,
    UDP,
    TCP6,
    UDP6,
    Other(String),
}

#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionState {
    Established,
    Listen,
    SynSent,
    SynReceived,
    FinWait1,
    FinWait2,
    TimeWait,
    CloseWait,
    LastAck,
    Closing,
    Closed,
    Unknown,
}

#[derive(Debug, Clone)]
pub struct NetworkConnection {
    pub pid: Option<u32>,
    pub process_name: String,
    pub local_address: String,
    pub local_port: u16,
    pub remote_address: String,
    pub remote_port: u16,
    pub protocol: Protocol,
    pub state: ConnectionState,
    pub bytes_sent: u64,
    pub bytes_received: u64,
}

pub struct ConnectionTracker {
    connections: Vec<NetworkConnection>,
    process_map: HashMap<u32, String>, // pid -> process name
}

impl ConnectionTracker {
    pub fn new() -> Self {
        Self {
            connections: Vec::new(),
            process_map: HashMap::new(),
        }
    }
    
    pub fn get_connections(&mut self) -> Vec<NetworkConnection> {
        self.refresh();
        self.connections.clone()
    }
    
    pub fn get_connections_for_pid(&mut self, pid: u32) -> Vec<NetworkConnection> {
        self.refresh();
        self.connections
            .iter()
            .filter(|c| c.pid == Some(pid))
            .cloned()
            .collect()
    }
    
    pub fn refresh(&mut self) {
        // Clear existing data
        self.connections.clear();
        self.process_map.clear();
        
        // Get connections from netstat
        self.parse_netstat();
        
        // Map connections to processes using lsof
        self.map_processes_with_lsof();
    }
    
    fn parse_netstat(&mut self) {
        // Run netstat to get all connections
        let output = Command::new("netstat")
            .args(&["-anv"])
            .output();
        
        if let Ok(output) = output {
            let stdout = String::from_utf8_lossy(&output.stdout);
            
            // Parse TCP connections
            self.parse_tcp_connections(&stdout);
            
            // Parse UDP connections
            self.parse_udp_connections(&stdout);
        }
    }
    
    fn parse_tcp_connections(&mut self, netstat_output: &str) {
        // Regex for TCP connections
        // Example: tcp4       0      0  127.0.0.1.6942         127.0.0.1.52389        ESTABLISHED
        let tcp_regex = Regex::new(
            r"(tcp[46]?)\s+\d+\s+\d+\s+([\d\.\:]+)\.(\d+)\s+([\d\.\:]+|\*)\.(\d+|\*)\s+(\w+)"
        ).unwrap();
        
        for line in netstat_output.lines() {
            if let Some(captures) = tcp_regex.captures(line) {
                let protocol = match &captures[1] {
                    "tcp" | "tcp4" => Protocol::TCP,
                    "tcp6" => Protocol::TCP6,
                    _ => continue,
                };
                
                let local_addr = captures[2].to_string();
                let local_port = captures[3].parse::<u16>().unwrap_or(0);
                let remote_addr = captures[4].to_string();
                let remote_port = if &captures[5] == "*" {
                    0
                } else {
                    captures[5].parse::<u16>().unwrap_or(0)
                };
                
                let state = self.parse_state(&captures[6]);
                
                self.connections.push(NetworkConnection {
                    pid: None,
                    process_name: String::new(),
                    local_address: local_addr,
                    local_port,
                    remote_address: remote_addr,
                    remote_port,
                    protocol,
                    state,
                    bytes_sent: 0,
                    bytes_received: 0,
                });
            }
        }
    }
    
    fn parse_udp_connections(&mut self, netstat_output: &str) {
        // Regex for UDP connections
        let udp_regex = Regex::new(
            r"(udp[46]?)\s+\d+\s+\d+\s+([\d\.\:]+)\.(\d+)\s+([\d\.\:]+|\*)\.(\d+|\*)"
        ).unwrap();
        
        for line in netstat_output.lines() {
            if let Some(captures) = udp_regex.captures(line) {
                let protocol = match &captures[1] {
                    "udp" | "udp4" => Protocol::UDP,
                    "udp6" => Protocol::UDP6,
                    _ => continue,
                };
                
                let local_addr = captures[2].to_string();
                let local_port = captures[3].parse::<u16>().unwrap_or(0);
                let remote_addr = if &captures[4] == "*" {
                    "*".to_string()
                } else {
                    captures[4].to_string()
                };
                let remote_port = if &captures[5] == "*" {
                    0
                } else {
                    captures[5].parse::<u16>().unwrap_or(0)
                };
                
                self.connections.push(NetworkConnection {
                    pid: None,
                    process_name: String::new(),
                    local_address: local_addr,
                    local_port,
                    remote_address: remote_addr,
                    remote_port,
                    protocol,
                    state: ConnectionState::Established, // UDP doesn't have states
                    bytes_sent: 0,
                    bytes_received: 0,
                });
            }
        }
    }
    
    fn map_processes_with_lsof(&mut self) {
        // Run lsof to get process information for network connections
        let output = Command::new("lsof")
            .args(&["-i", "-n", "-P"])
            .output();
        
        if let Ok(output) = output {
            let stdout = String::from_utf8_lossy(&output.stdout);
            
            // Parse lsof output
            // Example: COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
            //          firefox   12345   user   45u  IPv4 0x1234567890abcdef      0t0  TCP 192.168.1.2:54321->93.184.216.34:443 (ESTABLISHED)
            
            for line in stdout.lines().skip(1) { // Skip header
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 9 {
                    let process_name = parts[0].to_string();
                    if let Ok(pid) = parts[1].parse::<u32>() {
                        self.process_map.insert(pid, process_name.clone());
                        
                        // Try to match this with our connections
                        if let Some(connection_info) = parts.last() {
                            self.match_connection_with_process(pid, process_name, connection_info);
                        }
                    }
                }
            }
        }
    }
    
    fn match_connection_with_process(&mut self, pid: u32, process_name: String, connection_str: &str) {
        // Parse connection string like "192.168.1.2:54321->93.184.216.34:443"
        if let Some(arrow_pos) = connection_str.find("->") {
            let local_part = &connection_str[..arrow_pos];
            let remote_part = &connection_str[arrow_pos + 2..];
            
            // Parse local address and port
            if let Some(colon_pos) = local_part.rfind(':') {
                let local_port = local_part[colon_pos + 1..]
                    .parse::<u16>()
                    .unwrap_or(0);
                
                // Parse remote address and port
                if let Some(remote_colon) = remote_part.rfind(':') {
                    let remote_port = remote_part[remote_colon + 1..]
                        .split('(') // Remove state info like "(ESTABLISHED)"
                        .next()
                        .and_then(|s| s.parse::<u16>().ok())
                        .unwrap_or(0);
                    
                    // Find matching connection and update it
                    for conn in &mut self.connections {
                        if conn.local_port == local_port && conn.remote_port == remote_port {
                            conn.pid = Some(pid);
                            conn.process_name = process_name.clone();
                            break;
                        }
                    }
                }
            }
        } else if connection_str.contains(':') {
            // Handle LISTEN connections (no remote address)
            if let Some(colon_pos) = connection_str.rfind(':') {
                let port = connection_str[colon_pos + 1..]
                    .parse::<u16>()
                    .unwrap_or(0);
                
                // Find matching LISTEN connection
                for conn in &mut self.connections {
                    if conn.local_port == port && conn.state == ConnectionState::Listen {
                        conn.pid = Some(pid);
                        conn.process_name = process_name.clone();
                        break;
                    }
                }
            }
        }
    }
    
    fn parse_state(&self, state_str: &str) -> ConnectionState {
        match state_str.to_uppercase().as_str() {
            "ESTABLISHED" => ConnectionState::Established,
            "LISTEN" => ConnectionState::Listen,
            "SYN_SENT" => ConnectionState::SynSent,
            "SYN_RECEIVED" | "SYN_RCVD" => ConnectionState::SynReceived,
            "FIN_WAIT_1" | "FIN_WAIT1" => ConnectionState::FinWait1,
            "FIN_WAIT_2" | "FIN_WAIT2" => ConnectionState::FinWait2,
            "TIME_WAIT" => ConnectionState::TimeWait,
            "CLOSE_WAIT" => ConnectionState::CloseWait,
            "LAST_ACK" => ConnectionState::LastAck,
            "CLOSING" => ConnectionState::Closing,
            "CLOSED" => ConnectionState::Closed,
            _ => ConnectionState::Unknown,
        }
    }
}

impl Protocol {
    pub fn display_name(&self) -> &str {
        match self {
            Protocol::TCP => "TCP",
            Protocol::UDP => "UDP",
            Protocol::TCP6 => "TCP6",
            Protocol::UDP6 => "UDP6",
            Protocol::Other(name) => name,
        }
    }
}

impl ConnectionState {
    pub fn display_name(&self) -> &str {
        match self {
            ConnectionState::Established => "Established",
            ConnectionState::Listen => "Listen",
            ConnectionState::SynSent => "SYN Sent",
            ConnectionState::SynReceived => "SYN Received",
            ConnectionState::FinWait1 => "FIN Wait 1",
            ConnectionState::FinWait2 => "FIN Wait 2",
            ConnectionState::TimeWait => "Time Wait",
            ConnectionState::CloseWait => "Close Wait",
            ConnectionState::LastAck => "Last ACK",
            ConnectionState::Closing => "Closing",
            ConnectionState::Closed => "Closed",
            ConnectionState::Unknown => "Unknown",
        }
    }
    
    pub fn color(&self) -> &str {
        match self {
            ConnectionState::Established => "green",
            ConnectionState::Listen => "blue",
            ConnectionState::SynSent | ConnectionState::SynReceived => "yellow",
            ConnectionState::TimeWait | ConnectionState::CloseWait => "orange",
            ConnectionState::Closed | ConnectionState::LastAck | 
            ConnectionState::FinWait1 | ConnectionState::FinWait2 => "gray",
            _ => "secondary",
        }
    }
}