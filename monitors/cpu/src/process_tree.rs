use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use sysinfo::System;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessTreeNode {
    pub pid: u32,
    pub name: String,
    pub command: Vec<String>,  // Full command with arguments
    pub executable_path: String,
    pub cpu_usage: f32,
    pub memory_mb: f64,
    pub status: String,
    pub thread_count: usize,
    pub children: Vec<ProcessTreeNode>,
    
    // Aggregated metrics for this process and all its descendants
    pub total_cpu_usage: f32,
    pub total_memory_mb: f64,
    pub descendant_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessTree {
    pub roots: Vec<ProcessTreeNode>,
    pub total_processes: usize,
}

pub struct ProcessTreeBuilder {
    system: System,
}

impl ProcessTreeBuilder {
    pub fn new() -> Self {
        let mut system = System::new();
        system.refresh_all();
        ProcessTreeBuilder { system }
    }
    
    pub fn build_tree(&mut self) -> ProcessTree {
        self.system.refresh_processes();
        
        // Collect all processes first
        let mut all_processes: HashMap<u32, ProcessTreeNode> = HashMap::new();
        let mut parent_to_children: HashMap<u32, Vec<u32>> = HashMap::new();
        let mut root_pids: HashSet<u32> = HashSet::new();
        
        // First pass: create all nodes
        for (pid, process) in self.system.processes() {
            let pid_u32 = pid.as_u32();
            
            // Get command with arguments
            let command = process.cmd().to_vec();
            let executable_path = process.exe()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|| process.name().to_string());
            
            let node = ProcessTreeNode {
                pid: pid_u32,
                name: process.name().to_string(),
                command: command.iter().map(|s| s.to_string()).collect(),
                executable_path,
                cpu_usage: process.cpu_usage(),
                memory_mb: process.memory() as f64 / 1024.0,
                status: format!("{:?}", process.status()),
                thread_count: 0, // thread_count method not available in current sysinfo version
                children: Vec::new(),
                total_cpu_usage: process.cpu_usage(),
                total_memory_mb: process.memory() as f64 / 1024.0,
                descendant_count: 0,
            };
            
            all_processes.insert(pid_u32, node);
            
            // Track parent-child relationships
            if let Some(parent_pid) = process.parent() {
                let parent_u32 = parent_pid.as_u32();
                parent_to_children.entry(parent_u32).or_insert_with(Vec::new).push(pid_u32);
            } else {
                root_pids.insert(pid_u32);
            }
        }
        
        // Second pass: build tree structure
        let tree_nodes: HashMap<u32, ProcessTreeNode> = HashMap::new();
        
        // Build tree recursively from roots
        let mut roots = Vec::new();
        for root_pid in &root_pids {
            if let Some(root_node) = all_processes.get(root_pid) {
                let built_node = self.build_node_recursive(
                    root_node.clone(),
                    &all_processes,
                    &parent_to_children,
                    &mut HashSet::new(),
                );
                roots.push(built_node);
            }
        }
        
        // Handle orphaned processes (parent not in process list)
        for (pid, node) in &all_processes {
            if !root_pids.contains(pid) {
                // Check if this process has a parent in our list
                let mut has_parent = false;
                for (_, process) in self.system.processes() {
                    if process.pid().as_u32() == *pid {
                        if let Some(parent) = process.parent() {
                            if all_processes.contains_key(&parent.as_u32()) {
                                has_parent = true;
                                break;
                            }
                        }
                    }
                }
                
                if !has_parent && !tree_nodes.contains_key(pid) {
                    // This is an orphaned process, add it as a root
                    let built_node = self.build_node_recursive(
                        node.clone(),
                        &all_processes,
                        &parent_to_children,
                        &mut HashSet::new(),
                    );
                    roots.push(built_node);
                }
            }
        }
        
        // Sort roots by CPU usage (highest first)
        roots.sort_by(|a, b| b.total_cpu_usage.partial_cmp(&a.total_cpu_usage).unwrap());
        
        ProcessTree {
            roots,
            total_processes: all_processes.len(),
        }
    }
    
    fn build_node_recursive(
        &self,
        mut node: ProcessTreeNode,
        all_processes: &HashMap<u32, ProcessTreeNode>,
        parent_to_children: &HashMap<u32, Vec<u32>>,
        visited: &mut HashSet<u32>,
    ) -> ProcessTreeNode {
        // Prevent cycles
        if visited.contains(&node.pid) {
            return node;
        }
        visited.insert(node.pid);
        
        // Add children
        if let Some(child_pids) = parent_to_children.get(&node.pid) {
            for child_pid in child_pids {
                if let Some(child_node) = all_processes.get(child_pid) {
                    let built_child = self.build_node_recursive(
                        child_node.clone(),
                        all_processes,
                        parent_to_children,
                        visited,
                    );
                    
                    // Update aggregated metrics
                    node.total_cpu_usage += built_child.total_cpu_usage;
                    node.total_memory_mb += built_child.total_memory_mb;
                    node.descendant_count += 1 + built_child.descendant_count;
                    
                    node.children.push(built_child);
                }
            }
        }
        
        // Sort children by CPU usage
        node.children.sort_by(|a, b| b.total_cpu_usage.partial_cmp(&a.total_cpu_usage).unwrap());
        
        visited.remove(&node.pid);
        node
    }
    
    pub fn find_process_family(&mut self, target_pid: u32) -> Option<ProcessTreeNode> {
        let tree = self.build_tree();
        self.find_in_tree(&tree.roots, target_pid)
    }
    
    fn find_in_tree(&self, nodes: &[ProcessTreeNode], target_pid: u32) -> Option<ProcessTreeNode> {
        for node in nodes {
            if node.pid == target_pid {
                return Some(node.clone());
            }
            if let Some(found) = self.find_in_tree(&node.children, target_pid) {
                return Some(found);
            }
        }
        None
    }
}