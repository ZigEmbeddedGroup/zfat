const std = @import("std");
const config = @import("config");
const c = @import("c");
const logger = std.log.scoped(.fatfs);

pub const volume_count = c.FF_VOLUMES;

pub var disks: [c.FF_VOLUMES]?*Disk = @splat(null);

pub const PathChar = c.TCHAR;
pub const LBA = c.LBA_t;
pub const FileSize = c.FSIZE_t;
pub const Path = [:0]const PathChar;

pub const WORD = c.WORD;
pub const DWORD = c.DWORD;

pub const MkDirError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_DENIED,
    FR_EXIST,
    FR_WRITE_PROTECTED,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_NOT_ENOUGH_CORE,
};
pub fn mkdir(path: Path) MkDirError!void {
    try map_error(MkDirError, api.mkdir(path.ptr));
}

pub const UnlinkError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_FILE,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_DENIED,
    FR_WRITE_PROTECTED,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_LOCKED,
    FR_NOT_ENOUGH_CORE,
};

pub fn unlink(path: Path) UnlinkError!void {
    try map_error(UnlinkError, api.unlink(path.ptr));
}

pub const RenameError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_FILE,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_EXIST,
    FR_WRITE_PROTECTED,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_LOCKED,
    FR_NOT_ENOUGH_CORE,
};
pub fn rename(
    old_path: Path,
    new_path: Path,
) RenameError!void {
    try map_error(RenameError, api.rename(old_path.ptr, new_path.ptr));
}

pub const StatError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_FILE,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_NOT_ENOUGH_CORE,
};
pub fn stat(path: Path) StatError!FileInfo {
    var res: c.FILINFO = undefined;
    try map_error(StatError, api.stat(path.ptr, &res));
    return FileInfo.fromFILINFO(res);
}

pub const ChmodError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_FILE,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_WRITE_PROTECTED,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_NOT_ENOUGH_CORE,
};
pub const ChmodAttributes = struct {
    read_only: ?bool = null,
    hidden: ?bool = null,
    system: ?bool = null,
    archive: ?bool = null,
};
pub fn chmod(path: Path, attributes: ChmodAttributes) ChmodError!void {
    var mask: Attributes = @bitCast(@as(u8, 0));
    var values: Attributes = @bitCast(@as(u8, 0));

    inline for (.{
        "read_only",
        "hidden",
        "system",
        "archive",
    }) |field| {
        if (@field(attributes, field)) |value| {
            @field(mask, field) = true;
            @field(values, field) = value;
        }
    }

    try map_error(ChmodError, api.chmod(path.ptr, @bitCast(values), @bitCast(mask)));
}

pub const UTimeError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_FILE,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_WRITE_PROTECTED,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_NOT_ENOUGH_CORE,
};
pub fn utime(path: Path, date: Date, time: Time) UTimeError!void {
    const file_info = std.mem.zeroInit(c.FILINFO, .{
        .fdate = date.encode(),
        .ftime = time.encode(),
    });
    try map_error(UTimeError, api.utime(path.ptr, &file_info));
}

pub const ChDirError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NO_PATH,
    FR_INVALID_NAME,
    FR_INVALID_DRIVE,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_NOT_ENOUGH_CORE,
};
pub fn chdir(path: Path) ChDirError!void {
    try map_error(ChDirError, api.chdir(path.ptr));
}

pub const ChDriveError = error{FR_INVALID_DRIVE};
pub fn chdrive(path: Path) ChDriveError!void {
    try map_error(ChDriveError, api.chdrive(path.ptr));
}

pub const GetCwdError = error{
    FR_DISK_ERR,
    FR_INT_ERR,
    FR_NOT_READY,
    FR_NOT_ENABLED,
    FR_NO_FILESYSTEM,
    FR_TIMEOUT,
    FR_NOT_ENOUGH_CORE,
};
pub fn getcwd(buffer: []PathChar) GetCwdError!Path {
    try map_error(GetCwdError, api.getcwd(buffer.ptr, std.math.cast(c_uint, buffer.len) orelse std.math.maxInt(c_uint)));
    return @ptrCast(std.mem.sliceTo(buffer, 0));
}

