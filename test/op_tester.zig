//!
//! This file implements several tests that try to exercise
//! and perform all possible operations of the zfat library.
//!
const std = @import("std");
const zfat = @import("zfat");

// requires pointer stability
var global_fs: zfat.FileSystem = undefined;

// requires pointer stability
var ramdisks: [5]RamDisk = .{.{}} ** 5;

pub const std_options = std.Options{
    .log_level = .info,
};

pub fn main() !void {
    try ramdisks[0].init(100_000);

    zfat.disks[0] = &ramdisks[0].interface;

    // try mkfs with all formats:
    {
        const formats = [_]zfat.DiskFormat{ .any, .fat, .exfat, .fat32 };
        var workspace: [4096]u8 = undefined;

        for (formats) |target_fmt| {
            std.log.info("format disk with {s}...", .{@tagName(target_fmt)});
            try zfat.mkfs("0:", .{
                .filesystem = target_fmt,
                .sector_align = 1,
                .use_partitions = true,
            }, &workspace);
        }
    }

    std.log.info("mount disk...", .{});
    try global_fs.mount("0:", true);
    defer zfat.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

    // mkdir
    // unlink
    // rename
    // stat
    // chmod
    // utime
    // chdir
    // chdrive
    // getcwd

    // Dir.open
    // Dir.close
    // Dir.next
    // Dir.rewind

    // File.open
    // File.create
    // File.openRead
    // File.openWrite
    // File.close
    // File.sync
    // File.truncate
    // File.seekTo
    // File.expand
    // File.endOfFile
    // File.hasError
    // File.tell
    // File.size
    // File.rewind
    // File.write
    // File.read

    // api.fdisk
    // api.getfree
    // api.getlabel
    // api.setlabel
    // api.setcp
}

pub const RamDisk = struct {
    const sector_size = 512;

    interface: zfat.Disk = .{
        .getStatusFn = getStatus,
        .initializeFn = initialize,
        .readFn = read,
        .writeFn = write,
        .ioctlFn = ioctl,
    },
    sectors: [][sector_size]u8 = &.{},

    pub fn init(rd: *RamDisk, sector_count: usize) !void {
        rd.* = .{};
        rd.sectors = try std.heap.page_allocator.alloc([sector_size]u8, sector_count);
    }

    pub fn deinit(rd: *RamDisk) void {
        if (rd.sectors.len > 0) {
            std.heap.page_allocator.free(rd.sectors);
        }
        rd.sectors = &.{};
    }

    pub fn getStatus(interface: *zfat.Disk) zfat.Disk.Status {
        const self: *RamDisk = @fieldParentPtr("interface", interface);
        return zfat.Disk.Status{
            .initialized = (self.sectors.len > 0),
            .disk_present = true,
            .write_protected = false,
        };
    }

    pub fn initialize(interface: *zfat.Disk) zfat.Disk.Error!zfat.Disk.Status {
        const self: *RamDisk = @fieldParentPtr("interface", interface);
        return getStatus(&self.interface);
    }

    pub fn read(interface: *zfat.Disk, buff: [*]u8, sector: zfat.LBA, count: c_uint) zfat.Disk.Error!void {
        const self: *RamDisk = @fieldParentPtr("interface", interface);

        std.log.debug("read({*}, {}, {})", .{ buff, sector, count });

        var sectors = std.io.fixedBufferStream(std.mem.sliceAsBytes(self.sectors));
        sectors.seekTo(sector * sector_size) catch return error.IoError;
        sectors.reader().readNoEof(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn write(interface: *zfat.Disk, buff: [*]const u8, sector: zfat.LBA, count: c_uint) zfat.Disk.Error!void {
        const self: *RamDisk = @fieldParentPtr("interface", interface);

        std.log.debug("write({*}, {}, {})", .{ buff, sector, count });

        var sectors = std.io.fixedBufferStream(std.mem.sliceAsBytes(self.sectors));
        sectors.seekTo(sector * sector_size) catch return error.IoError;
        sectors.writer().writeAll(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn ioctl(interface: *zfat.Disk, cmd: zfat.IoCtl, buff: [*]u8) zfat.Disk.Error!void {
        const self: *RamDisk = @fieldParentPtr("interface", interface);

        switch (cmd) {
            .sync => {},
            .get_sector_count => {
                @as(*align(1) zfat.LBA, @ptrCast(buff)).* = @intCast(self.sectors.len);
            },
            .trim => {},
            else => {
                std.log.err("invalid ioctl: {}", .{cmd});
                return error.InvalidParameter;
            },
        }
    }
};
