# Boot Media Write Reduction Optimizations

## Overview
This document outlines the optimizations implemented to significantly reduce reads and writes to your USB boot media, extending its lifespan.

## Key Optimizations Implemented

### 1. RAM Disk (tmpfs) for Application Code
- **PharmaStock Application**: Moved to `/opt/pharmastock` on a 2GB tmpfs
- **Setup Repository**: Moved to `/opt/new-sight-pi-setup` on a 1GB tmpfs
- **Cache Directories**: Separate cache directories for version tracking and dependencies
- **Benefits**: All application code runs in RAM, zero writes to boot media

### 2. Binary-Based Download System
- **Tarball Downloads**: Using GitHub tarball downloads instead of git clone
- **Version Caching**: Smart version checking to avoid unnecessary downloads
- **Minimal API Calls**: Using GitHub API for version checks (minimal data transfer)
- **Efficient Extraction**: Direct extraction to RAM without intermediate writes

### 3. Enhanced Logging Configuration
- **Volatile Storage**: Set `Storage=volatile` in journald.conf
- **Reduced Log Sizes**: 
  - SystemMaxUse: 25M (reduced from 50M)
  - SystemMaxFileSize: 5M (reduced from 10M)
  - MaxRetentionSec: 7d (reduced from 14d)
- **Compression**: Enabled log compression
- **Sync Frequency**: Reduced to 300 seconds

### 4. Streamlined tmpfs Mounts (16GB RAM Optimized)
Added minimal, efficient tmpfs mounts for high-write directories:
- `/tmp` - 1GB (system temporary files)
- `/var/log` - 500MB (system logs)
- `/var/cache` - 2GB (unified cache directory)
- `/opt/pharmastock` - 2GB (application code)
- `/opt/new-sight-pi-setup` - 1GB (setup scripts)
- `/opt/cache` - 1GB (unified application cache)

### 5. Zram Swap Configuration
- **RAM-based swap**: 4GB (25% of 16GB RAM)
- **Compression**: LZ4 algorithm for efficient memory usage
- **Priority**: High priority to avoid disk swap

### 6. log2ram Integration
- Existing log2ram configuration maintained
- Works in conjunction with new tmpfs mounts
- Provides additional log write protection

## Memory Usage (16GB RAM Optimized)
Total additional RAM usage: ~6.5GB
- PharmaStock app: 2GB
- Setup repository: 1GB
- Unified cache: 1GB
- System tmpfs mounts: 3.5GB
- Zram swap: 4GB (25% of 16GB)

## Benefits
1. **Zero writes to boot media** for application code
2. **Minimal writes** for system operations
3. **Faster performance** due to RAM-based operations
4. **Extended USB drive lifespan**
5. **Reduced wear** on boot media
6. **Efficient updates** with smart version checking
7. **Faster downloads** using tarballs instead of git operations
8. **Better caching** with dependency hash checking

## Considerations
- Requires sufficient RAM (recommend 2GB+ for Pi)
- Application data is lost on reboot (code is re-downloaded)
- Logs are not persistent across reboots
- Temporary files are cleared on reboot

## Monitoring
To monitor tmpfs usage:
```bash
df -h | grep tmpfs
```

To check mount points:
```bash
mount | grep tmpfs
```

## Recovery
If you need to disable these optimizations:
1. Comment out the tmpfs mount lines in `/etc/fstab`
2. Reboot the system
3. The system will fall back to normal disk-based operations
