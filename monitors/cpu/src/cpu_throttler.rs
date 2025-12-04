use std::time::{Duration, Instant};
use std::collections::VecDeque;

/// CPU Throttler to limit Reaper's own CPU usage
/// Implements adaptive refresh rates and circuit breaker pattern
#[derive(Debug, Clone)]
pub struct CpuThrottler {
    /// Maximum CPU percentage Reaper should use (default: 2.0%)
    max_cpu_percent: f32,
    /// Current CPU usage of Reaper
    current_usage: f32,
    /// Base refresh interval
    base_interval: Duration,
    /// Current sample interval (adaptive)
    sample_interval: Duration,
    /// History of recent CPU measurements
    usage_history: VecDeque<(Instant, f32)>,
    /// Circuit breaker state
    breaker: CircuitBreaker,
}

#[derive(Debug, Clone)]
struct CircuitBreaker {
    /// CPU threshold for triggering breaker (5.0%)
    threshold: f32,
    /// How long CPU must exceed threshold
    duration: Duration,
    /// Cooldown period after triggering
    cooldown: Duration,
    /// Current state
    state: BreakerState,
    /// When the breaker was triggered
    triggered_at: Option<Instant>,
    /// When high usage started
    high_usage_start: Option<Instant>,
}

#[derive(Debug, Clone, PartialEq)]
enum BreakerState {
    Closed,     // Normal operation
    Open,       // Breaker triggered, operations limited
    HalfOpen,   // Testing if system recovered
}

impl Default for CpuThrottler {
    fn default() -> Self {
        Self::new(2.0, Duration::from_secs(1))
    }
}

impl CpuThrottler {
    pub fn new(max_cpu_percent: f32, base_interval: Duration) -> Self {
        Self {
            max_cpu_percent,
            current_usage: 0.0,
            base_interval,
            sample_interval: base_interval,
            usage_history: VecDeque::with_capacity(60),
            breaker: CircuitBreaker::new(),
        }
    }

    /// Update current CPU usage and adjust throttling
    pub fn update_usage(&mut self, cpu_percent: f32) {
        self.current_usage = cpu_percent;
        
        // Add to history
        let now = Instant::now();
        self.usage_history.push_back((now, cpu_percent));
        
        // Keep only last 60 seconds
        while self.usage_history.len() > 60 {
            self.usage_history.pop_front();
        }
        
        // Update circuit breaker
        self.breaker.update(cpu_percent);
        
        // Adjust sample interval based on usage
        self.sample_interval = self.calculate_interval();
    }

    /// Calculate adaptive refresh interval based on current state
    pub fn calculate_interval(&self) -> Duration {
        // If circuit breaker is open, use maximum interval
        if self.breaker.is_open() {
            return Duration::from_secs(10);
        }
        
        // Adaptive intervals based on CPU usage
        match self.current_usage {
            u if u > 5.0 => Duration::from_secs(10),  // Emergency throttle
            u if u > self.max_cpu_percent => Duration::from_secs(5),  // Over limit
            u if u > 1.0 => Duration::from_secs(2),   // Normal usage
            _ => self.base_interval,                   // Low usage
        }
    }

    /// Get current refresh interval
    pub fn get_refresh_interval(&self) -> Duration {
        self.sample_interval
    }

    /// Check if we should skip this update cycle
    pub fn should_skip_update(&self) -> bool {
        // Skip if circuit breaker is open
        if self.breaker.is_open() {
            return true;
        }
        
        // Skip if consistently over limit
        if self.get_average_usage(5) > self.max_cpu_percent * 1.5 {
            return true;
        }
        
        false
    }

    /// Get average CPU usage over last N seconds
    pub fn get_average_usage(&self, seconds: usize) -> f32 {
        let now = Instant::now();
        let cutoff = now - Duration::from_secs(seconds as u64);
        
        let recent: Vec<f32> = self.usage_history
            .iter()
            .filter(|(time, _)| *time > cutoff)
            .map(|(_, usage)| *usage)
            .collect();
        
        if recent.is_empty() {
            return self.current_usage;
        }
        
        recent.iter().sum::<f32>() / recent.len() as f32
    }

