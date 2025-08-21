use std::collections::HashMap;
use std::time::Duration;

/// Stack trace information (simplified for flame graphs)
#[derive(Debug, Clone)]
pub struct StackTrace {
    pub pid: u32,
    pub thread_id: Option<u64>,
    pub timestamp: std::time::SystemTime,
    pub frames: Vec<StackFrame>,
    pub sample_duration_ms: u64,
    pub is_complete: bool,
}

/// Individual stack frame (simplified for flame graphs)
#[derive(Debug, Clone)]
pub struct StackFrame {
    pub address: u64,
    pub symbol: Option<String>,
    pub module: Option<String>,
    pub file: Option<String>,
    pub line: Option<u32>,
    pub offset: Option<u64>,
}

/// Flame graph data structure optimized for visualization
#[derive(Debug, Clone)]
pub struct FlameGraphData {
    pub root: FlameGraphNode,
    pub total_samples: u64,
    pub total_duration: Duration,
    pub process_name: String,
    pub pid: u32,
    pub generated_at: std::time::SystemTime,
}

/// Individual node in the flame graph tree
#[derive(Debug, Clone)]
pub struct FlameGraphNode {
    pub function_name: String,
    pub module_name: Option<String>,
    pub file_path: Option<String>,
    pub line_number: Option<u32>,
    pub self_samples: u64,
    pub total_samples: u64,
    pub children: HashMap<String, FlameGraphNode>,
}

/// Builder for constructing flame graphs from stack traces
#[derive(Debug)]
pub struct FlameGraphBuilder {
    root: FlameGraphNode,
    total_samples: u64,
    process_name: String,
    pid: u32,
    samples_by_thread: HashMap<u64, Vec<StackTrace>>,
}

impl FlameGraphNode {
    pub fn new(function_name: String) -> Self {
        Self {
            function_name,
            module_name: None,
            file_path: None,
            line_number: None,
            self_samples: 0,
            total_samples: 0,
            children: HashMap::new(),
        }
    }
    
    pub fn with_location(
        function_name: String,
        module_name: Option<String>,
        file_path: Option<String>,
        line_number: Option<u32>,
    ) -> Self {
        Self {
            function_name,
            module_name,
            file_path,
            line_number,
            self_samples: 0,
            total_samples: 0,
            children: HashMap::new(),
        }
    }
    
    pub fn add_sample(&mut self, count: u64) {
        self.self_samples += count;
        self.total_samples += count;
    }
    
    pub fn get_or_create_child(&mut self, key: String, frame: &StackFrame) -> &mut FlameGraphNode {
        self.children.entry(key.clone()).or_insert_with(|| {
            FlameGraphNode::with_location(
                frame.symbol.clone().unwrap_or_else(|| format!("0x{:x}", frame.address)),
                frame.module.clone(),
                frame.file.clone(),
                frame.line,
            )
        })
    }
    
    pub fn update_totals(&mut self) {
        // Recursively update total counts from children
        let mut child_total = 0;
        for child in self.children.values_mut() {
            child.update_totals();
            child_total += child.total_samples;
        }
        self.total_samples = self.self_samples + child_total;
    }
    
    pub fn get_percentage(&self, total: u64) -> f64 {
        if total == 0 {
            0.0
        } else {
            (self.total_samples as f64 / total as f64) * 100.0
        }
    }
    
    pub fn prune_small_nodes(&mut self, min_percentage: f64, total: u64) {
        let threshold = (min_percentage / 100.0 * total as f64) as u64;
        
        self.children.retain(|_, child| {
            child.prune_small_nodes(min_percentage, total);
            child.total_samples >= threshold
        });
    }
}

impl FlameGraphBuilder {
    pub fn new(process_name: String, pid: u32) -> Self {
        Self {
            root: FlameGraphNode::new("ROOT".to_string()),
            total_samples: 0,
            process_name,
            pid,
            samples_by_thread: HashMap::new(),
        }
    }
    
    pub fn add_stack_trace(&mut self, stack_trace: StackTrace) {
        if stack_trace.frames.is_empty() {
            return;
        }
        
        // Group by thread if available
        let thread_id = stack_trace.thread_id.unwrap_or(0);
        self.samples_by_thread
            .entry(thread_id)
            .or_insert_with(Vec::new)
            .push(stack_trace);
    }
    
    pub fn build(mut self) -> FlameGraphData {
        // Process all stack traces - clone the data to avoid borrow issues
        let traces_to_process: Vec<StackTrace> = self.samples_by_thread
            .values()
            .flat_map(|traces| traces.iter().cloned())
            .collect();
            
        for trace in traces_to_process {
            self.process_stack_trace(trace);
        }
        
        // Update totals recursively
        self.root.update_totals();
        
        // Prune nodes that represent less than 0.5% of total samples
        self.root.prune_small_nodes(0.5, self.total_samples);
        
        FlameGraphData {
            root: self.root,
            total_samples: self.total_samples,
            total_duration: Duration::from_millis(0), // Will be set by caller
            process_name: self.process_name,
            pid: self.pid,
            generated_at: std::time::SystemTime::now(),
        }
    }
    
