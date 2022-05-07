const std = @import("std");
const c = @cImport({
    @cInclude("ff.h");
    @cInclude("diskio.h");
});
const logger = std.log.scoped(.fatfs);

pub const FileSystem = struct {
    const Self = @This();

    raw: c.FATFS,

    pub fn mount(self: *Self, drive: [:0]const u8, force_mount: bool) !void {
        try tryFs(api.mount(&self.raw, drive.ptr, @boolToInt(force_mount)));
    }

    pub fn unmount(drive: [:0]const u8) !void {
        try tryFs(api.unmount(drive.ptr));
    }
};

pub const File = struct {
    const Self = @This();

    raw: c.FIL,

    pub fn create(path: [:0]const u8) !Self {
        var file = Self{ .raw = undefined };
        try tryFs(api.open(&file.raw, path.ptr, c.FA_WRITE | c.FA_CREATE_ALWAYS));
        return file;
    }

    pub fn close(file: *Self) void {
        tryFs(api.close(&file.raw)) catch |e| {
            logger.err("failed to close file: {s}", .{@errorName(e)});
        };
        file.* = undefined;
    }

    pub const WriteError = error{Overflow} || Error;
    pub fn write(file: *Self, data: []const u8) WriteError!usize {
        var written: c_uint = 0;
        try tryFs(api.write(&file.raw, data.ptr, try std.math.cast(c_uint, data.len), &written));
        return written;
    }

    pub const ReadError = error{Overflow} || Error;
    pub fn read(file: *Self, data: []u8) ReadError!usize {
        var written: c_uint = 0;
        try tryFs(api.read(&file.raw, data.ptr, try std.math.cast(c_uint, data.len), &written));
        return written;
    }

    pub const Reader = std.io.Reader(*Self, ReadError, read);
    pub fn reader(file: *Self) Reader {
        return Reader{ .context = file };
    }

    pub const Writer = std.io.Writer(*Self, WriteError, write);
    pub fn writer(file: *Self) Writer {
        return Writer{ .context = file };
    }
};

pub const LBA = c.LBA_t;

pub const Disk = struct {
    const Self = @This();

    getStatusFn: fn (self: *Self) Status,
    initializeFn: fn (self: *Self) Self.Error!Status,
    readFn: fn (self: *Self, buff: [*]u8, sector: c.LBA_t, count: c.UINT) Self.Error!void,
    writeFn: fn (self: *Self, buff: [*]const u8, sector: c.LBA_t, count: c.UINT) Self.Error!void,
    ioctlFn: fn (self: *Self, cmd: IoCtl, buff: [*]u8) Self.Error!void,

    pub fn getStatus(self: *Self) Status {
        return self.getStatusFn(self);
    }

    pub fn initialize(self: *Self) Self.Error!Status {
        return self.initializeFn(self);
    }

    pub fn read(self: *Self, buff: [*]u8, sector: c.LBA_t, count: c.UINT) Self.Error!void {
        return self.readFn(self, buff, sector, count);
    }

    pub fn write(self: *Self, buff: [*]const u8, sector: c.LBA_t, count: c.UINT) Self.Error!void {
        return self.writeFn(self, buff, sector, count);
    }

    pub fn ioctl(self: *Self, cmd: IoCtl, buff: [*]u8) Self.Error!void {
        return self.ioctlFn(self, cmd, buff);
    }

    fn mapResult(value: Self.Error!void) c.DRESULT {
        if (value) |_| {
            return c.RES_OK;
        } else |err| return switch (err) {
            error.IoError => c.RES_ERROR,
            error.WriteProtected => c.RES_WRPRT,
            error.DiskNotReady => c.RES_NOTRDY,
            error.InvalidParameter => c.RES_PARERR,
        };
    }

    pub const Error = error{
        IoError,
        WriteProtected,
        DiskNotReady,
        InvalidParameter,
    };

    pub const Status = struct {
        initialized: bool,
        disk_present: bool,
        write_protected: bool,

        fn toInteger(self: @This()) c.DSTATUS {
            var i: c.DSTATUS = 0;
            if (!self.initialized) i |= @intCast(u8, c.STA_NOINIT);
            if (!self.disk_present) i |= @intCast(u8, c.STA_NODISK);
            if (self.write_protected) i |= @intCast(u8, c.STA_PROTECT);
            return i;
        }
    };
};

pub var disks: [10]?*Disk = .{null} ** 10;

pub const WRITE = c.FA_WRITE;
pub const CREATE_ALWAYS = c.FA_CREATE_ALWAYS;
pub const OK = c.FR_OK;