    /// Get throttling statistics
    pub fn get_stats(&self) -> ThrottleStats {
        ThrottleStats {
            current_usage: self.current_usage,
            average_usage_5s: self.get_average_usage(5),
            average_usage_60s: self.get_average_usage(60),
            current_interval: self.sample_interval,
            breaker_state: format!("{:?}", self.breaker.state),
            is_throttled: self.should_skip_update(),
        }
    }

    /// Set maximum CPU percentage
    pub fn set_max_cpu(&mut self, percent: f32) {
        self.max_cpu_percent = percent.max(1.0).min(50.0);
    }

    /// Reset throttler state
    pub fn reset(&mut self) {
        self.current_usage = 0.0;
        self.usage_history.clear();
        self.sample_interval = self.base_interval;
        self.breaker.reset();
    }
}

impl CircuitBreaker {
    fn new() -> Self {
        Self {
            threshold: 5.0,
            duration: Duration::from_secs(10),
            cooldown: Duration::from_secs(30),
            state: BreakerState::Closed,
            triggered_at: None,
            high_usage_start: None,
        }
    }

    fn update(&mut self, cpu_percent: f32) {
        let now = Instant::now();
        
        match self.state {
            BreakerState::Closed => {
                if cpu_percent > self.threshold {
                    if let Some(start) = self.high_usage_start {
                        if now.duration_since(start) > self.duration {
                            // Trigger breaker
                            self.state = BreakerState::Open;
                            self.triggered_at = Some(now);
                            self.high_usage_start = None;
                        }
                    } else {
                        self.high_usage_start = Some(now);
                    }
                } else {
                    self.high_usage_start = None;
                }
            }
            BreakerState::Open => {
                if let Some(triggered) = self.triggered_at {
                    if now.duration_since(triggered) > self.cooldown {
                        self.state = BreakerState::HalfOpen;
                    }
                }
            }
            BreakerState::HalfOpen => {
                if cpu_percent < self.threshold {
                    self.state = BreakerState::Closed;
                    self.triggered_at = None;
                } else {
                    self.state = BreakerState::Open;
                    self.triggered_at = Some(now);
                }
            }
        }
    }

    fn is_open(&self) -> bool {
        self.state == BreakerState::Open
    }

    fn reset(&mut self) {
        self.state = BreakerState::Closed;
        self.triggered_at = None;
        self.high_usage_start = None;
    }
}

#[derive(Debug, Clone)]
pub struct ThrottleStats {
    pub current_usage: f32,
    pub average_usage_5s: f32,
    pub average_usage_60s: f32,
    pub current_interval: Duration,
    pub breaker_state: String,
    pub is_throttled: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_adaptive_intervals() {
        let mut throttler = CpuThrottler::new(2.0, Duration::from_secs(1));
        
        // Low usage
        throttler.update_usage(0.5);
        assert_eq!(throttler.calculate_interval(), Duration::from_secs(1));
        
        // Normal usage
        throttler.update_usage(1.5);
        assert_eq!(throttler.calculate_interval(), Duration::from_secs(2));
        
        // Over limit
        throttler.update_usage(3.0);
        assert_eq!(throttler.calculate_interval(), Duration::from_secs(5));
        
        // Emergency
        throttler.update_usage(6.0);
        assert_eq!(throttler.calculate_interval(), Duration::from_secs(10));
    }

    #[test]
    fn test_circuit_breaker() {
        let mut throttler = CpuThrottler::new(2.0, Duration::from_secs(1));
        
        // Simulate high CPU for 11 seconds
        for _ in 0..11 {
            throttler.update_usage(6.0);
            std::thread::sleep(Duration::from_millis(100));
        }
        
        // Should trigger circuit breaker
        assert!(throttler.should_skip_update());
    }

    #[test]
    fn test_average_usage() {
        let mut throttler = CpuThrottler::new(2.0, Duration::from_secs(1));
        
        // Add some usage data
        throttler.update_usage(1.0);
        throttler.update_usage(2.0);
        throttler.update_usage(3.0);
        
        let avg = throttler.get_average_usage(5);
        assert!(avg > 1.5 && avg < 2.5);
    }
}