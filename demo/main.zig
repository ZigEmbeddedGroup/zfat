const std = @import("std");

const fatfs = @import("zfat");

// requires pointer stability
var global_fs: fatfs.FileSystem = undefined;

// requires pointer stability
var image_disk: Disk = undefined;

pub fn main() !u8 {
    image_disk = Disk{
        .sectors = try std.heap.page_allocator.alloc([Disk.sector_size]u8, 100_000), // ~40 MB
    };
    defer std.heap.page_allocator.free(image_disk.sectors);

    fatfs.disks[0] = &image_disk.interface;

    var workspace: [4096]u8 = undefined;
    try fatfs.mkfs("0:", .{
        .filesystem = .fat32,
        .sector_align = 1,
        .use_partitions = true,
    }, &workspace);

    try global_fs.mount("0:", true);
    defer fatfs.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

    {
        var file = try fatfs.File.create("0:/firmware.uf2");
        defer file.close();

        try file.writer().writeAll("Hello, World!\r\n");
    }

    return 0;
}

pub const Disk = struct {
    const sector_size = 512;

    interface: fatfs.Disk = fatfs.Disk{
        .getStatusFn = getStatus,
        .initializeFn = initialize,
        .readFn = read,
        .writeFn = write,
        .ioctlFn = ioctl,
    },
    sectors: [][sector_size]u8,

    pub fn getStatus(interface: *fatfs.Disk) fatfs.Disk.Status {
        const self: *Disk = @fieldParentPtr("interface", interface);
        _ = self;
        return fatfs.Disk.Status{
            .initialized = true,
            .disk_present = true,
            .write_protected = false,
        };
    }

    pub fn initialize(interface: *fatfs.Disk) fatfs.Disk.Error!fatfs.Disk.Status {
        const self: *Disk = @fieldParentPtr("interface", interface);
        return getStatus(&self.interface);
    }

    pub fn read(interface: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self: *Disk = @fieldParentPtr("interface", interface);

        std.log.info("read({*}, {}, {})", .{ buff, sector, count });

        var sectors = std.io.fixedBufferStream(std.mem.sliceAsBytes(self.sectors));
        sectors.seekTo(sector * sector_size) catch return error.IoError;
        sectors.reader().readNoEof(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn write(interface: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self: *Disk = @fieldParentPtr("interface", interface);

        std.log.info("write({*}, {}, {})", .{ buff, sector, count });

        var sectors = std.io.fixedBufferStream(std.mem.sliceAsBytes(self.sectors));
        sectors.seekTo(sector * sector_size) catch return error.IoError;
        sectors.writer().writeAll(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn ioctl(interface: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
        const self: *Disk = @fieldParentPtr("interface", interface);

        switch (cmd) {
            .sync => {},
            .get_sector_count => {
                @as(*align(1) fatfs.LBA, @ptrCast(buff)).* = @intCast(self.sectors.len);
            },
            else => {
                std.log.err("invalid ioctl: {}", .{cmd});
                return error.InvalidParameter;
            },
        }
    }
};