pub const api = struct {
    pub const open = c.f_open; // Open/Create a file
    pub const close = c.f_close; // Close an open file
    pub const read = c.f_read; // Read data from the file
    pub const write = c.f_write; // Write data to the file
    pub const lseek = c.f_lseek; // Move read/write pointer, Expand size
    pub const truncate = c.f_truncate; // Truncate file size
    pub const sync = c.f_sync; // Flush cached data
    pub const forward = c.f_forward; // Forward data to the stream
    pub const expand = c.f_expand; // Allocate a contiguous block to the file
    pub const gets = c.f_gets; // Read a string
    pub const putc = c.f_putc; // Write a character
    pub const puts = c.f_puts; // Write a string
    pub const printf = c.f_printf; // Write a formatted string
    pub const tell = c.f_tell; // Get current read/write pointer
    pub const eof = c.f_eof; // Test for end-of-file
    pub const size = c.f_size; // Get size
    pub const @"error" = c.f_error; // Test for an error

    // Directory Access
    pub const opendir = c.f_opendir; // Open a directory
    pub const closedir = c.f_closedir; // Close an open directory
    pub const readdir = c.f_readdir; // Read a directory item
    pub const findfirst = c.f_findfirst; // Open a directory and read the first item matched
    pub const findnext = c.f_findnext; // Read a next item matched

    // File and Directory Management
    pub const stat = c.f_stat; // Check existance of a file or sub-directory
    pub const unlink = c.f_unlink; // Remove a file or sub-directory
    pub const rename = c.f_rename; // Rename/Move a file or sub-directory
    pub const chmod = c.f_chmod; // Change attribute of a file or sub-directory
    pub const utime = c.f_utime; // Change timestamp of a file or sub-directory
    pub const mkdir = c.f_mkdir; // Create a sub-directory
    pub const chdir = c.f_chdir; // Change current directory
    pub const chdrive = c.f_chdrive; // Change current drive
    pub const getcwd = c.f_getcwd; // Retrieve the current directory and drive

    // Volume Management and System Configuration
    pub const mount = c.f_mount; // Register the work area of the volume
    pub const unmount = c.f_unmount; // Unregister the work area of the volume
    pub const mkfs = c.f_mkfs; // Create an FAT volume on the logical drive
    pub const fdisk = c.f_fdisk; // Create partitions on the physical drive
    pub const getfree = c.f_getfree; // Get free space on the volume
    pub const getlabel = c.f_getlabel; // Get volume label
    pub const setlabel = c.f_setlabel; // Set volume label
    pub const setcp = c.f_setcp; // Set active code page

};

// Current local time shall be returned as bit-fields packed into a DWORD value. The bit fields are as follows:
// bit31:25  Year origin from the 1980 (0..127, e.g. 37 for 2017)
// bit24:21  Month (1..12)
// bit20:16  Day of the month (1..31)
// bit15:11  Hour (0..23)
// bit10:5  Minute (0..59)
// bit4:0  Second / 2 (0..29, e.g. 25 for 50)
export fn get_fattime() c.DWORD {
    const timestamp = std.time.timestamp() - std.time.epoch.dos;

    const epoch_secs = std.time.epoch.EpochSeconds{
        .secs = @intCast(u64, timestamp),
    };

    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();

    const year_and_day = epoch_day.calculateYearDay();
    const month_and_day = year_and_day.calculateMonthDay();

    const year: u32 = year_and_day.year;
    const month: u32 = @enumToInt(month_and_day.month);
    const day: u32 = month_and_day.day_index + 1;

    const hour: u32 = day_secs.getHoursIntoDay();
    const minute: u32 = day_secs.getMinutesIntoHour();
    const second: u32 = day_secs.getSecondsIntoMinute();

    return 0 |
        (year << 25) | // bit31:25  Year origin from the 1980 (0..127, e.g. 37 for 2017)
        (month << 21) | // bit24:21  Month (1..12)
        (day << 16) | // bit20:16  Day of the month (1..31)
        (hour << 11) | // bit15:11  Hour (0..23)
        (minute << 5) | // bit10:5  Minute (0..59)
        ((second / 2) << 0) // bit4:0  Second / 2 (0..29, e.g. 25 for 50)
    ;
}

export fn disk_status(
    pdrv: c.BYTE, // Physical drive nmuber to identify the drive */
) c.DSTATUS {
    logger.info("disk.status({})", .{pdrv});

    const disk = disks[pdrv] orelse return c.STA_NOINIT;
    return disk.getStatus().toInteger();
}

