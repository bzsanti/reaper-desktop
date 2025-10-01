// Test program that uses the library directly
mod disk_monitor {
    include!("../disk_monitor.rs");
}

use disk_monitor::DiskMonitor;

fn main() {
    println!("=== Disk Monitor Test ===\n");

    let mut monitor = DiskMonitor::new();
    monitor.refresh();

    let all_disks = monitor.get_all_disks();

    println!("Found {} disk(s):\n", all_disks.len());

    for disk in &all_disks {
        println!("Mount Point: {}", disk.mount_point);
        println!("  Name: {}", disk.name);
        println!("  File System: {}", disk.file_system);
        println!("  Type: {}", disk.disk_type.as_str());
        println!("  Total: {} ({})", disk.total_bytes, DiskMonitor::format_bytes(disk.total_bytes));
        println!("  Used: {} ({})", disk.used_bytes, DiskMonitor::format_bytes(disk.used_bytes));
        println!("  Available: {} ({})", disk.available_bytes, DiskMonitor::format_bytes(disk.available_bytes));
        println!("  Usage: {:.2}%", disk.usage_percent);
        println!("  Removable: {}", disk.is_removable);
        println!();
    }

    if let Some(primary) = monitor.get_primary_disk() {
        println!("=== Primary Disk (/) ===");
        println!("Name: {}", primary.name);
        println!("Total: {} ({})", primary.total_bytes, DiskMonitor::format_bytes(primary.total_bytes));
        println!("Used: {} ({})", primary.used_bytes, DiskMonitor::format_bytes(primary.used_bytes));
        println!("Available: {} ({})", primary.available_bytes, DiskMonitor::format_bytes(primary.available_bytes));
        println!("Usage: {:.2}%", primary.usage_percent);

        // Verification
        let calc_used = primary.total_bytes - primary.available_bytes;
        println!("\nVerification:");
        println!("  Total - Available = {} (should match Used: {})", calc_used, primary.used_bytes);
        println!("  Match: {}", calc_used == primary.used_bytes);
    } else {
        println!("ERROR: Primary disk not found!");
    }
}
