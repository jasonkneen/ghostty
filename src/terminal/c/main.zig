pub const osc = @import("osc.zig");

// The full C API, unexported.
pub const osc_new = osc.new;
pub const osc_free = osc.free;
pub const osc_reset = osc.reset;
pub const osc_next = osc.next;
pub const osc_end = osc.end;
pub const osc_command_type = osc.commandType;
pub const osc_command_data = osc.commandData;

test {
    _ = osc;

    // We want to make sure we run the tests for the C allocator interface.
    _ = @import("../../lib/allocator.zig");
}
