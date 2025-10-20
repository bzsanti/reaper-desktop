use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use std::io;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use parking_lot::RwLock;

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

        // Simple cache eviction: clear if too large
        if cache.len() >= self.max_entries {
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
            PathBuf::from("/System"),
            PathBuf::from("/private"),
            PathBuf::from("/dev"),
            PathBuf::from("/proc"),
            PathBuf::from("/sys"),
            PathBuf::from("/cores"),
            PathBuf::from("/Volumes"),
            PathBuf::from("/Library/Caches"),
            PathBuf::from("/Library/Logs"),
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
        )?;

        if cancel_flag.load(Ordering::Relaxed) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
        }

        // Second pass: hash files with same size
        let mut duplicates = Vec::new();
        let total_to_hash: usize = files_by_size.values().filter(|v| v.len() >= 2).map(|v| v.len()).sum();
        let hashed = Arc::new(AtomicUsize::new(0));

        for (size, paths) in files_by_size.iter() {
            if cancel_flag.load(Ordering::Relaxed) {
                return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
            }

            if paths.len() < 2 {
                continue;
            }

            // Group by hash
            let mut by_hash: HashMap<String, Vec<PathBuf>> = HashMap::new();

            for path in paths {
                if cancel_flag.load(Ordering::Relaxed) {
                    return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
                }

                if let Ok(hash) = self.hash_file_fast(path) {
                    by_hash.entry(hash).or_insert_with(Vec::new).push(path.clone());
                }

                let count = hashed.fetch_add(1, Ordering::Relaxed) + 1;
                if let Some(ref callback) = progress_callback {
                    if count % 10 == 0 {
                        let bytes = bytes_processed.load(Ordering::Relaxed) as u64;
                        callback(count * 100 / total_to_hash.max(1), bytes);
                    }
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

    /// Walk directory recursively with cancellation support
    fn walk_directory_cancellable<F>(
        &self,
        path: &Path,
        depth: usize,
        callback: &mut F,
        cancel_flag: Arc<AtomicBool>,
    ) -> io::Result<()>
    where
        F: FnMut(FileEntry),
    {
        // Check for cancellation
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "Operation cancelled"));
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
                let _ = self.walk_directory_cancellable(&path, depth + 1, callback, cancel_flag.clone());
            }
        }

        Ok(())
    }

    /// Fast file hashing using first/middle/last chunks with optional caching
    /// This is much faster than hashing the entire file for large files
    fn hash_file_fast(&self, path: &Path) -> io::Result<String> {
        use std::io::Read;

        let metadata = fs::metadata(path)?;
        let file_size = metadata.len();
        let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);

        // Check cache first
        if let Some(ref cache) = self.hash_cache {
            if let Some(cached_hash) = cache.get(path, modified) {
                return Ok(cached_hash);
            }
        }

        // For small files (< 1MB), hash the entire file
        let hash = if file_size < 1_048_576 {
            self.hash_file_full(path)?
        } else {
            // For large files, hash first 8KB, middle 8KB, and last 8KB
            let mut file = fs::File::open(path)?;
            let chunk_size = 8192;
            let mut hasher = blake3::Hasher::new();

            // First chunk
            let mut buffer = vec![0u8; chunk_size];
            let n = file.read(&mut buffer)?;
            hasher.update(&buffer[..n]);

            // Middle chunk
            if file_size > chunk_size as u64 * 2 {
                use std::io::Seek;
                let middle = file_size / 2 - (chunk_size as u64 / 2);
                file.seek(std::io::SeekFrom::Start(middle))?;
                let n = file.read(&mut buffer)?;
                hasher.update(&buffer[..n]);
            }

            // Last chunk
            if file_size > chunk_size as u64 {
                use std::io::Seek;
                let last_pos = file_size.saturating_sub(chunk_size as u64);
                file.seek(std::io::SeekFrom::Start(last_pos))?;
                let n = file.read(&mut buffer)?;
                hasher.update(&buffer[..n]);
            }

            hasher.finalize().to_hex().to_string()
        };

        // Store in cache
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

        let analyzer = FileAnalyzer::new();
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

        let analyzer = FileAnalyzer::new();
        let duplicates = analyzer.find_duplicates(temp_path).unwrap();

        assert_eq!(duplicates.len(), 1);
        assert_eq!(duplicates[0].files.len(), 2);
    }
}
