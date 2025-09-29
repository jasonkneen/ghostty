//! This is the public API of the ghostty-vt Zig module.
//!
//! WARNING: The API is not guaranteed to be stable.
//!
//! The functionality is extremely stable, since it is extracted
//! directly from Ghostty which has been used in real world scenarios
//! by thousands of users for years. However, the API itself (functions,
//! types, etc.) may change without warning. We're working on stabilizing
//! this in the future.
const lib = @This();

// The public API below reproduces a lot of terminal/main.zig but
// is separate because (1) we need our root file to be in `src/`
// so we can access other directories and (2) we may want to withhold
// parts of `terminal` that are not ready for public consumption
// or are too Ghostty-internal.
const terminal = @import("terminal/main.zig");

pub const apc = terminal.apc;
pub const dcs = terminal.dcs;
pub const osc = terminal.osc;
pub const point = terminal.point;
pub const color = terminal.color;
pub const device_status = terminal.device_status;
pub const kitty = terminal.kitty;
pub const modes = terminal.modes;
pub const page = terminal.page;
pub const parse_table = terminal.parse_table;
pub const search = terminal.search;
pub const size = terminal.size;
pub const x11_color = terminal.x11_color;

pub const Charset = terminal.Charset;
pub const CharsetSlot = terminal.CharsetSlot;
pub const CharsetActiveSlot = terminal.CharsetActiveSlot;
pub const Cell = page.Cell;
pub const Coordinate = point.Coordinate;
pub const CSI = Parser.Action.CSI;
pub const DCS = Parser.Action.DCS;
pub const MouseShape = terminal.MouseShape;
pub const Page = page.Page;
pub const PageList = terminal.PageList;
pub const Parser = terminal.Parser;
pub const Pin = PageList.Pin;
pub const Point = point.Point;
pub const Screen = terminal.Screen;
pub const ScreenType = Terminal.ScreenType;
pub const Selection = terminal.Selection;
pub const SizeReportStyle = terminal.SizeReportStyle;
pub const StringMap = terminal.StringMap;
pub const Style = terminal.Style;
pub const Terminal = terminal.Terminal;
pub const Stream = terminal.Stream;
pub const Cursor = Screen.Cursor;
pub const CursorStyle = Screen.CursorStyle;
pub const CursorStyleReq = terminal.CursorStyle;
pub const DeviceAttributeReq = terminal.DeviceAttributeReq;
pub const Mode = modes.Mode;
pub const ModePacked = modes.ModePacked;
pub const ModifyKeyFormat = terminal.ModifyKeyFormat;
pub const ProtectedMode = terminal.ProtectedMode;
pub const StatusLineType = terminal.StatusLineType;
pub const StatusDisplay = terminal.StatusDisplay;
pub const EraseDisplay = terminal.EraseDisplay;
pub const EraseLine = terminal.EraseLine;
pub const TabClear = terminal.TabClear;
pub const Attribute = terminal.Attribute;

comptime {
    // If we're building the C library (vs. the Zig module) then
    // we want to reference the C API so that it gets exported.
    if (@import("root") == lib) {
        const c = terminal.c_api;
        @export(&c.osc_new, .{ .name = "ghostty_osc_new" });
        @export(&c.osc_free, .{ .name = "ghostty_osc_free" });
        @export(&c.osc_next, .{ .name = "ghostty_osc_next" });
        @export(&c.osc_reset, .{ .name = "ghostty_osc_reset" });
        @export(&c.osc_end, .{ .name = "ghostty_osc_end" });
        @export(&c.osc_command_type, .{ .name = "ghostty_osc_command_type" });
        @export(&c.osc_command_data, .{ .name = "ghostty_osc_command_data" });
    }
}

test {
    _ = terminal;
    _ = @import("lib/main.zig");
    if (comptime terminal.options.c_abi) {
        _ = terminal.c_api;
    }
}
