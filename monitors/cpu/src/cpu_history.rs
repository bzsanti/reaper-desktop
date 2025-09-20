use std::collections::{BTreeMap, VecDeque};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use serde::{Deserialize, Serialize};

use crate::cpu_analyzer::CpuMetrics;
use crate::process_monitor::ProcessInfo;

/// Historical CPU data point for persistence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuHistoryPoint {
    pub timestamp: u64, // Unix timestamp in seconds
    pub total_usage: f32,
    pub per_core_usage: Vec<f32>,
    pub load_average: (f64, f64, f64), // 1, 5, 15 minute averages
    pub frequency_mhz: u64,
    pub temperature: Option<f32>,
    pub top_processes: Vec<ProcessInfo>, // Top 10 CPU consumers
}

/// Configuration for CPU history storage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuHistoryConfig {
    pub data_directory: PathBuf,
    pub max_points_in_memory: usize,
    pub max_days_to_keep: u32,
    pub compression_enabled: bool,
    pub auto_cleanup_enabled: bool,
    pub flush_interval_seconds: u64,
}

impl Default for CpuHistoryConfig {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        let data_dir = PathBuf::from(home)
            .join(".reaper")
            .join("cpu_history");

        Self {
            data_directory: data_dir,
            max_points_in_memory: 1440, // 24 hours at 1-minute intervals
            max_days_to_keep: 30,
            compression_enabled: true,
            auto_cleanup_enabled: true,
            flush_interval_seconds: 300, // 5 minutes
        }
    }
}

/// CPU history storage with persistence capabilities
#[derive(Debug)]
pub struct CpuHistoryStore {
    config: CpuHistoryConfig,
    memory_buffer: VecDeque<CpuHistoryPoint>,
    daily_files: BTreeMap<String, PathBuf>, // date -> file path
    last_flush_time: SystemTime,
    current_day: String,
}

impl CpuHistoryStore {
    pub fn new(config: CpuHistoryConfig) -> std::io::Result<Self> {
        // Create data directory if it doesn't exist
        std::fs::create_dir_all(&config.data_directory)?;

        let mut store = Self {
            config,
            memory_buffer: VecDeque::new(),
            daily_files: BTreeMap::new(),
            last_flush_time: SystemTime::now(),
            current_day: Self::current_date_string(),
        };

        // Discover existing history files
        store.discover_existing_files()?;

        // Load recent data into memory
        store.load_recent_data()?;

        // Perform cleanup if enabled
        if store.config.auto_cleanup_enabled {
            store.cleanup_old_files()?;
        }

        Ok(store)
    }

    pub fn add_data_point(&mut self, metrics: &CpuMetrics) -> std::io::Result<()> {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let history_point = CpuHistoryPoint {
            timestamp,
            total_usage: metrics.total_usage,
            per_core_usage: metrics.per_core_usage.clone(),
            load_average: (
                metrics.load_average.one_minute,
                metrics.load_average.five_minutes,
                metrics.load_average.fifteen_minutes,
            ),
            frequency_mhz: metrics.frequency_mhz,
            temperature: metrics.temperature,
            top_processes: Vec::new(), // Will need to be populated separately
        };

        // Add to memory buffer
        self.memory_buffer.push_back(history_point);

        // Trim buffer if too large
        while self.memory_buffer.len() > self.config.max_points_in_memory {
            self.memory_buffer.pop_front();
        }

        // Check if we need to flush to disk
        let should_flush = self.last_flush_time
            .elapsed()
            .unwrap_or_default()
            .as_secs() >= self.config.flush_interval_seconds;

        if should_flush {
            self.flush_to_disk()?;
        }

        Ok(())
    }

    pub fn get_recent_data(&self, duration: Duration) -> Vec<&CpuHistoryPoint> {
        let cutoff_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .saturating_sub(duration.as_secs());

        self.memory_buffer
            .iter()
            .filter(|point| point.timestamp >= cutoff_time)
            .collect()
    }

