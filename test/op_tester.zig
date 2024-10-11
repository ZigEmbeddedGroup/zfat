//!
//! This file implements several tests that try to exercise
//! and perform all possible operations of the zfat library.
//!
const std = @import("std");
const zfat = @import("zfat");

// requires pointer stability
var global_fs: [5]zfat.FileSystem = undefined;

// requires pointer stability
var ramdisks: [5]RamDisk = .{.{}} ** 5;

pub const std_options = std.Options{
    .log_level = .info,
};

pub fn main() !void {
    try ramdisks[0].init(100_000);
    try ramdisks[1].init(100_000);

    zfat.disks[0] = &ramdisks[0].interface;
    zfat.disks[1] = &ramdisks[1].interface;

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

    {
        var workspace: [4096]u8 = undefined;
        try zfat.mkfs("1:", .{
            .filesystem = .fat32,
            .sector_align = 1,
            .use_partitions = true,
        }, &workspace);
    }

    std.log.info("mount disk...", .{});
    try global_fs[0].mount("0:", true);
    defer zfat.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

    try zfat.mkdir("0:/build");
    try zfat.mkdir("0:/src");

    try zfat.unlink("0:/build");

    try zfat.rename("0:/src", "0:/code");

    std.log.info("stat: {}", .{try zfat.stat("0:/code")});

    try zfat.chmod("0:/code", .{
        .archive = true,
        .system = true,
    });

    {
        const stat = try zfat.stat("0:/code");
        std.debug.assert(stat.attributes.directory == true);
        std.debug.assert(stat.attributes.archive == true);
        std.debug.assert(stat.attributes.system == true);
        std.log.info("stat: {}", .{stat});
    }

    try zfat.chmod("0:/code", .{
        .archive = false,
        .system = true,
        .read_only = true,
    });

    {
        const stat = try zfat.stat("0:/code");
        std.debug.assert(stat.attributes.directory == true);
        std.debug.assert(stat.attributes.archive == false);
        std.debug.assert(stat.attributes.system == true);
        std.debug.assert(stat.attributes.read_only == true);
        std.log.info("stat: {}", .{stat});
    }

    {
        const date = zfat.Date.init(1993, .sep, 13);
        const time = zfat.Time.init(13, 37, 42);

        try zfat.utime("0:/code", date, time);

        const stat = try zfat.stat("0:/code");
        std.debug.assert(std.meta.eql(stat.date, date));
        std.debug.assert(std.meta.eql(stat.time, time));
        std.log.info("stat: {}", .{stat});
    }

    // getcwd:
    {
        var buffer: [256]u8 = undefined;
        const cwd = try zfat.getcwd(&buffer);
        std.debug.assert(std.mem.eql(u8, cwd, "0:/"));
    }

    // chdir:
    {
        var buffer: [256]u8 = undefined;

        std.log.info("chdir: {s}", .{try zfat.getcwd(&buffer)});
        try zfat.chdir("0:/code");
        std.log.info("chdir: {s}", .{try zfat.getcwd(&buffer)});
        try zfat.chdir("/");
        std.log.info("chdir: {s}", .{try zfat.getcwd(&buffer)});
    }

    // chdrive:
    {
        var buffer: [256]u8 = undefined;

        // We have to expect that disk 1 is not enabled right now:
        std.debug.assert(zfat.chdir("1:") == error.NotEnabled);
        {
            try global_fs[0].mount("1:", true);
            defer zfat.FileSystem.unmount("1:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

            std.log.info("chdrive: {s}", .{try zfat.getcwd(&buffer)});
            try zfat.chdrive("1:");
            std.log.info("chdrive: {s}", .{try zfat.getcwd(&buffer)});
            try zfat.chdrive("0:");
            std.log.info("chdrive: {s}", .{try zfat.getcwd(&buffer)});
        }
        // We have to expect that disk 1 is not enabled anymore:
        std.debug.assert(zfat.chdir("1:") == error.NotEnabled);
    }

    // File.{create,close,write}
    {
        var file = try zfat.File.create("0:/hello.txt");
        defer file.close();

        const content = "Hello, World!\r\n";

        const written = try file.write(content);
        std.debug.assert(written == content.len);
    }

    // File.{open,read,tell,size,rewind,endOfFile}
    {
        const expected_content = "Hello, World!\r\n";

        var file = try zfat.File.open("0:/hello.txt", .{ .access = .read_only, .mode = .open_existing });
        defer file.close();

        const size = file.size();
        std.log.info("size: {}", .{size});
        std.debug.assert(size == expected_content.len);

        const pos0 = file.tell();
        std.log.info("tell: {}", .{pos0});
        std.debug.assert(pos0 == 0);

        std.debug.assert(file.endOfFile() == false);

        var buffer: [2 * expected_content.len]u8 = undefined;

        const bytes_read = try file.read(&buffer);
        std.debug.assert(std.mem.eql(u8, buffer[0..bytes_read], expected_content));

        const pos1 = file.tell();
        std.log.info("tell: {}", .{pos1});
        std.debug.assert(pos1 == expected_content.len);

        std.debug.assert(try file.read(&buffer) == 0);

        std.debug.assert(file.endOfFile() == true);

        try file.rewind();

        std.debug.assert(file.endOfFile() == false);

        const pos2 = file.tell();
        std.log.info("tell: {}", .{pos2});
        std.debug.assert(pos2 == 0);

        try file.seekTo(7);

        const bytes_read2 = try file.read(&buffer);
        std.debug.assert(std.mem.eql(u8, buffer[0..bytes_read2], expected_content[7..]));
    }

    // TODO:
    // File.sync
    // File.truncate
    // File.expand
    // File.hasError

    // set up some files and dirs to create something for Dir apis:
    try zfat.mkdir("0:/build");
    try zfat.mkdir("0:/zig-out");
    try zfat.mkdir("0:/zig-out/bin");
    try zfat.mkdir("0:/code/library");

    try writeFile("0:/build/CMakeCache.txt", "dummy");
    try writeFile("0:/zig-out/bin/zfat-demo", "\xAA\xAA\xAA\xAA");
    try writeFile("0:/code/main.zig", "");
    try writeFile("0:/code/application.zig", "");
    try writeFile("0:/code/library/main.zig", "");
    try writeFile("0:/code/library/demo.zig", "");

    // Dir.{open,close,next,rewind}
    {
        var dir = try zfat.Dir.open("0:/code");
        defer dir.close();

        std.log.info("LIST 0:/code", .{});
        while (try dir.next()) |entry| {
            std.log.info("- {}", .{entry});
        }

        try dir.rewind();

        std.log.info("LIST 0:/code", .{});
        while (try dir.next()) |entry| {
            std.log.info("- {}", .{entry});
        }
    }

    // TODO:
    // api.fdisk
    // api.getfree
    // api.getlabel
    // api.setlabel
    // api.setcp
}

fn writeFile(path: zfat.Path, contents: []const u8) !void {
    var file = try zfat.File.create(path);
    defer file.close();

    try file.writer().writeAll(contents);
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
