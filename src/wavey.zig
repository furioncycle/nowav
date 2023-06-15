const std = @import("std");
const testing = std.testing;

const WaveErrors = error{
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
    length: u32,
    fmt: Fmt,
    data: Data,
    fact: ?Fact = null,
    pub fn decode(reader: anytype) !WaveHeader {
        if (!(try parseId("RIFF", reader))) {
            return WaveErrors.NoChunk;
        }

        const fileLen = try reader.readInt(
            u32,
            .Little,
        );

        if (!(try parseId("WAVE", reader))) {
            return WaveErrors.NoChunk;
        }

        var buf: [4]u8 = undefined;
        var counter: usize = fileLen;
        var len: usize = 0;
        _ = try reader.read(&buf);

        var w: WaveHeader = undefined;

        while (counter > 0) : (counter -= len) {
            switch (Ids.toEnum(&buf)) {
                .Fmt => {
                    w.fmt = try Fmt.decode(reader);
                    len = w.length;
                },
                .Data => {
                    w.data = try Data.decode(reader);
                    len = w.length;
                },
                .Fact => {
                    w.fact = try Fact.decode(reader);
                    len = w.length;
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
        if (!(try parseId("data", reader))) {
            return WaveErrors.NoChunk;
        }
        return Data{
            .length = try reader.readInt(u32, .Little),
        };
    }
};

pub fn decode(allocator: std.mem.Allocator, reader: anytype) !Decoder(@TypeOf(reader)) {
    return Decoder(@TypeOf(reader)).init(allocator, reader);
}

pub fn Decoder(comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        inner_reader: ReaderType,
        header: WaveHeader,

        pub fn init(allocator: std.mem.Allocator, in_reader: ReaderType) !Self {
            return Self{
                .allocator = allocator,
                .inner_reader = in_reader,
                .header = try WaveHeader.decode(in_reader),
            };
        }
    };
}

fn parseId(id: []const u8, reader: anytype) !bool {
    var buf: [4]u8 = undefined;

    _ = try reader.read(&buf);
    return std.mem.eql(u8, &buf, id);
}

pub fn encode(allocator: std.mem.Allocator, writer: anytype) !Encode(@TypeOf(writer)) {
    return Encode(@TypeOf(writer)).init(allocator, writer);
}

pub fn Encode(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        inner_writer: WriterType,

        pub fn init(allocator: std.mem.Allocator, in_writer: WriterType) !Self {
            return Self{
                .allocator = allocator,
                .inner_writer = in_writer,
            };
        }

        pub fn writeFmt(self: Self, fmt: Fmt) !void {
            _ = try self.inner_writer.write(&fmt.id);
            _ = try self.inner_writer.writeInt(u32, fmt.length, .Little);
            _ = try self.inner_writer.writeInt(u16, @enumToInt(fmt.audioFormat), .Little);
            _ = try self.inner_writer.writeInt(u16, @enumToInt(fmt.numChannels), .Little);
            _ = try self.inner_writer.writeInt(u32, fmt.sampleRate, .Little);
            _ = try self.inner_writer.writeInt(u32, fmt.byteRate, .Little);
            _ = try self.inner_writer.writeInt(u16, fmt.blockAlign, .Little);
            _ = try self.inner_writer.writeInt(u16, fmt.bitsPerSample, .Little);
        }

        pub fn writeData(self: Self, data: Data) !void {
            _ = try self.inner_writer.write(&data.id);
            _ = try self.inner_writer.writeInt(u32, data.length, .Little);
        }

        pub fn writeHeader(self: Self, header: WaveHeader) !usize {
            var RIFF = [_]u8{ 'R', 'I', 'F', 'F' };
            var WAVE = [_]u8{ 'W', 'A', 'V', 'E' };
            _ = try self.inner_writer.write(&RIFF);
            _ = try self.inner_writer.writeInt(u32, header.length, .Little);
            _ = try self.inner_writer.write(&WAVE);

            try self.writeFmt(header.fmt);
            try self.writeData(header.data);

            return header.length;
        }
    };
}
test "Read empty wave file" {
    const file = try std.fs.cwd().openFile("testSamples/doug.wav", .{});
    defer file.close();

    try testing.expect(decode(testing.allocator, file.reader()) == WaveErrors.NoChunk);
}

test "Parse Header" {
    const h: WaveHeader = .{
        .length = 0,
        .fmt = .{
            .audioFormat = .Pcm,
            .numChannels = .Mono,
            .sampleRate = 44100,
            .byteRate = 44100 * 1 * 16 / 8,
            .blockAlign = 1 * 16 / 8,
            .bitsPerSample = 16,
        },
        .data = .{},
    };

    {
        const file = try std.fs.cwd().createFile("testSamples/dougRiff.wav", .{
            .read = true,
        });
        defer file.close();

        const Wavey = try encode(testing.allocator, file.writer());
        try testing.expect((try Wavey.writeHeader(h)) == 0);
    }

    const file = try std.fs.cwd().openFile("testSamples/dougRiff.wav", .{});
    defer file.close();

    const Wavey = try decode(testing.allocator, file.reader());

    try testing.expectEqualDeep(h, Wavey.header);
}
