use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use std::io;

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub path: PathBuf,
    pub size_bytes: u64,
    pub is_dir: bool,
    pub modified: SystemTime,
    pub file_type: String,
}

#[derive(Debug, Clone)]
pub struct DirectoryAnalysis {
    pub path: PathBuf,
    pub total_size: u64,
    pub file_count: usize,
    pub dir_count: usize,
    pub largest_files: Vec<FileEntry>,
    pub size_by_type: HashMap<String, u64>,
}

#[derive(Debug, Clone)]
pub struct DuplicateGroup {
    pub hash: String,
    pub size_bytes: u64,
    pub files: Vec<PathBuf>,
    pub total_wasted_space: u64,
}

pub struct FileAnalyzer {
    max_depth: usize,
    min_file_size: u64,
    follow_symlinks: bool,
}

impl FileAnalyzer {
    pub fn new() -> Self {
        Self {
            max_depth: 10,
            min_file_size: 0,
            follow_symlinks: false,
        }
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

        self.walk_directory(path, 0, &mut |entry: FileEntry| {
            if entry.is_dir {
                dir_count += 1;
            } else {
                file_count += 1;
                total_size += entry.size_bytes;

                // Track size by file type
                let ext = entry.file_type.clone();
                *size_by_type.entry(ext).or_insert(0) += entry.size_bytes;

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

        let entries = match fs::read_dir(path) {
            Ok(entries) => entries,
            Err(_) => return Ok(()), // Skip directories we can't read
        };

        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };

            let path = entry.path();
            let metadata = match if self.follow_symlinks {
                fs::metadata(&path)
            } else {
                fs::symlink_metadata(&path)
            } {
                Ok(m) => m,
                Err(_) => continue,
            };

            let is_dir = metadata.is_dir();
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

    /// Fast file hashing using first/middle/last chunks
    /// This is much faster than hashing the entire file for large files
    fn hash_file_fast(&self, path: &Path) -> io::Result<String> {
        use std::io::Read;

        let file_size = fs::metadata(path)?.len();

        // For small files (< 1MB), hash the entire file
        if file_size < 1_048_576 {
            return self.hash_file_full(path);
        }

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

        Ok(hasher.finalize().to_hex().to_string())
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
