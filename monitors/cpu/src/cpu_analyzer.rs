use serde::{Deserialize, Serialize};
use std::time::{Instant, Duration};
use std::collections::VecDeque;
use sysinfo::System;
use std::process::Command;

#[derive(Debug, Clone)]
pub struct CpuMetrics {
    pub total_usage: f32,
    pub per_core_usage: Vec<f32>,
    pub load_average: LoadAverage,
    pub frequency_mhz: u64,
    pub temperature: Option<f32>,
    pub timestamp: Instant,
}

#[derive(Debug, Clone)]
pub struct RealTimeCpuSample {
    pub timestamp: Instant,
    pub total_usage: f32,
    pub per_core_usage: Vec<f32>,
    pub context_switches_delta: u64,
    pub interrupts_delta: u64,
    pub processes_running: u32,
    pub processes_blocked: u32,
}

#[derive(Debug)]
pub struct CpuSamplingBuffer {
    samples: VecDeque<RealTimeCpuSample>,
    max_samples: usize,
    sample_interval_ms: u64,
    last_sample_time: Instant,
}

#[derive(Debug, Clone)]
pub struct AggregatedCpuMetrics {
    pub timespan: Duration,
    pub average_usage: f32,
    pub peak_usage: f32,
    pub per_core_average: Vec<f32>,
    pub per_core_peak: Vec<f32>,
    pub context_switches_per_second: f64,
    pub sample_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadAverage {
    pub one_minute: f64,
    pub five_minutes: f64,
    pub fifteen_minutes: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuBottleneck {
    pub bottleneck_type: BottleneckType,
    pub severity: f32,
    pub affected_processes: Vec<u32>,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BottleneckType {
    HighCpuUsage,
    HighIoWait,
    ExcessiveContextSwitching,
    ThermalThrottling,
    MemoryPressure,
}

pub struct CpuAnalyzer {
    system: System,
    last_update: Instant,
    history: Vec<CpuMetrics>,
    max_history_size: usize,
    // Real-time sampling components
    sampling_buffer: CpuSamplingBuffer,
    last_context_switches: Option<u64>,
    last_interrupts: Option<u64>,
    high_frequency_sampling: bool,
}

impl CpuSamplingBuffer {
    pub fn new(sample_interval_ms: u64, max_samples: usize) -> Self {
        Self {
            samples: VecDeque::with_capacity(max_samples),
            max_samples,
            sample_interval_ms,
            last_sample_time: Instant::now(),
        }
    }
    
    pub fn add_sample(&mut self, sample: RealTimeCpuSample) {
        if self.samples.len() >= self.max_samples {
            self.samples.pop_front();
        }
        self.last_sample_time = sample.timestamp;
        self.samples.push_back(sample);
    }
    
    pub fn should_sample(&self) -> bool {
        self.last_sample_time.elapsed().as_millis() >= self.sample_interval_ms as u128
    }
    
    pub fn get_recent_samples(&self, duration: Duration) -> Vec<&RealTimeCpuSample> {
        let cutoff = Instant::now() - duration;
        self.samples
            .iter()
            .filter(|sample| sample.timestamp >= cutoff)
            .collect()
    }
    
    pub fn aggregate_samples(&self, timespan: Duration) -> Option<AggregatedCpuMetrics> {
        let samples = self.get_recent_samples(timespan);
        if samples.is_empty() {
            return None;
        }
        
        let mut total_usage_sum = 0.0f32;
        let mut peak_usage = 0.0f32;
        let mut core_sums = vec![0.0f32; samples[0].per_core_usage.len()];
        let mut core_peaks = vec![0.0f32; samples[0].per_core_usage.len()];
        let mut total_context_switches = 0u64;
        
        for sample in &samples {
            total_usage_sum += sample.total_usage;
            peak_usage = peak_usage.max(sample.total_usage);
            total_context_switches += sample.context_switches_delta;
            
            for (i, &core_usage) in sample.per_core_usage.iter().enumerate() {
                core_sums[i] += core_usage;
                core_peaks[i] = core_peaks[i].max(core_usage);
            }
        }
        
        let sample_count = samples.len();
        let context_switches_per_second = total_context_switches as f64 / timespan.as_secs_f64();
        
        Some(AggregatedCpuMetrics {
            timespan,
            average_usage: total_usage_sum / sample_count as f32,
            peak_usage,
            per_core_average: core_sums.iter().map(|&sum| sum / sample_count as f32).collect(),
            per_core_peak: core_peaks,
            context_switches_per_second,
            sample_count,
        })
    }
}

impl CpuAnalyzer {
    pub fn new() -> Self {
        let mut system = System::new();
        // Only refresh what we need initially
        system.refresh_cpu();
        system.refresh_memory();
        
        CpuAnalyzer {
            system,
            last_update: Instant::now(),
            history: Vec::with_capacity(60), // Pre-allocate
            max_history_size: 60,
            sampling_buffer: CpuSamplingBuffer::new(100, 600), // 100ms intervals, 60 seconds of data
            last_context_switches: None,
            last_interrupts: None,
            high_frequency_sampling: false,
        }
    }
    
    
    pub fn refresh(&mut self) {
        // Always try real-time sampling if enabled
        if self.high_frequency_sampling && self.sampling_buffer.should_sample() {
            self.collect_realtime_sample();
        }
        
        // Only refresh main metrics if enough time has passed (avoid too frequent updates)
        if self.last_update.elapsed().as_millis() < 500 {
            return;
        }
        
        self.system.refresh_cpu();
        self.system.refresh_memory();
        
        let metrics = self.get_current_metrics();
        
        // Use VecDeque would be better, but for now optimize with swap_remove
        if self.history.len() >= self.max_history_size {
            self.history.remove(0);
        }
        self.history.push(metrics);
        
        self.last_update = Instant::now();
    }
    
    pub fn enable_high_frequency_sampling(&mut self) {
        self.high_frequency_sampling = true;
        // Reset sampling buffer for fresh data
        self.sampling_buffer = CpuSamplingBuffer::new(50, 1200); // 50ms interval, 1 minute buffer
    }
    
    pub fn disable_high_frequency_sampling(&mut self) {
        self.high_frequency_sampling = false;
    }
    
    pub fn collect_realtime_sample(&mut self) {
        self.system.refresh_cpu();
        
        let timestamp = Instant::now();
        let total_usage = self.system.global_cpu_info().cpu_usage();
        let per_core_usage: Vec<f32> = self.system.cpus().iter()
            .map(|cpu| cpu.cpu_usage())
            .collect();
        
        // Get system stats for context switches and interrupts (simplified)
        let (context_switches_delta, interrupts_delta) = self.get_system_stats_delta();
        
        // Count processes in different states
        let (processes_running, processes_blocked) = self.count_process_states();
        
        let sample = RealTimeCpuSample {
            timestamp,
            total_usage,
            per_core_usage,
            context_switches_delta,
            interrupts_delta,
            processes_running,
            processes_blocked,
        };
        
        self.sampling_buffer.add_sample(sample);
    }
    
    fn get_system_stats_delta(&mut self) -> (u64, u64) {
        // Simplified implementation - in a real implementation this would
        // read from /proc/stat equivalent on macOS or use system calls
        
        // For macOS, we could use host_statistics() system call
        // For now, return simulated deltas
        
        let current_switches = self.estimate_context_switches();
        let current_interrupts = self.estimate_interrupts();
        
        let switches_delta = self.last_context_switches
            .map(|last| current_switches.saturating_sub(last))
            .unwrap_or(0);
        let interrupts_delta = self.last_interrupts
            .map(|last| current_interrupts.saturating_sub(last))
            .unwrap_or(0);
        
        self.last_context_switches = Some(current_switches);
        self.last_interrupts = Some(current_interrupts);
        
        (switches_delta, interrupts_delta)
    }
    
    fn estimate_context_switches(&self) -> u64 {
        // Rough estimation based on CPU usage and process count
        let cpu_usage = self.system.global_cpu_info().cpu_usage();
        let process_count = self.system.processes().len() as u64;
        
        // Higher CPU usage and more processes = more context switches
        ((cpu_usage as u64) * process_count * 10) / 100
    }
    
    fn estimate_interrupts(&self) -> u64 {
        // Simplified estimation
        let cpu_usage = self.system.global_cpu_info().cpu_usage();
        (cpu_usage as u64) * 50
    }
    
    fn count_process_states(&self) -> (u32, u32) {
        let mut running = 0;
        let mut blocked = 0;
        
        // This is a simplified version - real implementation would
        // parse process states from system calls
        for process in self.system.processes().values() {
            // sysinfo doesn't provide detailed process states on macOS
            // so we estimate based on CPU usage
            if process.cpu_usage() > 0.1 {
                running += 1;
            } else {
                // Assume sleeping/idle processes are "blocked" for our purposes
                blocked += 1;
            }
        }
        
        (running, blocked)
    }
    
    pub fn get_realtime_metrics(&self, timespan: Duration) -> Option<AggregatedCpuMetrics> {
        self.sampling_buffer.aggregate_samples(timespan)
    }
    
    pub fn get_recent_samples(&self, duration: Duration) -> Vec<&RealTimeCpuSample> {
        self.sampling_buffer.get_recent_samples(duration)
    }
    
    pub fn get_current_metrics(&self) -> CpuMetrics {
        let load_avg = System::load_average();

        CpuMetrics {
            total_usage: self.system.global_cpu_info().cpu_usage(),
            per_core_usage: self.system.cpus().iter().map(|cpu| cpu.cpu_usage()).collect(),
            load_average: LoadAverage {
                one_minute: load_avg.one,
                five_minutes: load_avg.five,
                fifteen_minutes: load_avg.fifteen,
            },
            frequency_mhz: self.system.global_cpu_info().frequency(),
            temperature: self.get_cpu_temperature(),
            timestamp: Instant::now(),
        }
    }

    fn get_cpu_temperature(&self) -> Option<f32> {
        // Try to get CPU temperature using system tools
        // First try the thermal state from macOS
        if let Ok(output) = Command::new("sysctl")
            .arg("-n")
            .arg("machdep.xcpm.cpu_thermal_state")
            .output() {
            if output.status.success() {
                let temp_str = String::from_utf8_lossy(&output.stdout);
                if let Ok(temp) = temp_str.trim().parse::<f32>() {
                    return Some(temp);
                }
            }
        }

        // Alternative: try powermetrics (requires sudo, but might work for reading)
        if let Ok(output) = Command::new("powermetrics")
            .arg("-n")
            .arg("1")
            .arg("-i")
            .arg("500")
            .arg("--samplers")
            .arg("smc")
            .arg("-o")
            .arg("stdout")
            .output() {
            if output.status.success() {
                let output_str = String::from_utf8_lossy(&output.stdout);
                // Look for CPU temperature in powermetrics output
                for line in output_str.lines() {
                    if line.contains("CPU die temperature") {
                        if let Some(temp_part) = line.split(':').nth(1) {
                            if let Some(temp_str) = temp_part.split_whitespace().next() {
                                if let Ok(temp) = temp_str.parse::<f32>() {
                                    return Some(temp);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fallback: simulate temperature based on CPU usage (for development)
        let base_temp = 35.0; // Base temperature in Celsius
        let usage_temp = self.system.global_cpu_info().cpu_usage() * 0.5; // Scale factor
        Some(base_temp + usage_temp)
    }
    
    pub fn detect_bottlenecks(&self) -> Vec<CpuBottleneck> {
        let mut bottlenecks = Vec::new();
        let metrics = self.get_current_metrics();
        
        if metrics.total_usage > 90.0 {
            bottlenecks.push(CpuBottleneck {
                bottleneck_type: BottleneckType::HighCpuUsage,
                severity: metrics.total_usage / 100.0,
                affected_processes: vec![],
                description: format!("CPU usage is critically high at {:.1}%", metrics.total_usage),
            });
        }
        
        if metrics.load_average.one_minute > self.system.cpus().len() as f64 * 2.0 {
            bottlenecks.push(CpuBottleneck {
                bottleneck_type: BottleneckType::ExcessiveContextSwitching,
                severity: ((metrics.load_average.one_minute / self.system.cpus().len() as f64) / 3.0) as f32,
                affected_processes: vec![],
                description: format!(
                    "System load ({:.2}) is significantly higher than CPU count ({})",
                    metrics.load_average.one_minute,
                    self.system.cpus().len()
                ),
            });
        }
        
        let memory_usage = (self.system.used_memory() as f64 / self.system.total_memory() as f64) * 100.0;
        if memory_usage > 90.0 {
            bottlenecks.push(CpuBottleneck {
                bottleneck_type: BottleneckType::MemoryPressure,
                severity: memory_usage as f32 / 100.0,
                affected_processes: vec![],
                description: format!("Memory usage is critically high at {:.1}%", memory_usage),
            });
        }
        
        bottlenecks
    }
    
    pub fn get_cpu_trend(&self) -> Option<f32> {
        if self.history.len() < 2 {
            return None;
        }
        
        let recent_avg: f32 = self.history.iter()
            .rev()
            .take(5)
            .map(|m| m.total_usage)
            .sum::<f32>() / 5.0_f32.min(self.history.len() as f32);
        
        let older_avg: f32 = self.history.iter()
            .rev()
            .skip(5)
            .take(5)
            .map(|m| m.total_usage)
            .sum::<f32>() / 5.0_f32.min((self.history.len() - 5).max(1) as f32);
        
        Some(recent_avg - older_avg)
    }
}