pub const DiskFormat = enum(u8) {
    fat = c.FM_FAT,
    fat32 = c.FM_FAT32,
    exfat = c.FM_EXFAT,
    any = c.FM_ANY,
};

pub const FatTables = enum(u8) {
    one = 1,
    two = 2,
};

pub const FormatOptions = struct {
    /// Specifies a combination of FAT type flags, FM_FAT, FM_FAT32, FM_EXFAT and bitwise-or of these three,
    // FM_ANY. FM_EXFAT is ignored when exFAT is not enabled. These flags specify which type of FAT volume
    // to be created. If two or more types are specified, one out of them will be selected depends on the
    // volume size and au_size. The flag FM_SFD specifies to create the volume on the drive in SFD format.
    // The default value is FM_ANY.
    filesystem: DiskFormat,

    /// Specifies number of FAT copies on the FAT/FAT32 volume. Valid value for this member is 1 or 2.
    /// The default value (0) and any invaid value gives 1. If the FAT type is exFAT, this member has no effect.
    fats: FatTables = .one,

    /// Specifies alignment of the volume data area (file allocation pool, usually erase block boundary of flash memory media) in unit of sector. The valid value for this member is between 1 and 32768 inclusive in power of 2. If a zero (the default value) or any invalid value is given, the function obtains the block size from lower layer with disk_ioctl function.
    sector_align: c_uint,

    /// Specifies size of the allocation unit (cluter) in unit of byte. The valid value is power of 2 between
    /// sector size and 128 * sector size inclusive for FAT/FAT32 volume, or up to 16 MB for exFAT volume. If
    /// a zero (default value) or any invalid value is given, the function uses default allocation unit size
    /// depends on the volume size.
    cluster_size: u32 = 0,

    /// Specifies number of root directory entries on the FAT volume. Valid value for this member is up to 32768
    /// and aligned to sector size / 32. The default value (0) and any invaid value gives 512. If the FAT type is
    /// FAT32 or exFAT, this member has no effect.
    rootdir_size: c_uint = 512,

    use_partitions: bool = false,
};

pub const MkfsError = error{
    FR_DISK_ERR,
    FR_NOT_READY,
    FR_WRITE_PROTECTED,
    FR_INVALID_DRIVE,
    FR_MKFS_ABORTED,
    FR_INVALID_PARAMETER,
    FR_NOT_ENOUGH_CORE,
};
pub fn mkfs(path: Path, options: FormatOptions, workspace: []u8) MkfsError!void {
    const opts = c.MKFS_PARM{
        .fmt = @backingInt(options.filesystem) | if (!options.use_partitions) @as(u8, @intCast(c.FM_SFD)) else 0,
        .n_fat = @backingInt(options.fats),
        .@"align" = options.sector_align,
        .au_size = options.cluster_size,
        .n_root = options.rootdir_size,
    };
    try map_error(MkfsError, api.mkfs(path.ptr, &opts, workspace.ptr, @as(c_uint, @intCast(@min(workspace.len, std.math.maxInt(c_uint))))));
}

pub const FileSystem = struct {
    raw: c.FATFS,

    pub const MountError = error{
        FR_INVALID_DRIVE,
        FR_DISK_ERR,
        FR_NOT_READY,
        FR_NOT_ENABLED,
        FR_NO_FILESYSTEM,
    };
    pub fn mount(fs: *FileSystem, drive: Path, force_mount: bool) MountError!void {
        try map_error(MountError, api.mount(&fs.raw, drive.ptr, @intFromBool(force_mount)));
    }

    pub fn unmount(drive: Path) MountError!void {
        try map_error(MountError, api.unmount(drive.ptr));
    }
};

