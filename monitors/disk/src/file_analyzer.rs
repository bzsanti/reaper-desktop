use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, Duration, Instant};
use std::io;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use parking_lot::RwLock;
use rayon::prelude::*;

#[cfg(target_os = "macos")]
use std::os::unix::fs::MetadataExt;

// Memory and performance limits
#[allow(dead_code)] // Reserved for future memory limit enforcement
const MAX_FILES_IN_MEMORY: usize = 100_000;
#[allow(dead_code)] // Currently used in HashCache insert logic
const MAX_CACHE_SIZE: usize = 10_000;
const SCAN_TIMEOUT_SECS: u64 = 300; // 5 minutes
const HASH_CHUNK_SIZE: usize = 8192;

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub path: PathBuf,
    pub size_bytes: u64,
    pub is_dir: bool,
    pub modified: SystemTime,
    pub file_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum FileCategory {
    Documents,
    Media,
    Code,
    Archives,
    Applications,
    SystemFiles,
    Other,
}

impl FileCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            FileCategory::Documents => "Documents",
            FileCategory::Media => "Media",
            FileCategory::Code => "Code",
            FileCategory::Archives => "Archives",
            FileCategory::Applications => "Applications",
            FileCategory::SystemFiles => "System Files",
            FileCategory::Other => "Other",
        }
    }
}

#[derive(Debug, Clone)]
pub struct FileCategoryStats {
    pub category: FileCategory,
    pub total_size: u64,
    pub file_count: usize,
}

#[derive(Debug, Clone)]
pub struct DirectoryAnalysis {
    pub path: PathBuf,
    pub total_size: u64,
    pub file_count: usize,
    pub dir_count: usize,
    pub largest_files: Vec<FileEntry>,
    pub size_by_type: HashMap<String, u64>,
    pub category_stats: HashMap<FileCategory, FileCategoryStats>,
}

#[derive(Debug, Clone)]
pub struct DuplicateGroup {
    pub hash: String,
    pub size_bytes: u64,
    pub files: Vec<PathBuf>,
    pub total_wasted_space: u64,
}

/// Hash cache for avoiding recomputation of file hashes
#[derive(Debug, Clone)]
pub struct HashCache {
    cache: Arc<RwLock<HashMap<(PathBuf, SystemTime), String>>>,
    max_entries: usize,
}

impl HashCache {
    pub fn new(max_entries: usize) -> Self {
        Self {
            cache: Arc::new(RwLock::new(HashMap::new())),
            max_entries,
        }
    }

    pub fn get(&self, path: &Path, modified: SystemTime) -> Option<String> {
        let cache = self.cache.read();
        cache.get(&(path.to_path_buf(), modified)).cloned()
    }

    pub fn insert(&self, path: PathBuf, modified: SystemTime, hash: String) {
        let mut cache = self.cache.write();

        // Memory limit enforcement: Clear cache if it exceeds max size
        // Simple eviction strategy to prevent unbounded memory growth
        if cache.len() >= self.max_entries {
            // Clear cache when limit is reached
            // In a production system, this could use a proper LRU cache
            cache.clear();
        }

        cache.insert((path, modified), hash);
    }

    pub fn len(&self) -> usize {
        self.cache.read().len()
    }

    pub fn is_empty(&self) -> bool {
        self.cache.read().is_empty()
    }

    pub fn clear(&self) {
        self.cache.write().clear();
    }
}

impl Default for HashCache {
    fn default() -> Self {
        Self::new(10000) // Default to 10k entries
    }
}

pub struct FileAnalyzer {
    max_depth: usize,
    min_file_size: u64,
    follow_symlinks: bool,
    hash_cache: Option<HashCache>,
    excluded_paths: Vec<PathBuf>,
}

/// Error type for permission-related errors
#[derive(Debug)]
pub enum PermissionError {
    AccessDenied(PathBuf),
    SystemPath(PathBuf),
    CircularSymlink(PathBuf),
}

/// Progress callback type: (files_processed, total_bytes_processed)
pub type ProgressCallback = Arc<dyn Fn(usize, u64) + Send + Sync>;

impl FileAnalyzer {
    pub fn new() -> Self {
        Self {
            max_depth: 10,
            min_file_size: 0,
            follow_symlinks: false,
            hash_cache: None,
            excluded_paths: Self::default_excluded_paths(),
        }
    }

    /// Default system paths that should be excluded from scanning on macOS
    fn default_excluded_paths() -> Vec<PathBuf> {
        vec![
            // Critical system directories
            PathBuf::from("/System"),
            PathBuf::from("/private"),
            PathBuf::from("/dev"),
            PathBuf::from("/proc"),
            PathBuf::from("/sys"),
            PathBuf::from("/cores"),
            PathBuf::from("/var"),
            // Volumes and network
            PathBuf::from("/Volumes"),
            PathBuf::from("/Network"),
            // macOS-specific metadata
            PathBuf::from("/.Spotlight-V100"),
            PathBuf::from("/.DocumentRevisions-V100"),
            PathBuf::from("/.fseventsd"),
            PathBuf::from("/.TemporaryItems"),
            PathBuf::from("/.Trashes"),
            PathBuf::from("/.vol"),
            // Cache directories
            PathBuf::from("/Library/Caches"),
            PathBuf::from("/Library/Logs"),
            PathBuf::from("/System/Library/Caches"),
            // Time Machine
            PathBuf::from("/.MobileBackups"),
            PathBuf::from("/Backups.backupdb"),
        ]
    }