export fn disk_initialize(pdrv: c.BYTE) c.DSTATUS {
    logger.info("disk.initialize({})", .{pdrv});

    const disk = disks[pdrv] orelse return c.STA_NOINIT;

    if (disk.initialize()) |status| {
        return status.toInteger();
    } else |err| {
        logger.err("disk.initialize({}) failed: {s}", .{ pdrv, @errorName(err) });
        return c.STA_NOINIT;
    }
}

export fn disk_read(
    pdrv: c.BYTE, // Physical drive nmuber to identify the drive */
    buff: [*]c.BYTE, // Data buffer to store read data */
    sector: c.LBA_t, // Start sector in LBA */
    count: c.UINT, // Number of sectors to read */
) c.DRESULT {
    const disk = disks[pdrv] orelse return c.RES_NOTRDY;
    logger.info("disk.read({}, {*}, {}, {})", .{ pdrv, buff, sector, count });
    return Disk.mapResult(disk.read(buff, sector, count));
}

export fn disk_write(
    pdrv: c.BYTE, // Physical drive nmuber to identify the drive */
    buff: [*]const c.BYTE, // Data to be written */
    sector: c.LBA_t, // Start sector in LBA */
    count: c.UINT, // Number of sectors to write */
) c.DRESULT {
    const disk = disks[pdrv] orelse return c.RES_NOTRDY;
    logger.info("disk.write({}, {*}, {}, {})", .{ pdrv, buff, sector, count });
    return Disk.mapResult(disk.write(buff, sector, count));
}

export fn disk_ioctl(
    pdrv: c.BYTE, // Physical drive nmuber (0..) */
    cmd: c.BYTE, // Control code */
    buff: [*]u8, // Buffer to send/receive control data */
) c.DRESULT {
    const disk = disks[pdrv] orelse return c.RES_NOTRDY;
    logger.info("disk.ioctl({}, {}, {*})", .{ pdrv, cmd, buff });
    return Disk.mapResult(disk.ioctl(@intToEnum(IoCtl, cmd), buff));
}

pub const Error = error{
    DiskErr,
    IntErr,
    NotReady,
    NoFile,
    NoPath,
    InvalidName,
    Denied,
    Exist,
    InvalidObject,
    WriteProtected,
    InvalidDrive,
    NotEnabled,
    NoFilesystem,
    MkfsAborted,
    Timeout,
    Locked,
    NotEnoughCore,
    TooManyOpenFiles,
    InvalidParameter,
};

pub fn tryFs(code: c.FRESULT) Error!void {
    return switch (code) {
        c.FR_OK => {},
        c.FR_DISK_ERR => error.DiskErr,
        c.FR_INT_ERR => error.IntErr,
        c.FR_NOT_READY => error.NotReady,
        c.FR_NO_FILE => error.NoFile,
        c.FR_NO_PATH => error.NoPath,
        c.FR_INVALID_NAME => error.InvalidName,
        c.FR_DENIED => error.Denied,
        c.FR_EXIST => error.Exist,
        c.FR_INVALID_OBJECT => error.InvalidObject,
        c.FR_WRITE_PROTECTED => error.WriteProtected,
        c.FR_INVALID_DRIVE => error.InvalidDrive,
        c.FR_NOT_ENABLED => error.NotEnabled,
        c.FR_NO_FILESYSTEM => error.NoFilesystem,
        c.FR_MKFS_ABORTED => error.MkfsAborted,
        c.FR_TIMEOUT => error.Timeout,
        c.FR_LOCKED => error.Locked,
        c.FR_NOT_ENOUGH_CORE => error.NotEnoughCore,
        c.FR_TOO_MANY_OPEN_FILES => error.TooManyOpenFiles,
        c.FR_INVALID_PARAMETER => error.InvalidParameter,
        else => unreachable,
    };
}

pub const IoCtl = enum(u8) {
    /// Complete pending write process (needed at FF_FS_READONLY == 0)
    sync = @intCast(u8, c.CTRL_SYNC),

    /// Get media size (needed at FF_USE_MKFS == 1)
    get_sector_count = @intCast(u8, c.GET_SECTOR_COUNT),

    /// Get sector size (needed at FF_MAX_SS != FF_MIN_SS)
    get_sector_size = @intCast(u8, c.GET_SECTOR_SIZE),

    /// Get erase block size (needed at FF_USE_MKFS == 1)
    get_block_size = @intCast(u8, c.GET_BLOCK_SIZE),

    /// Inform device that the data on the block of sectors is no longer used (needed at FF_USE_TRIM == 1)
    trim = @intCast(u8, c.CTRL_TRIM),

    _,
};