pub const Dir = struct {
    raw: c.DIR,

    pub const OpenDirError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_NOT_READY,
        FR_NO_PATH,
        FR_INVALID_NAME,
        FR_INVALID_OBJECT,
        FR_INVALID_DRIVE,
        FR_NOT_ENABLED,
        FR_NO_FILESYSTEM,
        FR_TIMEOUT,
        FR_NOT_ENOUGH_CORE,
        FR_TOO_MANY_OPEN_FILES,
    };

    pub fn open(path: Path) OpenDirError!Dir {
        var dir = Dir{ .raw = undefined };
        try map_error(OpenDirError, api.opendir(&dir.raw, path.ptr));
        return dir;
    }

    pub fn close(dir: *Dir) void {
        map_generic_error(api.closedir(&dir.raw)) catch |e| {
            logger.err("failed to close directory: {s}", .{@errorName(e)});
        };
        dir.* = undefined;
    }

    pub const ReadDirError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_INVALID_OBJECT,
        FR_TIMEOUT,
        FR_NOT_ENOUGH_CORE,
    };

    pub fn next(dir: *Dir) ReadDirError!?FileInfo {
        var res: c.FILINFO = .{};
        try map_error(ReadDirError, api.readdir(&dir.raw, &res));
        if (res.fname[0] == 0)
            return null;
        return FileInfo.fromFILINFO(res);
    }

    pub fn rewind(dir: *Dir) ReadDirError!void {
        try map_error(ReadDirError, api.readdir(&dir.raw, null));
    }
};

pub const Attributes = packed struct(u8) {
    read_only: bool,
    hidden: bool,
    system: bool,
    _padding0: bool = false,
    directory: bool,
    archive: bool,
    _padding1: bool = false,
    _padding2: bool = false,

    comptime {
        std.debug.assert(c.AM_RDO == 0x01);
        std.debug.assert(c.AM_HID == 0x02);
        std.debug.assert(c.AM_SYS == 0x04);
        std.debug.assert(c.AM_DIR == 0x10);
        std.debug.assert(c.AM_ARC == 0x20);

        std.debug.assert(@bitOffsetOf(Attributes, "read_only") == 0);
        std.debug.assert(@bitOffsetOf(Attributes, "hidden") == 1);
        std.debug.assert(@bitOffsetOf(Attributes, "system") == 2);
        std.debug.assert(@bitOffsetOf(Attributes, "directory") == 4);
        std.debug.assert(@bitOffsetOf(Attributes, "archive") == 5);
    }

    pub fn format(attrs: Attributes, writer: *std.Io.Writer) !void {
        const bits = .{
            .{ attrs.read_only, "read_only" },
            .{ attrs.hidden, "hidden" },
            .{ attrs.system, "system" },
            .{ attrs._padding0, "BIT3" },
            .{ attrs.directory, "directory" },
            .{ attrs.archive, "archive" },
            .{ attrs._padding1, "BIT6" },
            .{ attrs._padding2, "BIT7" },
        };

        var names: [bits.len][]const u8 = undefined;
        var names_len: usize = 0;
        inline for (bits) |bit| {
            if (bit[0]) {
                names[names_len] = bit[1];
                names_len += 1;
            }
        }

        try writer.print("{s}{{", .{@typeName(Attributes)});

        if (names_len > 0) {
            try writer.writeAll(" ");
            try writer.writeAll(names[0]);
            for (names[1..names_len]) |other| {
                try writer.writeAll(", ");
                try writer.writeAll(other);
            }
            try writer.writeAll(" ");
        }

        try writer.writeAll("}");
    }
};