    pub fn with_max_depth(mut self, depth: usize) -> Self {
        self.max_depth = depth;
        self
    }

    pub fn with_min_file_size(mut self, size: u64) -> Self {
        self.min_file_size = size;
        self
    }

    pub fn with_symlinks(mut self, follow: bool) -> Self {
        self.follow_symlinks = follow;
        self
    }

    pub fn with_hash_cache(mut self, max_entries: usize) -> Self {
        self.hash_cache = Some(HashCache::new(max_entries));
        self
    }

    pub fn enable_default_cache(mut self) -> Self {
        self.hash_cache = Some(HashCache::default());
        self
    }

    pub fn with_excluded_paths(mut self, paths: Vec<PathBuf>) -> Self {
        self.excluded_paths = paths;
        self
    }

    pub fn add_excluded_path(mut self, path: PathBuf) -> Self {
        self.excluded_paths.push(path);
        self
    }

    /// Check if a path should be excluded from scanning
    fn is_path_excluded(&self, path: &Path) -> bool {
        for excluded in &self.excluded_paths {
            if path.starts_with(excluded) {
                return true;
            }
        }
        false
    }

    /// Validate that a path is safe and within the allowed root directory
    /// Prevents path traversal attacks and validates symlinks
    #[allow(dead_code)] // Reserved for future enhanced security validation
    fn is_safe_path(&self, path: &Path, root: &Path) -> bool {
        // First check: Ensure path is not in exclusion list
        if self.is_path_excluded(path) {
            return false;
        }

        // Second check: Canonicalize and verify it's within root directory
        match path.canonicalize() {
            Ok(canonical) => {
                // Ensure canonical path starts with root
                match root.canonicalize() {
                    Ok(canonical_root) => canonical.starts_with(canonical_root),
                    Err(_) => false, // Root doesn't exist or no permission (fail-safe: deny)
                }
            }
            Err(_) => {
                // Cannot canonicalize - either doesn't exist or no permission
                // Fail-safe: deny access
                false
            }
        }
    }

    /// Check path permissions and validity
    /// Returns Ok(()) if path is safe to access, Err otherwise
    #[allow(dead_code)] // Reserved for future use and external API
    fn check_path_permissions(&self, path: &Path) -> Result<(), PermissionError> {
        // Check if path is in excluded list
        if self.is_path_excluded(path) {
            return Err(PermissionError::SystemPath(path.to_path_buf()));
        }

        // Check if path is readable
        match fs::metadata(path) {
            Ok(_) => Ok(()),
            Err(_) => Err(PermissionError::AccessDenied(path.to_path_buf())),
        }
    }

    /// Detect circular symlinks by tracking visited paths
    #[allow(dead_code)] // Reserved for future symlink tracking
    fn detect_circular_symlink(&self, path: &Path, visited: &mut Vec<PathBuf>) -> bool {
        if let Ok(canonical) = path.canonicalize() {
            if visited.contains(&canonical) {
                return true;
            }
            visited.push(canonical);
        }
        false
    }

    /// Check if a file is a cloud storage placeholder (OneDrive, iCloud, Dropbox, etc.)
    /// These files have metadata but the actual content is not downloaded locally
    fn is_cloud_placeholder(&self, path: &Path, metadata: &fs::Metadata) -> bool {
        // Skip directories
        if metadata.is_dir() {
            return false;
        }

        #[cfg(target_os = "macos")]
        {
            // On macOS, cloud files have special characteristics:
            // 1. OneDrive: Files in OneDrive folders with size 0 or very small
            // 2. iCloud: Files with .icloud extension or in CloudDocs
            // 3. Check for common cloud storage paths

            let path_str = path.to_string_lossy();

            // Check for OneDrive placeholder patterns
            if path_str.contains("/OneDrive") || path_str.contains("/OneDrive - ") {
                // OneDrive placeholders often have 0 size or very small size (just metadata)
                // Real files should have substantial size
                if metadata.len() < 100 {
                    return true;
                }

                // OneDrive uses special file attributes - check for unusual block count
                // Placeholder files have blocks == 0 while real files have blocks > 0
                if metadata.blocks() == 0 && metadata.len() > 0 {
                    return true;
                }
            }

            // Check for iCloud placeholder files (.icloud extension)
            if let Some(extension) = path.extension() {
                if extension == "icloud" {
                    return true;
                }
            }

            // Check for iCloud Drive paths
            if path_str.contains("/Library/Mobile Documents/com~apple~CloudDocs") {
                // iCloud files with 0 blocks are not downloaded
                if metadata.blocks() == 0 && metadata.len() > 0 {
                    return true;
                }
            }

            // Check for Dropbox smart sync placeholders
            if path_str.contains("/Dropbox") {
                if metadata.blocks() == 0 && metadata.len() > 0 {
                    return true;
                }
            }
        }

        false
    }