    pub fn get_historical_data(&self, start_time: SystemTime, end_time: SystemTime) -> std::io::Result<Vec<CpuHistoryPoint>> {
        let start_timestamp = start_time
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let end_timestamp = end_time
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let mut results = Vec::new();

        // Add matching points from memory buffer
        for point in &self.memory_buffer {
            if point.timestamp >= start_timestamp && point.timestamp <= end_timestamp {
                results.push(point.clone());
            }
        }

        // Load data from disk files
        let start_date = Self::timestamp_to_date_string(start_timestamp);
        let end_date = Self::timestamp_to_date_string(end_timestamp);

        for (date, file_path) in &self.daily_files {
            if date >= &start_date && date <= &end_date {
                let file_data = self.load_data_from_file(file_path)?;
                for point in file_data {
                    if point.timestamp >= start_timestamp && point.timestamp <= end_timestamp {
                        results.push(point);
                    }
                }
            }
        }

        // Sort by timestamp
        results.sort_by_key(|p| p.timestamp);
        results.dedup_by_key(|p| p.timestamp);

        Ok(results)
    }

    pub fn get_statistics(&self, duration: Duration) -> CpuHistoryStatistics {
        let recent_data = self.get_recent_data(duration);
        
        if recent_data.is_empty() {
            return CpuHistoryStatistics::default();
        }

        let mut total_usage_sum = 0.0;
        let mut max_usage: f32 = 0.0;
        let mut min_usage = f32::MAX;

        for point in &recent_data {
            total_usage_sum += point.total_usage;
            max_usage = max_usage.max(point.total_usage);
            min_usage = min_usage.min(point.total_usage);
        }

        let count = recent_data.len() as f32;

        CpuHistoryStatistics {
            duration,
            data_points: recent_data.len(),
            average_cpu_usage: total_usage_sum / count,
            max_cpu_usage: max_usage,
            min_cpu_usage: min_usage,
            average_frequency_mhz: recent_data.iter()
                .map(|p| p.frequency_mhz as f32)
                .sum::<f32>() / count,
            average_load: recent_data.last()
                .map(|p| p.load_average)
                .unwrap_or((0.0, 0.0, 0.0)),
        }
    }

    pub fn flush_to_disk(&mut self) -> std::io::Result<()> {
        let current_date = Self::current_date_string();

        // Check if we've moved to a new day
        if current_date != self.current_day {
            self.current_day = current_date.clone();
        }

        let file_path = self.get_file_path_for_date(&current_date);
        self.daily_files.insert(current_date, file_path.clone());

        // Append new data to today's file
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&file_path)?;

        // Only write points that haven't been written yet
        for point in &self.memory_buffer {
            let json_line = serde_json::to_string(point)?;
            writeln!(file, "{}", json_line)?;
        }

        file.flush()?;
        self.last_flush_time = SystemTime::now();