pub const FileInfo = struct {
    pub fn fromFILINFO(info: c.FILINFO) FileInfo {
        return FileInfo{
            .size = info.fsize,
            .date = Date.decode(info.fdate),
            .time = Time.decode(info.ftime),
            .kind = if ((info.fattrib & c.AM_DIR) != 0) .Directory else .File,
            .attributes = @bitCast(info.fattrib),
            .name_buffer = info.fname,
            .altname_buffer = if (@hasField(c.FILINFO, "altname")) info.altname else [1]u8{0},
        };
    }

    size: u64,
    date: Date,
    time: Time,
    kind: Kind,
    attributes: Attributes,

    name_buffer: [max_name_len + 1]u8,
    altname_buffer: [max_altname_len + 1]u8,

    pub fn name(self: *const FileInfo) []const u8 {
        return std.mem.sliceTo(&self.name_buffer, 0);
    }

    pub fn altName(self: *const FileInfo) []const u8 {
        return std.mem.sliceTo(&self.altname_buffer, 0);
    }

    pub const max_name_len = if (@hasDecl(c, "FF_LFN_BUF")) c.FF_LFN_BUF else 12;
    pub const max_altname_len = if (@hasDecl(c, "FF_SFN_BUF")) c.FF_SFN_BUF else 0;

    pub fn format(info: FileInfo, writer: *std.Io.Writer) !void {
        try writer.print(
            \\{s}{{ .size={}, .date = {}, .time = {}, .kind = .{s}, .attributes = {}, .name = '{}', .altname = '{}' }}
        , .{
            @typeName(FileInfo),
            info.size,
            info.date,
            info.time,
            @tagName(info.kind),
            info.attributes,
            std.zig.fmtEscapes(info.name()),
            std.zig.fmtEscapes(info.altName()),
        });
    }
};

pub const Kind = enum { File, Directory };

pub const Date = struct {
    year: u16,
    month: std.time.epoch.Month,
    day: u8,

    pub fn init(year: u16, month: std.time.epoch.Month, day: u8) Date {
        std.debug.assert(year >= 1980 and year <= 1980 + 127);
        std.debug.assert(day >= 1 and day <= 31);
        return .{
            .year = year,
            .month = month,
            .day = day,
        };
    }

    pub fn decode(val: u16) Date {
        const enc: Encoded = @bitCast(val);
        return Date{
            .year = 1980 + @as(u16, enc.years_from_1980),
            .month = @as(std.time.epoch.Month, @fromBackingInt(@intCast(enc.month))),
            .day = enc.day,
        };
    }

    pub fn encode(date: Date) u16 {
        return @bitCast(Encoded{
            .years_from_1980 = @intCast(date.year - 1980),
            .day = @intCast(date.day),
            .month = @backingInt(date.month),
        });
    }

    pub fn format(date: Date, writer: *std.Io.Writer) !void {
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{
            date.year,
            @backingInt(date.month),
            date.day,
        });
    }

    pub const Encoded = packed struct(u16) {
        /// bit[4:0]: Day (1..31)
        day: u5,

        /// bit[8:5]: Month (1..12)
        month: u4,

        /// bit[15:9]: Year origin from 1980 (0..127)
        years_from_1980: u7,
    };
};

pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,

    pub fn init(hour: u8, minute: u8, second: u8) Time {
        std.debug.assert(hour >= 0 and hour <= 24);
        std.debug.assert(minute >= 0 and minute <= 60);
        std.debug.assert(second >= 0 and second <= 60);
        return .{
            .hour = hour,
            .minute = minute,
            .second = second,
        };
    }

    pub fn decode(val: u16) Time {
        const enc: Encoded = @bitCast(val);
        return Time{
            .hour = enc.hour,
            .minute = enc.minute,
            .second = 2 * @as(u8, enc.double_second),
        };
    }

    pub fn encode(time: Time) u16 {
        return @bitCast(Encoded{
            .hour = @intCast(time.hour),
            .minute = @intCast(time.minute),
            .double_second = @intCast(time.second / 2),
        });
    }

    pub fn format(time: Time, writer: *std.Io.Writer) !void {
        try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{
            time.hour,
            time.minute,
            time.second,
        });
    }

    pub const Encoded = packed struct(u16) {
        /// bit[4:0]: Second / 2 (0..29)
        double_second: u5,
        /// bit[10:5]: Minute (0..59)
        minute: u6,
        /// bit[15:11]: Hour (0..23)
        hour: u5,
    };
};