    /// Categorize file type based on extension
    fn categorize_file_type(path: &Path) -> FileCategory {
        let extension = path.extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();

        match extension.as_str() {
            // Documents
            "pdf" | "doc" | "docx" | "txt" | "rtf" | "odt" | "pages" | "tex" | "md" | "markdown" => {
                FileCategory::Documents
            }
            // Media - Images
            "jpg" | "jpeg" | "png" | "gif" | "bmp" | "svg" | "webp" | "heic" | "tiff" | "tif" | "raw" | "cr2" | "nef" => {
                FileCategory::Media
            }
            // Media - Video
            "mp4" | "avi" | "mkv" | "mov" | "wmv" | "flv" | "webm" | "m4v" | "mpg" | "mpeg" => {
                FileCategory::Media
            }
            // Media - Audio
            "mp3" | "wav" | "flac" | "aac" | "ogg" | "m4a" | "wma" | "aiff" => {
                FileCategory::Media
            }
            // Code
            "rs" | "c" | "cpp" | "h" | "hpp" | "swift" | "py" | "js" | "ts" | "java" | "go" | "rb" | "php" | "cs" | "kt" | "scala" => {
                FileCategory::Code
            }
            "html" | "css" | "scss" | "sass" | "json" | "xml" | "yaml" | "yml" | "toml" | "sh" | "bash" | "zsh" => {
                FileCategory::Code
            }
            // Archives
            "zip" | "tar" | "gz" | "bz2" | "xz" | "7z" | "rar" | "dmg" | "iso" => {
                FileCategory::Archives
            }
            // Applications
            "app" | "exe" | "dll" | "so" | "dylib" => {
                FileCategory::Applications
            }
            // System Files
            "sys" | "ini" | "cfg" | "conf" | "log" | "tmp" | "bak" | "swp" | "cache" => {
                FileCategory::SystemFiles
            }
            // Other
            _ => FileCategory::Other,
        }
    }

    /// Analyze a directory and return the largest files
    pub fn analyze_directory<P: AsRef<Path>>(
        &self,
        path: P,
        top_n: usize,
    ) -> io::Result<DirectoryAnalysis> {
        let path = path.as_ref();
        let mut files = Vec::new();
        let mut total_size = 0u64;
        let mut file_count = 0usize;
        let mut dir_count = 0usize;
        let mut size_by_type: HashMap<String, u64> = HashMap::new();
        let mut category_stats: HashMap<FileCategory, FileCategoryStats> = HashMap::new();

        self.walk_directory(path, 0, &mut |entry: FileEntry| {
            if entry.is_dir {
                dir_count += 1;
            } else {
                file_count += 1;
                total_size += entry.size_bytes;

                // Track size by file type
                let ext = entry.file_type.clone();
                *size_by_type.entry(ext).or_insert(0) += entry.size_bytes;

                // Track size by category
                let category = Self::categorize_file_type(&entry.path);
                let stats = category_stats.entry(category.clone()).or_insert_with(|| FileCategoryStats {
                    category: category.clone(),
                    total_size: 0,
                    file_count: 0,
                });
                stats.total_size += entry.size_bytes;
                stats.file_count += 1;

                // Keep track of files for sorting
                if entry.size_bytes >= self.min_file_size {
                    files.push(entry);
                }
            }
        })?;

        // Sort by size and take top N
        files.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        files.truncate(top_n);

        Ok(DirectoryAnalysis {
            path: path.to_path_buf(),
            total_size,
            file_count,
            dir_count,
            largest_files: files,
            size_by_type,
            category_stats,
        })
    }

    /// Analyze a directory with progress reporting and cancellation support
    pub fn analyze_directory_with_progress<P: AsRef<Path>>(
        &self,
        path: P,
        top_n: usize,
        progress_callback: Option<ProgressCallback>,
        cancel_flag: Arc<AtomicBool>,
    ) -> io::Result<DirectoryAnalysis> {
        let path = path.as_ref();
        let mut files = Vec::new();
        let mut total_size = 0u64;
        let mut file_count = 0usize;
        let mut dir_count = 0usize;
        let mut size_by_type: HashMap<String, u64> = HashMap::new();
        let mut category_stats: HashMap<FileCategory, FileCategoryStats> = HashMap::new();

        let files_processed = Arc::new(AtomicUsize::new(0));
        let bytes_processed = Arc::new(AtomicUsize::new(0));

        // Start timeout timer
        let start_time = Instant::now();

        self.walk_directory_cancellable(
            path,
            0,
            &mut |entry: FileEntry| {
                if entry.is_dir {
                    dir_count += 1;
                } else {
                    file_count += 1;
                    total_size += entry.size_bytes;

                    // Track size by file type
                    let ext = entry.file_type.clone();
                    *size_by_type.entry(ext).or_insert(0) += entry.size_bytes;

                    // Track size by category
                    let category = Self::categorize_file_type(&entry.path);
                    let stats = category_stats.entry(category.clone()).or_insert_with(|| FileCategoryStats {
                        category: category.clone(),
                        total_size: 0,
                        file_count: 0,
                    });
                    stats.total_size += entry.size_bytes;
                    stats.file_count += 1;

                    // Keep track of files for sorting
                    if entry.size_bytes >= self.min_file_size {
                        files.push(entry.clone());
                    }

                    // Update progress
                    let count = files_processed.fetch_add(1, Ordering::Relaxed) + 1;
                    let bytes = bytes_processed.fetch_add(entry.size_bytes as usize, Ordering::Relaxed) as u64 + entry.size_bytes;

                    if let Some(ref callback) = progress_callback {
                        if count % 100 == 0 {
                            callback(count, bytes);
                        }
                    }
                }
            },
            cancel_flag.clone(),
            start_time,
        )?;

        // Check if cancelled
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
        }