        Ok(())
    }

    pub fn cleanup_old_files(&mut self) -> std::io::Result<()> {
        let cutoff_date = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .saturating_sub(self.config.max_days_to_keep as u64 * 24 * 3600);

        let cutoff_date_string = Self::timestamp_to_date_string(cutoff_date);

        let mut files_to_remove = Vec::new();
        for (date, file_path) in &self.daily_files {
            if date < &cutoff_date_string {
                if file_path.exists() {
                    std::fs::remove_file(file_path)?;
                }
                files_to_remove.push(date.clone());
            }
        }

        for date in files_to_remove {
            self.daily_files.remove(&date);
        }

        Ok(())
    }

    fn discover_existing_files(&mut self) -> std::io::Result<()> {
        if !self.config.data_directory.exists() {
            return Ok(());
        }

        for entry in std::fs::read_dir(&self.config.data_directory)? {
            let entry = entry?;
            let path = entry.path();

            if let Some(filename) = path.file_name().and_then(|n| n.to_str()) {
                if filename.starts_with("cpu_history_") && filename.ends_with(".jsonl") {
                    // Extract date from filename: cpu_history_2024-03-15.jsonl
                    if let Some(date) = filename
                        .strip_prefix("cpu_history_")
                        .and_then(|s| s.strip_suffix(".jsonl"))
                    {
                        self.daily_files.insert(date.to_string(), path);
                    }
                }
            }
        }

        Ok(())
    }

    fn load_recent_data(&mut self) -> std::io::Result<()> {
        // Load last few days of data into memory
        let mut recent_dates: Vec<_> = self.daily_files.keys()
            .rev()
            .take(2) // Last 2 days
            .collect();
        recent_dates.reverse();

        for date in recent_dates {
            if let Some(file_path) = self.daily_files.get(date) {
                let data = self.load_data_from_file(file_path)?;
                for point in data {
                    if self.memory_buffer.len() >= self.config.max_points_in_memory {
                        break;
                    }
                    self.memory_buffer.push_back(point);
                }
            }
        }

        Ok(())
    }

    fn load_data_from_file(&self, file_path: &Path) -> std::io::Result<Vec<CpuHistoryPoint>> {
        if !file_path.exists() {
            return Ok(Vec::new());
        }

        let file = File::open(file_path)?;
        let reader = BufReader::new(file);
        let mut data = Vec::new();

        for line in reader.lines() {
            let line = line?;
            if let Ok(point) = serde_json::from_str::<CpuHistoryPoint>(&line) {
                data.push(point);
            }
        }

        Ok(data)
    }

    fn get_file_path_for_date(&self, date: &str) -> PathBuf {
        self.config.data_directory
            .join(format!("cpu_history_{}.jsonl", date))
    }

    fn current_date_string() -> String {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        Self::timestamp_to_date_string(now)
    }

    fn timestamp_to_date_string(timestamp: u64) -> String {
        // Convert timestamp to YYYY-MM-DD format
        let days_since_epoch = timestamp / 86400;
        let epoch_date = chrono::NaiveDate::from_ymd_opt(1970, 1, 1).unwrap();
        let date = epoch_date + chrono::Duration::days(days_since_epoch as i64);
        date.format("%Y-%m-%d").to_string()
    }
}

/// Statistics computed from historical CPU data
#[derive(Debug, Clone)]
pub struct CpuHistoryStatistics {
    pub duration: Duration,
    pub data_points: usize,
    pub average_cpu_usage: f32,
    pub max_cpu_usage: f32,
    pub min_cpu_usage: f32,
    pub average_frequency_mhz: f32,
    pub average_load: (f64, f64, f64),
}

impl Default for CpuHistoryStatistics {
    fn default() -> Self {
        Self {
            duration: Duration::from_secs(0),
            data_points: 0,
            average_cpu_usage: 0.0,
            max_cpu_usage: 0.0,
            min_cpu_usage: 0.0,
            average_frequency_mhz: 0.0,
            average_load: (0.0, 0.0, 0.0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    #[test]
    fn test_cpu_history_store_creation() {
        let config = CpuHistoryConfig {
            data_directory: std::env::temp_dir().join("test_cpu_history"),
            max_points_in_memory: 100,
            max_days_to_keep: 7,
            compression_enabled: false,
            auto_cleanup_enabled: false,
            flush_interval_seconds: 60,
        };

        let store = CpuHistoryStore::new(config);
        assert!(store.is_ok());

        // Cleanup
        let _ = std::fs::remove_dir_all(std::env::temp_dir().join("test_cpu_history"));
    }

    #[test]
    fn test_date_string_conversion() {
        let timestamp = SystemTime::UNIX_EPOCH
            .checked_add(Duration::from_secs(1640995200)) // 2022-01-01 00:00:00 UTC
            .unwrap()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let date_string = CpuHistoryStore::timestamp_to_date_string(timestamp);
        assert_eq!(date_string, "2022-01-01");
    }

    #[test]
    fn test_history_point_serialization() {
        let point = CpuHistoryPoint {
            timestamp: 1640995200,
            total_usage: 75.5,
            per_core_usage: vec![80.0, 70.0, 75.0, 80.0],
            load_average: (1.2, 1.1, 1.0),
            frequency_mhz: 2400,
            temperature: Some(65.0),
            top_processes: Vec::new(),
        };

        let json = serde_json::to_string(&point).unwrap();
        let deserialized: CpuHistoryPoint = serde_json::from_str(&json).unwrap();

        assert_eq!(point.timestamp, deserialized.timestamp);
        assert_eq!(point.total_usage, deserialized.total_usage);
        assert_eq!(point.per_core_usage, deserialized.per_core_usage);
    }
}