pub const File = struct {
    raw: c.FIL,

    pub const Mode = enum(u8) {
        open_existing = c.FA_OPEN_EXISTING,
        create_new = c.FA_CREATE_NEW,
        create_always = c.FA_CREATE_ALWAYS,
        open_always = c.FA_OPEN_ALWAYS,
        open_append = c.FA_OPEN_APPEND,
    };

    pub const Access = enum(u8) {
        read_only = c.FA_READ,
        write_only = c.FA_WRITE,
        read_write = c.FA_READ | c.FA_WRITE,
    };

    pub const OpenFlags = struct {
        access: Access = .read_only,
        mode: Mode = .open_existing,
    };

    pub const OpenError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_NOT_READY,
        FR_NO_FILE,
        FR_NO_PATH,
        FR_INVALID_NAME,
        FR_DENIED,
        FR_EXIST,
        FR_INVALID_OBJECT,
        FR_WRITE_PROTECTED,
        FR_INVALID_DRIVE,
        FR_NOT_ENABLED,
        FR_NO_FILESYSTEM,
        FR_TIMEOUT,
        FR_LOCKED,
        FR_NOT_ENOUGH_CORE,
        FR_TOO_MANY_OPEN_FILES,
    };

    pub fn open(path: Path, flags: OpenFlags) OpenError!File {
        const int_flags = @backingInt(flags.mode) | @backingInt(flags.access);

        var file = File{ .raw = undefined };
        try map_error(OpenError, api.open(&file.raw, path.ptr, int_flags));
        return file;
    }

    /// Creates a new file. If the file is existing, it will be truncated and overwritten.
    /// File access is read and write.
    pub fn create(path: Path) OpenError!File {
        return open(path, .{
            .mode = .create_always,
            .access = .read_write,
        });
    }

    /// Opens a file. The function fails if the file is not existing.
    /// File access is read only.
    pub fn openRead(path: Path) OpenError!File {
        return open(path, .{
            .mode = .open_existing,
            .access = .read_only,
        });
    }

    /// Opens the file if it is existing. If not, a new file will be created.
    /// File access is read and write.
    pub fn openWrite(path: Path) OpenError!File {
        return open(path, .{
            .mode = .open_always,
            .access = .read_write,
        });
    }

    pub fn close(file: *File) void {
        map_generic_error(api.close(&file.raw)) catch |e| {
            logger.err("failed to close file: {s}", .{@errorName(e)});
        };
        file.* = undefined;
    }

    pub const SyncError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_INVALID_OBJECT,
        FR_TIMEOUT,
    };
    pub fn sync(file: *File) SyncError!void {
        try map_error(SyncError, api.sync(&file.raw));
    }

    pub const TruncateError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_DENIED,
        FR_INVALID_OBJECT,
        FR_TIMEOUT,
    };
    pub fn truncate(file: *File) TruncateError!void {
        try map_error(TruncateError, api.truncate(&file.raw));
    }

    pub const SeekToError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_INVALID_OBJECT,
        FR_TIMEOUT,
    };
    pub fn seekTo(file: *File, offset: FileSize) !void {
        try map_error(SeekToError, api.lseek(&file.raw, offset));
    }

    pub const ExpandError = error{
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_INVALID_OBJECT,
        FR_DENIED,
        FR_TIMEOUT,
    };
    pub fn expand(file: *File, new_size: FileSize, force_allocate: bool) !void {
        try map_error(ExpandError, api.expand(&file.raw, new_size, @intFromBool(force_allocate)));
    }

    pub fn endOfFile(self: File) bool {
        return (api.eof(&self.raw) != 0);
    }

    pub fn hasError(self: File) bool {
        return (api.@"error"(&self.raw) != 0);
    }

    pub fn tell(self: File) FileSize {
        return api.tell(&self.raw);
    }

    pub fn size(self: File) FileSize {
        return api.size(&self.raw);
    }

    pub fn rewind(self: *File) !void {
        try self.seekTo(0);
    }

    pub const WriteError = error{
        Overflow,
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_DENIED,
        FR_INVALID_OBJECT,
        FR_TIMEOUT,
    };

    pub fn write(file: *File, data: []const u8) WriteError!usize {
        var written: c_uint = 0;
        try map_error(WriteError, api.write(&file.raw, data.ptr, std.math.cast(c_uint, data.len) orelse return error.Overflow, &written));
        return written;
    }

    pub const ReadError = error{
        Overflow,
        FR_DISK_ERR,
        FR_INT_ERR,
        FR_DENIED,
        FR_INVALID_OBJECT,
        FR_TIMEOUT,
    };
    pub fn read(file: *File, data: []u8) ReadError!usize {
        var written: c_uint = 0;
        try map_error(ReadError, api.read(&file.raw, data.ptr, std.math.cast(c_uint, data.len) orelse return error.Overflow, &written));
        return written;
    }

    pub const Reader = struct {
        file: *File,
        err: ?ReadError = null,
        reader: std.Io.Reader,
    };

    pub const Writer = struct {
        file: *File,
        err: ?WriteError = null,
        writer: std.Io.Writer,
    };

    pub fn reader(file: *File, buffer: []u8) Reader {
        return .{
            .file = file,
            .reader = .{
                .buffer = buffer,
                .seek = 0,
                .end = 0,
                .vtable = comptime &.{
                    .stream = reader_stream,
                },
            },
        };
    }

    pub fn writer(file: *File, buffer: []u8) Writer {
        return .{
            .file = file,
            .writer = .{
                .buffer = buffer,
                .vtable = &.{
                    .drain = writer_drain,
                },
            },
        };
    }

    fn reader_stream(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const wrap: *Reader = @fieldParentPtr("reader", r);

        const buffer = limit.slice(try w.writableSliceGreedy(1));

        const len = wrap.file.read(buffer) catch |err| {
            wrap.err = err;
            return error.ReadFailed;
        };
        if (len == 0)
            return error.EndOfStream;
        w.advance(len);
        return len;
    }

    fn writer_drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        _ = splat;
        const wrap: *Writer = @fieldParentPtr("writer", w);
        const buffered = w.buffered();
        if (buffered.len != 0) return w.consume(wrap.file.write(buffered) catch |err| {
            wrap.err = err;
            return error.WriteFailed;
        });
        return wrap.file.write(data[0]) catch |err| {
            wrap.err = err;
            return error.WriteFailed;
        };
    }
};