        // Sort by size and take top N
        files.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
        files.truncate(top_n);

        Ok(DirectoryAnalysis {
            path: path.to_path_buf(),
            total_size,
            file_count,
            dir_count,
            largest_files: files,
            size_by_type,
            category_stats,
        })
    }

    /// Find duplicate files based on size and content hash
    pub fn find_duplicates<P: AsRef<Path>>(
        &self,
        path: P,
    ) -> io::Result<Vec<DuplicateGroup>> {
        let path = path.as_ref();
        let mut files_by_size: HashMap<u64, Vec<PathBuf>> = HashMap::new();

        // First pass: group by size
        self.walk_directory(path, 0, &mut |entry: FileEntry| {
            if !entry.is_dir && entry.size_bytes >= self.min_file_size {
                files_by_size
                    .entry(entry.size_bytes)
                    .or_insert_with(Vec::new)
                    .push(entry.path);
            }
        })?;

        // Second pass: hash files with same size
        let mut duplicates = Vec::new();

        for (size, paths) in files_by_size.iter() {
            if paths.len() < 2 {
                continue;
            }

            // Group by hash
            let mut by_hash: HashMap<String, Vec<PathBuf>> = HashMap::new();

            for path in paths {
                if let Ok(hash) = self.hash_file_fast(path) {
                    by_hash.entry(hash).or_insert_with(Vec::new).push(path.clone());
                }
            }

            // Identify duplicate groups
            for (hash, files) in by_hash {
                if files.len() >= 2 {
                    let total_wasted = *size * (files.len() as u64 - 1);
                    duplicates.push(DuplicateGroup {
                        hash,
                        size_bytes: *size,
                        files,
                        total_wasted_space: total_wasted,
                    });
                }
            }
        }

        // Sort by wasted space
        duplicates.sort_by(|a, b| b.total_wasted_space.cmp(&a.total_wasted_space));

        Ok(duplicates)
    }

    /// Find duplicates with progress reporting and cancellation support
    pub fn find_duplicates_with_progress<P: AsRef<Path>>(
        &self,
        path: P,
        progress_callback: Option<ProgressCallback>,
        cancel_flag: Arc<AtomicBool>,
    ) -> io::Result<Vec<DuplicateGroup>> {
        let path = path.as_ref();
        let mut files_by_size: HashMap<u64, Vec<PathBuf>> = HashMap::new();

        let files_processed = Arc::new(AtomicUsize::new(0));
        let bytes_processed = Arc::new(AtomicUsize::new(0));

        // Start timeout timer
        let start_time = Instant::now();

        // First pass: group by size
        self.walk_directory_cancellable(
            path,
            0,
            &mut |entry: FileEntry| {
                if !entry.is_dir && entry.size_bytes >= self.min_file_size {
                    files_by_size
                        .entry(entry.size_bytes)
                        .or_insert_with(Vec::new)
                        .push(entry.path);

                    let count = files_processed.fetch_add(1, Ordering::Relaxed) + 1;
                    if let Some(ref callback) = progress_callback {
                        if count % 50 == 0 {
                            callback(count, 0);
                        }
                    }
                }
            },
            cancel_flag.clone(),
            start_time,
        )?;

        if cancel_flag.load(Ordering::Relaxed) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
        }

        // Check timeout
        if start_time.elapsed() > Duration::from_secs(SCAN_TIMEOUT_SECS) {
            return Err(io::Error::new(io::ErrorKind::TimedOut, "Scan exceeded time limit"));
        }

        // Second pass: hash files with same size (PARALLELIZED with rayon)
        let mut duplicates = Vec::new();
        let total_to_hash: usize = files_by_size.values().filter(|v| v.len() >= 2).map(|v| v.len()).sum();
        let hashed = Arc::new(AtomicUsize::new(0));

        // Notify start of hashing phase with special marker
        // We use count = total files scanned, bytes = 0xFFFFFFFF to signal phase transition
        if let Some(ref callback) = progress_callback {
            let total_scanned = files_processed.load(Ordering::Relaxed);
            callback(total_scanned, 0xFFFFFFFF);
        }

        for (size, paths) in files_by_size.iter() {
            if cancel_flag.load(Ordering::Relaxed) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
            }

            // Check timeout periodically
            if start_time.elapsed() > Duration::from_secs(SCAN_TIMEOUT_SECS) {
                return Err(io::Error::new(io::ErrorKind::TimedOut, "Scan exceeded time limit"));
            }

            if paths.len() < 2 {
                continue;
            }

            // PARALLEL HASHING: Use rayon to hash files in parallel
            let hash_results: Vec<_> = paths
                .par_iter()
                .filter_map(|path| {
                    // Check cancellation in parallel workers
                    if cancel_flag.load(Ordering::Relaxed) {
                        return None;
                    }

                    // Hash the file
                    match self.hash_file_fast(path) {
                        Ok(hash) => {
                            let count = hashed.fetch_add(1, Ordering::Relaxed) + 1;
                            if let Some(ref callback) = progress_callback {
                                if count % 10 == 0 {
                                    // Send: current_hashed | (total_to_hash << 32) as special encoding
                                    // This allows Swift to know both current and total
                                    let progress_info = ((total_to_hash as u64) << 32) | (count as u64);
                                    callback(count, progress_info);
                                }
                            }
                            Some((hash, path.clone()))
                        }
                        Err(_) => None, // Skip files that can't be hashed (fail-safe)
                    }
                })
                .collect();

            // Check if operation was cancelled during parallel hashing
            if cancel_flag.load(Ordering::Relaxed) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
            }

            // Group by hash
            let mut by_hash: HashMap<String, Vec<PathBuf>> = HashMap::new();
            for (hash, path) in hash_results {
                by_hash.entry(hash).or_insert_with(Vec::new).push(path);
            }

            // Identify duplicate groups
            for (hash, files) in by_hash {
                if files.len() >= 2 {
                    let total_wasted = *size * (files.len() as u64 - 1);
                    duplicates.push(DuplicateGroup {
                        hash,
                        size_bytes: *size,
                        files,
                        total_wasted_space: total_wasted,
                    });
                }
            }
        }

        // Sort by wasted space
        duplicates.sort_by(|a, b| b.total_wasted_space.cmp(&a.total_wasted_space));

        Ok(duplicates)
    }

    /// Walk directory recursively
    fn walk_directory<F>(
        &self,
        path: &Path,
        depth: usize,
        callback: &mut F,
    ) -> io::Result<()>
    where
        F: FnMut(FileEntry),
    {
        if depth > self.max_depth {
            return Ok(());
        }

        // Security: Check if path is excluded (fail-safe: deny by default)
        if self.is_path_excluded(path) {
            return Ok(()); // Silently skip excluded paths
        }

        let entries = match fs::read_dir(path) {
            Ok(entries) => entries,
            Err(_) => return Ok(()), // Skip directories we can't read (fail-safe)
        };

        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };

            let path = entry.path();

            // Security: Skip excluded paths (fail-safe)
            if self.is_path_excluded(&path) {
                continue;
            }

            let metadata = match if self.follow_symlinks {
                fs::metadata(&path)
            } else {
                fs::symlink_metadata(&path)
            } {
                Ok(m) => m,
                Err(_) => continue, // Skip if we can't read metadata (fail-safe)
            };

            let is_dir = metadata.is_dir();

            // Security: Skip symlinks if not following them (prevent circular symlinks)
            if !self.follow_symlinks && metadata.file_type().is_symlink() {
                continue;
            }

            // Skip cloud storage placeholder files (OneDrive, iCloud, Dropbox, etc.)
            if !is_dir && self.is_cloud_placeholder(&path, &metadata) {
                continue;
            }

            let size = metadata.len();
            let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);

            let file_type = if is_dir {
                "directory".to_string()
            } else {
                path.extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("no_extension")
                    .to_string()
            };

            let file_entry = FileEntry {
                path: path.clone(),
                size_bytes: size,
                is_dir,
                modified,
                file_type,
            };

            callback(file_entry);

            // Recurse into directories
            if is_dir {
                let _ = self.walk_directory(&path, depth + 1, callback);
            }
        }

        Ok(())
    }

    /// Walk directory recursively with cancellation support and timeout
    fn walk_directory_cancellable<F>(
        &self,
        path: &Path,
        depth: usize,
        callback: &mut F,
        cancel_flag: Arc<AtomicBool>,
        start_time: Instant,
    ) -> io::Result<()>
    where
        F: FnMut(FileEntry),
    {
        // Check for cancellation
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
        }

        // Check for timeout (fail-safe: deny operation if timeout exceeded)
        if start_time.elapsed() > Duration::from_secs(SCAN_TIMEOUT_SECS) {
            return Err(io::Error::new(io::ErrorKind::TimedOut, "Scan exceeded time limit"));
        }

        if depth > self.max_depth {
            return Ok(());
        }

        // Security: Check if path is excluded (fail-safe: deny by default)
        if self.is_path_excluded(path) {
            return Ok(()); // Silently skip excluded paths
        }

        let entries = match fs::read_dir(path) {
            Ok(entries) => entries,
            Err(_) => return Ok(()), // Skip directories we can't read (fail-safe)
        };

        for entry in entries {
            // Check for cancellation periodically
            if cancel_flag.load(Ordering::Relaxed) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
            }

            // Periodic timeout check
            if start_time.elapsed() > Duration::from_secs(SCAN_TIMEOUT_SECS) {
                return Err(io::Error::new(io::ErrorKind::TimedOut, "Scan exceeded time limit"));
            }

            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue, // Skip entries we can't read (fail-safe)
            };

            let path = entry.path();

            // Security: Skip excluded paths (fail-safe)
            if self.is_path_excluded(&path) {
                continue;
            }

            let metadata = match if self.follow_symlinks {
                fs::metadata(&path)
            } else {
                fs::symlink_metadata(&path)
            } {
                Ok(m) => m,
                Err(_) => continue, // Skip if we can't read metadata (fail-safe)
            };

            let is_dir = metadata.is_dir();

            // Security: Skip symlinks if not following them (prevent circular symlinks)
            if !self.follow_symlinks && metadata.file_type().is_symlink() {
                continue;
            }

            // Skip cloud storage placeholder files (OneDrive, iCloud, Dropbox, etc.)
            if !is_dir && self.is_cloud_placeholder(&path, &metadata) {
                continue;
            }

            let size = metadata.len();
            let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);

            let file_type = if is_dir {
                "directory".to_string()
            } else {
                path.extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("no_extension")
                    .to_string()
            };

            let file_entry = FileEntry {
                path: path.clone(),
                size_bytes: size,
                is_dir,
                modified,
                file_type,
            };

            callback(file_entry);

            // Recurse into directories
            if is_dir {
                let _ = self.walk_directory_cancellable(&path, depth + 1, callback, cancel_flag.clone(), start_time);
            }
        }

        Ok(())
    }

    /// Fast file hashing using first/middle/last chunks with optional caching
    /// This is much faster than hashing the entire file for large files
    /// Thread-safe for use with rayon parallel iterators
    fn hash_file_fast(&self, path: &Path) -> io::Result<String> {
        use std::io::Read;

        let metadata = fs::metadata(path)?;
        let file_size = metadata.len();
        let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);

        // Check cache first (thread-safe access)
        if let Some(ref cache) = self.hash_cache {
            if let Some(cached_hash) = cache.get(path, modified) {
                return Ok(cached_hash);
            }
        }

        // For small files (< 1MB), hash the entire file
        let hash = if file_size < 1_048_576 {
            self.hash_file_full(path)?
        } else {
            // For large files, hash first/middle/last chunks for speed
            let mut file = fs::File::open(path)?;
            let mut hasher = blake3::Hasher::new();

            // First chunk
            let mut buffer = vec![0u8; HASH_CHUNK_SIZE];
            let n = file.read(&mut buffer)?;
            hasher.update(&buffer[..n]);

            // Middle chunk
            if file_size > HASH_CHUNK_SIZE as u64 * 2 {
                use std::io::Seek;
                let middle = file_size / 2 - (HASH_CHUNK_SIZE as u64 / 2);
                file.seek(std::io::SeekFrom::Start(middle))?;
                let n = file.read(&mut buffer)?;
                hasher.update(&buffer[..n]);
            }

            // Last chunk
            if file_size > HASH_CHUNK_SIZE as u64 {
                use std::io::Seek;
                let last_pos = file_size.saturating_sub(HASH_CHUNK_SIZE as u64);
                file.seek(std::io::SeekFrom::Start(last_pos))?;
                let n = file.read(&mut buffer)?;
                hasher.update(&buffer[..n]);
            }

            hasher.finalize().to_hex().to_string()
        };

        // Store in cache (thread-safe write)
        if let Some(ref cache) = self.hash_cache {
            cache.insert(path.to_path_buf(), modified, hash.clone());
        }

        Ok(hash)
    }

    /// Full file hashing (for small files or verification)
    fn hash_file_full(&self, path: &Path) -> io::Result<String> {
        let data = fs::read(path)?;
        let hash = blake3::hash(&data);
        Ok(hash.to_hex().to_string())
    }
}

