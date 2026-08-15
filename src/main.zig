const r4os = @import("r4os");

const clipboard_buffer_size: usize = @as(usize, r4os.clipboard.max_text_bytes) + 1;

const DiagApi = struct {
    sys: r4os.r4sys.Context,
    desk: r4os.r4desk.Context,

    fn init(r4_app: *r4os.App) ?DiagApi {
        return .{
            .sys = r4_app.system(),
            .desk = r4_app.desktop() orelse return null,
        };
    }
};

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var ctx = DiagApi.init(r4_app) orelse return r4os.abi.err_no_group;
    ctx.sys.println("CLIPD");

    if (!ctx.desk.hasFn("clipboard_info")) return fail(&ctx, "contract unsupported");
    if (!ctx.sys.hasFn("service_call")) return fail(&ctx, "service api unsupported");
    var service_handle = waitClipsvc(&ctx) orelse return fail(&ctx, "clipsvc unavailable");
    ctx.sys.println("CLIPD service=CLIPSVC");
    _ = ctx.sys.serviceClose(service_handle);

    if (ctx.desk.clipboardClear() != 0) return fail(&ctx, "clear failed");

    var info = r4os.abi.ClipboardInfo{};
    if (ctx.desk.clipboardInfo(&info) != 0) return fail(&ctx, "info failed");
    if (info.capacity != r4os.clipboard.max_text_bytes) return fail(&ctx, "bad capacity");
    if (info.length != 0) return fail(&ctx, "clear length");
    const clear_revision = info.revision;

    service_handle = waitClipsvc(&ctx) orelse return fail(&ctx, "clipsvc reopen failed");
    var service_info = r4os.abi.ClipboardInfo{};
    if (!clipsvcInfo(&ctx, service_handle, &service_info) or service_info.length != 0) return fail(&ctx, "service clear mismatch");
    _ = ctx.sys.serviceClose(service_handle);

    const sample = "R4OS clipboard\r\nline";
    if (ctx.desk.clipboardWrite(sample) != @as(i32, @intCast(sample.len))) return fail(&ctx, "write failed");
    if (ctx.desk.clipboardInfo(&info) != 0) return fail(&ctx, "info after write failed");
    if (info.length != @as(u32, @intCast(sample.len))) return fail(&ctx, "bad length");
    if (info.revision == clear_revision) return fail(&ctx, "revision unchanged");
    if ((info.flags & r4os.abi.clipboard_flag_has_text) == 0) return fail(&ctx, "missing has-text flag");

    var read_buf: [64]u8 = .{0} ** 64;
    const read_len = ctx.desk.clipboardRead(read_buf[0..]);
    if (read_len != @as(i32, @intCast(sample.len))) return fail(&ctx, "read failed");
    if (!equalBytes(read_buf[0..@as(usize, @intCast(read_len))], sample)) return fail(&ctx, "read mismatch");

    service_handle = waitClipsvc(&ctx) orelse return fail(&ctx, "clipsvc read open failed");
    var service_read: [64]u8 = .{0} ** 64;
    const service_read_len = clipsvcRead(&ctx, service_handle, service_read[0..]);
    if (service_read_len != @as(i32, @intCast(sample.len)) or !equalBytes(service_read[0..sample.len], sample)) return fail(&ctx, "service route mismatch");
    _ = ctx.sys.serviceClose(service_handle);

    var small: [4]u8 = .{0} ** 4;
    if (ctx.desk.clipboardRead(small[0..]) != r4os.abi.clipboard_error_buffer_too_small) return fail(&ctx, "small buffer accepted");

    const with_zero = [_]u8{ 'A', 0, 'B' };
    if (ctx.desk.clipboardWrite(with_zero[0..]) != r4os.abi.clipboard_error_invalid) return fail(&ctx, "nul accepted");

    const too_large: [clipboard_buffer_size]u8 = .{'X'} ** clipboard_buffer_size;
    if (ctx.desk.clipboardWrite(too_large[0..]) != r4os.abi.clipboard_error_too_large) return fail(&ctx, "oversize accepted");

    if (ctx.desk.clipboardClear() != 0) return fail(&ctx, "final clear failed");
    service_handle = waitClipsvc(&ctx) orelse return fail(&ctx, "clipsvc final open failed");
    if (!clipsvcInfo(&ctx, service_handle, &service_info) or service_info.length != 0) return fail(&ctx, "service final clear mismatch");
    _ = ctx.sys.serviceClose(service_handle);

    ctx.sys.println("CLIPD OK");
    return 0;
}

fn fail(ctx: *const DiagApi, reason: []const u8) i32 {
    ctx.sys.write("CLIPD FAILED: ");
    ctx.sys.write(reason);
    ctx.sys.write("\r\n");
    return 1;
}

fn equalBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn waitClipsvc(ctx: *const DiagApi) ?u32 {
    var tick: u32 = 0;
    while (tick < 160) : (tick += 1) {
        var service_info = r4os.abi.ServiceInfo{};
        const rc = ctx.sys.serviceOpen("CLIPSVC", &service_info);
        if (rc == r4os.abi.service_api_result_ok and service_info.handle != 0) return service_info.handle;
        ctx.sys.sleepTicks(1);
    }
    return null;
}

fn clipsvcInfo(ctx: *const DiagApi, handle: u32, out: *r4os.abi.ClipboardInfo) bool {
    var header = r4os.abi.ServiceMessageHeader{};
    var response: [16]u8 = .{0} ** 16;
    const got = ctx.sys.serviceCall(handle, r4os.abi.clipboard_service_op_info, "", &header, response[0..], 120);
    if (got != 16 or header.status != r4os.abi.service_api_result_ok) return false;
    out.* = .{
        .capacity = readLe32(response[0..4]),
        .length = readLe32(response[4..8]),
        .revision = readLe32(response[8..12]),
        .flags = readLe32(response[12..16]),
    };
    return true;
}

fn clipsvcRead(ctx: *const DiagApi, handle: u32, out: []u8) i32 {
    var header = r4os.abi.ServiceMessageHeader{};
    const got = ctx.sys.serviceCall(handle, r4os.abi.clipboard_service_op_read, "", &header, out, 120);
    if (got < 0) return got;
    if (header.status < 0) return header.status;
    return got;
}

fn readLe32(data: []const u8) u32 {
    return @as(u32, data[0]) |
        (@as(u32, data[1]) << 8) |
        (@as(u32, data[2]) << 16) |
        (@as(u32, data[3]) << 24);
}