pub const Disk = struct {
    getStatusFn: *const fn (self: *Disk) Status,
    initializeFn: *const fn (self: *Disk) Disk.Error!Status,
    readFn: *const fn (self: *Disk, buff: [*]u8, sector: c.LBA_t, count: c.UINT) Disk.Error!void,
    writeFn: *const fn (self: *Disk, buff: [*]const u8, sector: c.LBA_t, count: c.UINT) Disk.Error!void,
    ioctlFn: *const fn (self: *Disk, cmd: IoCtl, buff: [*]u8) Disk.Error!void,

    pub fn getStatus(self: *Disk) Status {
        return self.getStatusFn(self);
    }

    pub fn initialize(self: *Disk) Disk.Error!Status {
        return self.initializeFn(self);
    }

    pub fn read(self: *Disk, buff: [*]u8, sector: c.LBA_t, count: c.UINT) Disk.Error!void {
        return self.readFn(self, buff, sector, count);
    }

    pub fn write(self: *Disk, buff: [*]const u8, sector: c.LBA_t, count: c.UINT) Disk.Error!void {
        return self.writeFn(self, buff, sector, count);
    }

    pub fn ioctl(self: *Disk, cmd: IoCtl, buff: [*]u8) Disk.Error!void {
        return self.ioctlFn(self, cmd, buff);
    }

    fn mapResult(value: Disk.Error!void) c.DRESULT {
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

        pub fn toInteger(self: Status) c.DSTATUS {
            var i: c.DSTATUS = 0;
            if (!self.initialized) i |= @as(u8, @intCast(c.STA_NOINIT));
            if (!self.disk_present) i |= @as(u8, @intCast(c.STA_NODISK));
            if (self.write_protected) i |= @as(u8, @intCast(c.STA_PROTECT));
            return i;
        }
    };
};

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