impl Default for FileAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    use tempfile::TempDir;

    #[test]
    fn test_analyze_directory() {
        let temp = TempDir::new().unwrap();
        let temp_path = temp.path();

        // Create test files
        let mut file1 = File::create(temp_path.join("large.txt")).unwrap();
        file1.write_all(&vec![b'a'; 1000]).unwrap();

        let mut file2 = File::create(temp_path.join("small.txt")).unwrap();
        file2.write_all(b"hello").unwrap();

        // Use analyzer with empty excluded paths for testing
        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
        let analysis = analyzer.analyze_directory(temp_path, 10).unwrap();

        assert_eq!(analysis.file_count, 2);
        assert!(analysis.total_size >= 1005);
        assert!(!analysis.largest_files.is_empty());
    }

    #[test]
    fn test_find_duplicates() {
        let temp = TempDir::new().unwrap();
        let temp_path = temp.path();

        // Create identical files
        let content = b"duplicate content";
        let mut file1 = File::create(temp_path.join("dup1.txt")).unwrap();
        file1.write_all(content).unwrap();

        let mut file2 = File::create(temp_path.join("dup2.txt")).unwrap();
        file2.write_all(content).unwrap();

        let mut file3 = File::create(temp_path.join("unique.txt")).unwrap();
        file3.write_all(b"different content").unwrap();

        // Use analyzer with empty excluded paths for testing
        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
        let duplicates = analyzer.find_duplicates(temp_path).unwrap();

        assert_eq!(duplicates.len(), 1);
        assert_eq!(duplicates[0].files.len(), 2);
    }

    #[test]
    fn test_cancelation() {
        let temp_dir = TempDir::new().unwrap();

        // Create a few files
        for i in 0..10 {
            std::fs::write(
                temp_dir.path().join(format!("file{}.txt", i)),
                format!("content {}", i)
            ).unwrap();
        }

        // Test that cancellation flag is checked
        let cancel_flag = Arc::new(AtomicBool::new(true)); // Pre-cancelled
        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);

        let result = analyzer.analyze_directory_with_progress(
            temp_dir.path(),
            100,
            None,
            cancel_flag
        );

        // Should be interrupted immediately since flag is pre-set
        assert!(result.is_err(), "Analysis should be cancelled");
        if let Err(e) = result {
            assert_eq!(e.kind(), io::ErrorKind::Interrupted);
        }
    }

    #[test]
    fn test_progress_callback() {
        let temp_dir = TempDir::new().unwrap();
        let progress_calls = Arc::new(parking_lot::Mutex::new(Vec::new()));

        // Create enough files to trigger progress callback (callback fires every 100 files)
        for i in 0..150 {
            std::fs::write(
                temp_dir.path().join(format!("file{}.txt", i)),
                vec![0u8; 1024]
            ).unwrap();
        }

        let progress_clone = progress_calls.clone();
        let callback: ProgressCallback = Arc::new(move |current, total| {
            progress_clone.lock().push((current, total));
        });

        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
        let cancel_flag = Arc::new(AtomicBool::new(false));

        let _result = analyzer.analyze_directory_with_progress(
            temp_dir.path(),
            10,
            Some(callback),
            cancel_flag
        );

        let calls = progress_calls.lock();
        assert!(!calls.is_empty(), "Progress callback should be called");
        // Verify that progress values are reasonable
        for (count, bytes) in calls.iter() {
            assert!(*count > 0, "Progress count should be positive");
            assert!(*bytes > 0, "Progress bytes should be positive");
        }
    }

    #[test]
    fn test_file_categorization() {
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("test.pdf")), FileCategory::Documents);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("photo.jpg")), FileCategory::Media);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("video.mp4")), FileCategory::Media);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("song.mp3")), FileCategory::Media);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("script.rs")), FileCategory::Code);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("script.py")), FileCategory::Code);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("data.json")), FileCategory::Code);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("archive.zip")), FileCategory::Archives);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("archive.tar")), FileCategory::Archives);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("app.exe")), FileCategory::Applications);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("random.xyz")), FileCategory::Other);
        assert_eq!(FileAnalyzer::categorize_file_type(Path::new("no_ext")), FileCategory::Other);
    }

    #[test]
    fn test_hash_cache() {
        let temp_dir = TempDir::new().unwrap();
        let file_path = temp_dir.path().join("test.txt");
        std::fs::write(&file_path, b"test content").unwrap();

        let cache = HashCache::new(100);
        let metadata = std::fs::metadata(&file_path).unwrap();
        let modified = metadata.modified().unwrap();

        // First call should compute hash
        let hash1 = "test_hash".to_string();
        cache.insert(file_path.clone(), modified, hash1.clone());

        // Second call should use cache
        let hash2 = cache.get(&file_path, modified).unwrap();

        assert_eq!(hash1, hash2);
        assert_eq!(cache.len(), 1);
        assert!(!cache.is_empty());
    }

    #[test]
    fn test_hash_cache_eviction() {
        let cache = HashCache::new(3);
        let temp_dir = TempDir::new().unwrap();

        // Add 3 entries (within limit)
        for i in 0..3 {
            let path = temp_dir.path().join(format!("file{}.txt", i));
            std::fs::write(&path, format!("content {}", i)).unwrap();
            let metadata = std::fs::metadata(&path).unwrap();
            cache.insert(path, metadata.modified().unwrap(), format!("hash{}", i));
        }

        assert_eq!(cache.len(), 3);

        // Add one more entry (exceeds limit, should trigger eviction)
        let path = temp_dir.path().join("file3.txt");
        std::fs::write(&path, "content 3").unwrap();
        let metadata = std::fs::metadata(&path).unwrap();
        cache.insert(path.clone(), metadata.modified().unwrap(), "hash3".to_string());

        // Cache should have been cleared and only new entry added
        assert_eq!(cache.len(), 1);
    }

    #[test]
    fn test_hash_cache_clear() {
        let cache = HashCache::new(100);
        let temp_dir = TempDir::new().unwrap();

        let path = temp_dir.path().join("test.txt");
        std::fs::write(&path, b"content").unwrap();
        let metadata = std::fs::metadata(&path).unwrap();

        cache.insert(path, metadata.modified().unwrap(), "hash".to_string());
        assert_eq!(cache.len(), 1);

        cache.clear();
        assert_eq!(cache.len(), 0);
        assert!(cache.is_empty());
    }

    #[test]
    fn test_security_path_validation() {
        let temp_dir = TempDir::new().unwrap();
        let root = temp_dir.path();

        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);

        // Safe path within root
        let safe_path = root.join("subdir").join("file.txt");
        std::fs::create_dir_all(safe_path.parent().unwrap()).unwrap();
        std::fs::write(&safe_path, b"test").unwrap();
        assert!(analyzer.is_safe_path(&safe_path, root));

        // Path outside root should be unsafe
        let outside_path = PathBuf::from("/tmp/outside");
        assert!(!analyzer.is_safe_path(&outside_path, root));
    }

    #[test]
    fn test_excluded_paths() {
        let analyzer = FileAnalyzer::new();

        // Test default excluded paths (macOS system directories)
        assert!(analyzer.is_path_excluded(Path::new("/System/Library")));
        assert!(analyzer.is_path_excluded(Path::new("/private/var/log")));
        assert!(analyzer.is_path_excluded(Path::new("/dev/null")));
        assert!(analyzer.is_path_excluded(Path::new("/.Spotlight-V100/data")));
        assert!(analyzer.is_path_excluded(Path::new("/.DocumentRevisions-V100")));

        // Test non-excluded paths
        assert!(!analyzer.is_path_excluded(Path::new("/Users/test/Documents")));
        assert!(!analyzer.is_path_excluded(Path::new("/Applications")));
    }

    #[test]
    fn test_custom_excluded_paths() {
        let custom_paths = vec![
            PathBuf::from("/custom/excluded"),
            PathBuf::from("/another/excluded"),
        ];

        let analyzer = FileAnalyzer::new().with_excluded_paths(custom_paths);

        assert!(analyzer.is_path_excluded(Path::new("/custom/excluded/file.txt")));
        assert!(analyzer.is_path_excluded(Path::new("/another/excluded/subdir")));
        assert!(!analyzer.is_path_excluded(Path::new("/custom/allowed")));
    }

    #[test]
    fn test_category_stats() {
        let temp_dir = TempDir::new().unwrap();

        // Create files of different categories
        std::fs::write(temp_dir.path().join("doc1.pdf"), vec![0u8; 1024]).unwrap();
        std::fs::write(temp_dir.path().join("doc2.txt"), vec![0u8; 512]).unwrap();
        std::fs::write(temp_dir.path().join("image.jpg"), vec![0u8; 2048]).unwrap();
        std::fs::write(temp_dir.path().join("code.rs"), vec![0u8; 256]).unwrap();

        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
        let analysis = analyzer.analyze_directory(temp_dir.path(), 10).unwrap();

        // Verify category stats exist
        assert!(analysis.category_stats.contains_key(&FileCategory::Documents));
        assert!(analysis.category_stats.contains_key(&FileCategory::Media));
        assert!(analysis.category_stats.contains_key(&FileCategory::Code));

        // Verify document category stats
        let doc_stats = &analysis.category_stats[&FileCategory::Documents];
        assert_eq!(doc_stats.file_count, 2);
        assert_eq!(doc_stats.total_size, 1536); // 1024 + 512

        // Verify media category stats
        let media_stats = &analysis.category_stats[&FileCategory::Media];
        assert_eq!(media_stats.file_count, 1);
        assert_eq!(media_stats.total_size, 2048);
    }

    #[test]
    fn test_duplicate_detection_with_progress() {
        let temp_dir = TempDir::new().unwrap();
        let progress_calls = Arc::new(parking_lot::Mutex::new(Vec::new()));

        // Create enough duplicate files to trigger progress callback (fires every 10 hashes)
        let content = b"duplicate content for testing";
        for i in 0..15 {
            std::fs::write(
                temp_dir.path().join(format!("dup{}.txt", i)),
                content
            ).unwrap();
        }

        // Create unique files to have multiple groups
        for i in 0..5 {
            std::fs::write(
                temp_dir.path().join(format!("unique{}.txt", i)),
                format!("unique content {}", i)
            ).unwrap();
        }

        let progress_clone = progress_calls.clone();
        let callback: ProgressCallback = Arc::new(move |current, _total| {
            progress_clone.lock().push(current);
        });

        let analyzer = FileAnalyzer::new()
            .with_excluded_paths(vec![])
            .enable_default_cache();

        let cancel_flag = Arc::new(AtomicBool::new(false));
        let duplicates = analyzer.find_duplicates_with_progress(
            temp_dir.path(),
            Some(callback),
            cancel_flag
        ).unwrap();

        // Verify duplicates found
        assert_eq!(duplicates.len(), 1);
        assert_eq!(duplicates[0].files.len(), 15);

        // Verify progress was reported (with enough files, callback should fire)
        let calls = progress_calls.lock();
        assert!(!calls.is_empty(), "Progress callback should be called during duplicate detection");
    }

    #[test]
    fn test_min_file_size_filter() {
        let temp_dir = TempDir::new().unwrap();

        // Create files of different sizes
        std::fs::write(temp_dir.path().join("small.txt"), vec![0u8; 100]).unwrap();
        std::fs::write(temp_dir.path().join("medium.txt"), vec![0u8; 1000]).unwrap();
        std::fs::write(temp_dir.path().join("large.txt"), vec![0u8; 10000]).unwrap();

        // Analyze with minimum size filter
        let analyzer = FileAnalyzer::new()
            .with_excluded_paths(vec![])
            .with_min_file_size(500);

        let analysis = analyzer.analyze_directory(temp_dir.path(), 10).unwrap();

        // Total count includes all files
        assert_eq!(analysis.file_count, 3);

        // Largest files should only include files >= 500 bytes
        assert_eq!(analysis.largest_files.len(), 2);
        assert!(analysis.largest_files.iter().all(|f| f.size_bytes >= 500));
    }

    #[test]
    fn test_timeout_protection() {
        // This test verifies that the timeout mechanism exists
        // We can't easily test the actual timeout without creating a massive directory structure
        let temp_dir = TempDir::new().unwrap();

        // Create a few files
        for i in 0..5 {
            std::fs::write(
                temp_dir.path().join(format!("file{}.txt", i)),
                vec![0u8; 100]
            ).unwrap();
        }

        let analyzer = FileAnalyzer::new().with_excluded_paths(vec![]);
        let cancel_flag = Arc::new(AtomicBool::new(false));

        // Should complete without timeout
        let result = analyzer.analyze_directory_with_progress(
            temp_dir.path(),
            10,
            None,
            cancel_flag
        );

        assert!(result.is_ok());
    }
}
