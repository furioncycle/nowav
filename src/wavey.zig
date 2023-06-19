const std = @import("std");
const io = std.io;
const testing = std.testing;

const WaveErrors = error{
    NoRiffChunk,
    NoWaveChunk,
    NoDataChunk,
    NoChunk,
};

const Ids = enum {
    Fmt,
    Data,
    Fact,

    pub fn toEnum(str: []u8) Ids {
        if (std.mem.eql(u8, "fmt ", str)) {
            return .Fmt;
        } else if (std.mem.eql(u8, "data", str)) {
            return .Data;
        } else {
            return .Fact;
        }
    }
};

const WaveHeader = struct {
    fmt: Fmt,
    data: Data,
    // fact: ?Fact = null,
    pub fn decode(reader: anytype) !WaveHeader {
        if (!(try parseId("RIFF", reader))) {
            return WaveErrors.NoRiffChunk;
        }

        const fileLen = try reader.readInt(
            u32,
            .Little,
        );

        if (!(try parseId("WAVE", reader))) {
            return WaveErrors.NoWaveChunk;
        }

        var buf: [4]u8 = undefined;
        var counter: usize = fileLen;
        var len: usize = 0;

        var w: WaveHeader = undefined;

        while (counter > 0) : (counter -= len) {
            _ = try reader.read(&buf);
            switch (Ids.toEnum(&buf)) {
                .Fmt => {
                    w.fmt = try Fmt.decode(reader);
                    len = w.fmt.length + @sizeOf([4]u8);
                },
                .Data => {
                    w.data = try Data.decode(reader);
                    len = w.data.length + @sizeOf([4]u8);
                },
                .Fact => {
                    // w.fact = try Fact.decode(reader);
                },
            }
        }

        return w;
    }
};

const Fact = struct {
    length: u32 = 0,

    pub fn decode(reader: anytype) !Fact {
        _ = reader;
        return Fact{};
    }
};

const FormatType = enum(u8) {
    Pcm = 1,
    _,
};

const Channels = enum(u8) {
    Mono = 1,
    Stereo = 2,
    _,
};

const Fmt = struct {
    id: [4]u8 = [_]u8{ 'f', 'm', 't', ' ' },
    length: u32 = 0,
    audioFormat: FormatType = .Pcm,
    numChannels: Channels = .Mono,
    sampleRate: u32 = 0,
    byteRate: u32 = 0,
    blockAlign: u16 = 0,
    bitsPerSample: u16 = 0,

    fn decode(reader: anytype) !Fmt {
        return Fmt{
            .length = try reader.readInt(u32, .Little),
            .audioFormat = @intToEnum(FormatType, try reader.readInt(u16, .Little)),
            .numChannels = @intToEnum(Channels, try reader.readInt(u16, .Little)),
            .sampleRate = try reader.readInt(u32, .Little),
            .byteRate = try reader.readInt(u32, .Little),
            .blockAlign = try reader.readInt(u16, .Little),
            .bitsPerSample = try reader.readInt(u16, .Little),
        };
    }
};

const Data = struct {
    id: [4]u8 = [_]u8{ 'd', 'a', 't', 'a' },
    length: u32 = 0,

    fn decode(reader: anytype) !Data {
        return Data{
            .length = try reader.readInt(u32, .Little),
        };
    }
};

pub fn decode(allocator: std.mem.Allocator, file: std.fs.File) !Decoder(@TypeOf(file.reader())) {
    return Decoder(@TypeOf(file.reader())).init(allocator, file);
}

pub fn Decoder(comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        header: WaveHeader,
        file: std.fs.File,
        inner_reader: ReaderType,

        pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !Self {
            return Self{
                .allocator = allocator,
                .file = file,
                .inner_reader = file.reader(),
                .header = try WaveHeader.decode(file.reader()),
            };
        }
    };
}

fn parseId(id: []const u8, reader: anytype) !bool {
    var buf: [4]u8 = undefined;

    _ = try reader.read(&buf);
    return std.mem.eql(u8, &buf, id);
}

pub fn encode(allocator: std.mem.Allocator, file: std.fs.File) !Encode(@TypeOf(file.writer())) {
    return Encode(@TypeOf(file.writer())).init(allocator, file);
}

pub fn Encode(comptime WriterType: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        file: std.fs.File,
        inner_writer: WriterType,

        pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !Self {
            return Self{
                .allocator = allocator,
                .file = file,
                .inner_writer = file.writer(),
            };
        }

        pub fn writeFmt(self: Self, fmt: Fmt) !usize {
            _ = try self.inner_writer.write(&fmt.id);
            try self.inner_writer.writeInt(u32, fmt.length, .Little);
            try self.inner_writer.writeInt(u16, @enumToInt(fmt.audioFormat), .Little);
            try self.inner_writer.writeInt(u16, @enumToInt(fmt.numChannels), .Little);
            try self.inner_writer.writeInt(u32, fmt.sampleRate, .Little);
            try self.inner_writer.writeInt(u32, fmt.byteRate, .Little);
            try self.inner_writer.writeInt(u16, fmt.blockAlign, .Little);
            try self.inner_writer.writeInt(u16, fmt.bitsPerSample, .Little);
            return fmt.length + @sizeOf([4]u8);
        }

        pub fn writeData(self: Self, data: Data) !usize {
            _ = try self.inner_writer.write(&data.id);
            try self.inner_writer.writeInt(u32, data.length, .Little);
            return @sizeOf([4]u8) + data.length;
        }

        pub fn writeHeader(self: Self, header: WaveHeader) !usize {
            var RIFF = [_]u8{ 'R', 'I', 'F', 'F' };
            var WAVE = [_]u8{ 'W', 'A', 'V', 'E' };
            _ = try self.inner_writer.write(&RIFF);
            try self.inner_writer.writeInt(u32, 0, .Little);
            _ = try self.inner_writer.write(&WAVE);

            const fmtLen = try self.writeFmt(header.fmt);
            const dataLen = try self.writeData(header.data);

            //Go back to write the file length
            try self.file.seekTo(RIFF.len);
            try self.inner_writer.writeInt(u32, @intCast(u32, fmtLen) + @intCast(u32, dataLen), .Little);

            return fmtLen + dataLen;
        }
    };
}

test "Read empty wave file" {
    const file = try std.fs.cwd().openFile("testSamples/doug.wav", .{});
    defer file.close();

    try testing.expect(decode(testing.allocator, file) == WaveErrors.NoRiffChunk);
}

test "Parse Header" {
    const h: WaveHeader = .{
        .fmt = .{
            .length = @sizeOf(Fmt),
            .audioFormat = .Pcm,
            .numChannels = .Mono,
            .sampleRate = 44100,
            .byteRate = 44100 * 1 * 16 / 8,
            .blockAlign = 1 * 16 / 8,
            .bitsPerSample = 16,
        },
        .data = .{
            .length = 0,
        },
    };

    {
        const file = try std.fs.cwd().createFile("testSamples/dougRiff.wav", .{
            .read = true,
        });
        defer file.close();

        const Wavey = try encode(testing.allocator, file);
        const v = try Wavey.writeHeader(h);
        try testing.expect(v == @sizeOf(WaveHeader));
    }

    const file = try std.fs.cwd().openFile("testSamples/dougRiff.wav", .{});
    defer file.close();
    const Wavey = try decode(testing.allocator, file);

    try testing.expectEqualDeep(h, Wavey.header);
}