const RtcExport = struct {
    const Encoded = packed struct(c.DWORD) {
        /// bit[4:0]: Second / 2 (0..29, e.g. 25 for 50)
        double_second: u5,
        /// bit[10:5]: Minute (0..59)
        minute: u6,
        /// bit[15:11]: Hour (0..23)
        hour: u5,
        /// bit[20:16]: Day of the month (1..31)
        day: u5,
        /// bit[24:21]: Month (1..12)
        month: u4,
        /// bit[31:25]: Year origin from the 1980 (0..127, e.g. 37 for 2017)
        year_from_1980: u7,
    };

    // Current local time shall be returned as bit-fields packed into a DWORD value. The bit fields are as follows:

    export fn get_fattime() c.DWORD {
        // The C ABI leaves no way to thread an `Io` parameter through here, so
        // use the globally available debug instance for the wall clock.
        const io = std.Options.debug_io;
        const ns = std.Io.Clock.now(.real, io).nanoseconds;
        const timestamp: i64 = @intCast(@divTrunc(ns, std.time.ns_per_s));

        const epoch_secs = std.time.epoch.EpochSeconds{
            .secs = @as(u64, @intCast(timestamp)),
        };

        const epoch_day = epoch_secs.getEpochDay();
        const day_secs = epoch_secs.getDaySeconds();

        const year_and_day = epoch_day.calculateYearDay();
        const month_and_day = year_and_day.calculateMonthDay();

        const year = year_and_day.year;
        const month = @backingInt(month_and_day.month);
        const day = month_and_day.day_index + 1;

        const hour = day_secs.getHoursIntoDay();
        const minute = day_secs.getMinutesIntoHour();
        const second = day_secs.getSecondsIntoMinute();

        const dateTime = Encoded{
            .double_second = @intCast(second / 2),
            .minute = minute,
            .hour = hour,
            .day = day,
            .month = month,
            .year_from_1980 = @intCast(std.math.clamp(year - 1980, 0, 127)),
        };

        return @bitCast(dateTime);
    }
};

comptime {
    if (config.has_rtc) {
        // @compileLog("...", config.has_rtc);
        _ = RtcExport;
    }
}

export fn disk_status(
    pdrv: c.BYTE, // Physical drive nmuber to identify the drive */
) c.DSTATUS {
    logger.debug("disk.status({})", .{pdrv});

    const disk = disks[pdrv] orelse return c.STA_NOINIT;
    return disk.getStatus().toInteger();
}

export fn disk_initialize(pdrv: c.BYTE) c.DSTATUS {
    logger.debug("disk.initialize({})", .{pdrv});

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
    logger.debug("disk.read({}, {*}, {}, {})", .{ pdrv, buff, sector, count });
    return Disk.mapResult(disk.read(buff, sector, count));
}

export fn disk_write(
    pdrv: c.BYTE, // Physical drive nmuber to identify the drive */
    buff: [*]const c.BYTE, // Data to be written */
    sector: c.LBA_t, // Start sector in LBA */
    count: c.UINT, // Number of sectors to write */
) c.DRESULT {
    const disk = disks[pdrv] orelse return c.RES_NOTRDY;
    logger.debug("disk.write({}, {*}, {}, {})", .{ pdrv, buff, sector, count });
    return Disk.mapResult(disk.write(buff, sector, count));
}

