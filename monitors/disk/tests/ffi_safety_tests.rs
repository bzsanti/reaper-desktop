// FFI Safety Integration Tests
// These tests verify that the public API works correctly for FFI integration

use reaper_disk_monitor::file_analyzer::{FileAnalyzer, FileCategory};
use tempfile::TempDir;

#[test]
fn test_file_analyzer_creation() {
    let _analyzer = FileAnalyzer::new();
    // If we can create it without panic, test passes
}

#[test]
fn test_analyzer_with_temp_directory() {
    let temp_dir = TempDir::new().unwrap();

    // Create test files
    for i in 0..5 {
        std::fs::write(
            temp_dir.path().join(format!("file{}.txt", i)),
            vec![0u8; 1024 * (i + 1)]
        ).unwrap();
    }

    let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
    let result = analyzer.analyze_directory(temp_dir.path(), 10);

    assert!(result.is_ok());
    let analysis = result.unwrap();
    assert_eq!(analysis.file_count, 5);
    assert!(analysis.total_size > 0);
}

#[test]
fn test_duplicate_detection_basic() {
    let temp_dir = TempDir::new().unwrap();

    // Create duplicate files
    let content = b"duplicate content";
    std::fs::write(temp_dir.path().join("file1.txt"), content).unwrap();
    std::fs::write(temp_dir.path().join("file2.txt"), content).unwrap();
    std::fs::write(temp_dir.path().join("unique.txt"), b"different").unwrap();

    let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
    let result = analyzer.find_duplicates(temp_dir.path());

    assert!(result.is_ok());
    let duplicates = result.unwrap();
    assert_eq!(duplicates.len(), 1);
    assert_eq!(duplicates[0].files.len(), 2);
}

#[test]
fn test_analyzer_with_cache() {
    let temp_dir = TempDir::new().unwrap();

    // Create test files
    std::fs::write(temp_dir.path().join("file1.txt"), b"content1").unwrap();
    std::fs::write(temp_dir.path().join("file2.txt"), b"content2").unwrap();

    let analyzer = FileAnalyzer::new()
        .with_excluded_paths(vec![])
        .enable_default_cache();

    // First analysis
    let result1 = analyzer.analyze_directory(temp_dir.path(), 10);
    assert!(result1.is_ok());

    // Second analysis (should use cache for some operations)
    let result2 = analyzer.analyze_directory(temp_dir.path(), 10);
    assert!(result2.is_ok());
}

#[test]
fn test_category_stats_aggregation() {
    let temp_dir = TempDir::new().unwrap();

    // Create files of different categories
    std::fs::write(temp_dir.path().join("doc.pdf"), vec![0u8; 1024]).unwrap();
    std::fs::write(temp_dir.path().join("image.jpg"), vec![0u8; 2048]).unwrap();
    std::fs::write(temp_dir.path().join("code.rs"), vec![0u8; 512]).unwrap();

    let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
    let result = analyzer.analyze_directory(temp_dir.path(), 10);

    assert!(result.is_ok());
    let analysis = result.unwrap();

    assert!(analysis.category_stats.contains_key(&FileCategory::Documents));
    assert!(analysis.category_stats.contains_key(&FileCategory::Media));
    assert!(analysis.category_stats.contains_key(&FileCategory::Code));
}

#[test]
fn test_min_size_filtering() {
    let temp_dir = TempDir::new().unwrap();

    // Create files of different sizes
    std::fs::write(temp_dir.path().join("small.txt"), vec![0u8; 100]).unwrap();
    std::fs::write(temp_dir.path().join("large.txt"), vec![0u8; 10000]).unwrap();

    let analyzer = FileAnalyzer::new()
        .with_excluded_paths(vec![])
        .with_min_file_size(1000);

    let result = analyzer.analyze_directory(temp_dir.path(), 10);

    assert!(result.is_ok());
    let analysis = result.unwrap();

    // Total count should include all files
    assert_eq!(analysis.file_count, 2);

    // Largest files should only include files >= 1000 bytes
    assert!(analysis.largest_files.iter().all(|f| f.size_bytes >= 1000));
}

#[test]
fn test_custom_configuration() {
    let analyzer = FileAnalyzer::new()
        .with_max_depth(5)
        .with_min_file_size(1024)
        .enable_default_cache();

    // Test that analyzer can be created with custom configuration
    let temp_dir = TempDir::new().unwrap();
    let result = analyzer.analyze_directory(temp_dir.path(), 10);
    assert!(result.is_ok());
}

#[test]
fn test_empty_directory() {
    let temp_dir = TempDir::new().unwrap();

    let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
    let result = analyzer.analyze_directory(temp_dir.path(), 10);

    assert!(result.is_ok());
    let analysis = result.unwrap();
    assert_eq!(analysis.file_count, 0);
    assert_eq!(analysis.total_size, 0);
}