    fn process_stack_trace(&mut self, stack_trace: StackTrace) {
        if stack_trace.frames.is_empty() {
            return;
        }
        
        // Pre-compute all keys to avoid borrowing self during iteration
        let keys: Vec<String> = stack_trace.frames.iter().rev()
            .map(|frame| self.create_frame_key(frame))
            .collect();
        
        let mut current_node = &mut self.root;
        
        // Walk the stack from bottom to top (reverse order for flame graph)
        for (frame, key) in stack_trace.frames.iter().rev().zip(keys.iter()) {
            current_node = current_node.get_or_create_child(key.clone(), frame);
        }
        
        // Add sample to the leaf node
        current_node.add_sample(1);
        self.total_samples += 1;
    }
    
    fn create_frame_key(&self, frame: &StackFrame) -> String {
        // Create unique key for frame that combines symbol and address
        if let Some(ref symbol) = frame.symbol {
            if let Some(ref module) = frame.module {
                format!("{}::{}", module, symbol)
            } else {
                symbol.clone()
            }
        } else {
            format!("0x{:x}", frame.address)
        }
    }
}

impl FlameGraphData {
    pub fn export_to_folded_format(&self) -> String {
        let mut lines = Vec::new();
        self.export_node_folded(&self.root, String::new(), &mut lines);
        lines.join("\n")
    }
    
    fn export_node_folded(&self, node: &FlameGraphNode, stack: String, lines: &mut Vec<String>) {
        let current_stack = if stack.is_empty() {
            node.function_name.clone()
        } else {
            format!("{};{}", stack, node.function_name)
        };
        
        // Add self samples
        if node.self_samples > 0 {
            lines.push(format!("{} {}", current_stack, node.self_samples));
        }
        
        // Recursively process children
        for child in node.children.values() {
            self.export_node_folded(child, current_stack.clone(), lines);
        }
    }
    
    pub fn export_to_json(&self) -> serde_json::Value {
        use serde_json::json;
        
        json!({
            "name": self.process_name,
            "pid": self.pid,
            "total_samples": self.total_samples,
            "duration_ms": self.total_duration.as_millis(),
            "generated_at": self.generated_at.duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_secs(),
            "root": self.export_node_json(&self.root)
        })
    }
    
    fn export_node_json(&self, node: &FlameGraphNode) -> serde_json::Value {
        use serde_json::json;
        
        let mut children_array = Vec::new();
        for child in node.children.values() {
            children_array.push(self.export_node_json(child));
        }
        
        json!({
            "name": node.function_name,
            "module": node.module_name,
            "file": node.file_path,
            "line": node.line_number,
            "self_samples": node.self_samples,
            "total_samples": node.total_samples,
            "percentage": node.get_percentage(self.total_samples),
            "children": children_array
        })
    }
    
    pub fn get_hot_functions(&self, limit: usize) -> Vec<(&FlameGraphNode, f64)> {
        let mut hot_functions = Vec::new();
        self.collect_hot_functions(&self.root, &mut hot_functions);
        
        // Sort by total samples (descending)
        hot_functions.sort_by(|a, b| b.0.total_samples.cmp(&a.0.total_samples));
        
        // Take top N and calculate percentages
        hot_functions
            .into_iter()
            .take(limit)
            .map(|(node, _)| (node, node.get_percentage(self.total_samples)))
            .collect()
    }
    
    fn collect_hot_functions<'a>(&self, node: &'a FlameGraphNode, hot_functions: &mut Vec<(&'a FlameGraphNode, f64)>) {
        // Only include nodes with self samples (actual function calls)
        if node.self_samples > 0 && node.function_name != "ROOT" {
            hot_functions.push((node, 0.0)); // Percentage will be calculated later
        }
        
        for child in node.children.values() {
            self.collect_hot_functions(child, hot_functions);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_flame_graph_builder() {
        let mut builder = FlameGraphBuilder::new("test_process".to_string(), 1234);
        
        // Create a simple stack trace
        let stack_trace = StackTrace {
            pid: 1234,
            thread_id: Some(1),
            timestamp: std::time::SystemTime::now(),
            frames: vec![
                StackFrame {
                    address: 0x1000,
                    symbol: Some("main".to_string()),
                    module: Some("test_app".to_string()),
                    file: Some("main.c".to_string()),
                    line: Some(42),
                    offset: None,
                },
                StackFrame {
                    address: 0x2000,
                    symbol: Some("foo".to_string()),
                    module: Some("test_app".to_string()),
                    file: Some("foo.c".to_string()),
                    line: Some(10),
                    offset: None,
                },
            ],
            sample_duration_ms: 100,
            is_complete: true,
        };
        
        builder.add_stack_trace(stack_trace);
        let flame_graph = builder.build();
        
        assert_eq!(flame_graph.total_samples, 1);
        assert_eq!(flame_graph.process_name, "test_process");
        assert_eq!(flame_graph.pid, 1234);
        
        // Check that the stack was built correctly
        assert!(!flame_graph.root.children.is_empty());
    }
}