export fn disk_ioctl(
    pdrv: c.BYTE, // Physical drive nmuber (0..) */
    cmd: c.BYTE, // Control code */
    buff: [*]u8, // Buffer to send/receive control data */
) c.DRESULT {
    const disk = disks[pdrv] orelse return c.RES_NOTRDY;
    logger.debug("disk.ioctl({}, {}, {*})", .{ pdrv, cmd, buff });
    return Disk.mapResult(disk.ioctl(@as(IoCtl, @fromBackingInt(@intCast(cmd))), buff));
}

pub const IoCtl = enum(u8) {
    /// Complete pending write process (needed at FF_FS_READONLY == 0).
    ///
    /// Makes sure that the device has finished pending write process. If the disk I/O layer or
    /// storage device has a write-back cache, the dirty cache data must be committed to the medium
    /// immediately. Nothing to do for this command if each write operation to the medium is
    /// completed in the disk_write function.
    sync = @as(u8, @intCast(c.CTRL_SYNC)),

    /// Get media size (needed at FF_USE_MKFS == 1)
    /// Retrieves number of available sectors, the largest allowable LBA + 1, on the drive into the
    /// LBA_t variable that pointed by buff. This command is used by f_mkfs and f_fdisk function to
    /// determine the size of volume/partition to be created. It is required when FF_USE_MKFS == 1.
    get_sector_count = @as(u8, @intCast(c.GET_SECTOR_COUNT)),

    /// Get sector size (needed at FF_MAX_SS != FF_MIN_SS)
    /// Retrieves sector size, minimum data unit for generic read/write, into the WORD variable that
    /// pointed by buff. Valid sector sizes are 512, 1024, 2048 and 4096. This command is required
    /// only if FF_MAX_SS > FF_MIN_SS. When FF_MAX_SS == FF_MIN_SS, this command will be never used
    /// and the read/write function must work in FF_MAX_SS bytes/sector.
    get_sector_size = @as(u8, @intCast(c.GET_SECTOR_SIZE)),

    /// Get erase block size (needed at FF_USE_MKFS == 1)
    /// Retrieves erase block size in unit of sector of the flash memory media into the DWORD variable
    /// that pointed by buff. The allowable value is 1 to 32768 in power of 2. Return 1 if the value is
    /// unknown or non flash memory media. This command is used by only f_mkfs function and it attempts
    /// to align data area on the suggested block boundary. It is required when FF_USE_MKFS == 1.
    /// Note that FatFs does not have FTL (flash translation layer). Either disk I/O layter or storage
    /// device must have an FTL in it.
    get_block_size = @as(u8, @intCast(c.GET_BLOCK_SIZE)),

    /// Inform device that the data on the block of sectors is no longer used (needed at FF_USE_TRIM == 1)
    /// Informs the disk I/O layter or the storage device that the data on the block of sectors is no longer
    /// needed and it can be erased. The sector block is specified in an LBA_t array {<Start LBA>, <End LBA>}
    /// that pointed by buff. This is an identical command to Trim of ATA device. Nothing to do for this
    /// command if this funcion is not supported or not a flash memory device. FatFs does not check the result
    /// code and the file function is not affected even if the sector block was not erased well. This command
    /// is called on remove a cluster chain and in the f_mkfs function. It is required when FF_USE_TRIM == 1.
    trim = @as(u8, @intCast(c.CTRL_TRIM)),

    _,
};

pub const GlobalError = error{
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
    OutOfMemory,
    TooManyOpenFiles,
    InvalidParameter,
};

pub inline fn map_generic_error(code: c.FRESULT) GlobalError!void {
    try map_error(GlobalError, code);
}

pub inline fn map_error(comptime ErrorSet: type, code: c.FRESULT) ErrorSet!void {
    if (code == c.FR_OK)
        return;

    const error_names = @typeInfo(ErrorSet).error_set.error_names orelse
        @panic("Unrecognized error code");

    inline for (error_names) |error_name| {
        if (@hasDecl(c, error_name)) {
            if (@field(c, error_name) == code)
                return @field(ErrorSet, error_name);
        }
    }

    @panic("Unrecognized error code");
}
