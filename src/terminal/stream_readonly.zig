const std = @import("std");
const testing = std.testing;
const stream = @import("stream.zig");
const Action = stream.Action;
const CursorStyle = @import("Screen.zig").CursorStyle;
const Mode = @import("modes.zig").Mode;
const Terminal = @import("Terminal.zig");

/// This is a Stream implementation that processes actions against
/// a Terminal and updates the Terminal state. It is called "readonly" because
/// it only processes actions that modify terminal state, while ignoring
/// any actions that require a response (like queries).
///
/// If you're implementing a terminal emulator that only needs to render
/// output and doesn't need to respond (since it maybe isn't running the
/// actual program), this is the stream type to use. For example, this is
/// ideal for replay tooling, CI logs, PaaS builder output, etc.
pub const Stream = stream.Stream(Handler);

/// See Stream, which is just the stream wrapper around this.
///
/// This isn't attached directly to Terminal because there is additional
/// state and options we plan to add in the future, such as APC/DCS which
/// don't make sense to me to add to the Terminal directly. Instead, you
/// can call `vtHandler` on Terminal to initialize this handler.
pub const Handler = struct {
    /// The terminal state to modify.
    terminal: *Terminal,

    pub fn init(terminal: *Terminal) Handler {
        return .{
            .terminal = terminal,
        };
    }

    pub fn deinit(self: *Handler) void {
        // Currently does nothing but may in the future so callers should
        // call this.
        _ = self;
    }

    pub fn vt(
        self: *Handler,
        comptime action: Action.Tag,
        value: Action.Value(action),
    ) !void {
        switch (action) {
            .print => try self.terminal.print(value.cp),
            .print_repeat => try self.terminal.printRepeat(value),
            .backspace => self.terminal.backspace(),
            .carriage_return => self.terminal.carriageReturn(),
            .linefeed => try self.terminal.linefeed(),
            .index => try self.terminal.index(),
            .next_line => {
                try self.terminal.index();
                self.terminal.carriageReturn();
            },
            .reverse_index => self.terminal.reverseIndex(),
            .cursor_up => self.terminal.cursorUp(value.value),
            .cursor_down => self.terminal.cursorDown(value.value),
            .cursor_left => self.terminal.cursorLeft(value.value),
            .cursor_right => self.terminal.cursorRight(value.value),
            .cursor_pos => self.terminal.setCursorPos(value.row, value.col),
            .cursor_col => self.terminal.setCursorPos(self.terminal.screen.cursor.y + 1, value.value),
            .cursor_row => self.terminal.setCursorPos(value.value, self.terminal.screen.cursor.x + 1),
            .cursor_col_relative => self.terminal.setCursorPos(
                self.terminal.screen.cursor.y + 1,
                self.terminal.screen.cursor.x + 1 +| value.value,
            ),
            .cursor_row_relative => self.terminal.setCursorPos(
                self.terminal.screen.cursor.y + 1 +| value.value,
                self.terminal.screen.cursor.x + 1,
            ),
            .cursor_style => {
                const blink = switch (value) {
                    .default, .steady_block, .steady_bar, .steady_underline => false,
                    .blinking_block, .blinking_bar, .blinking_underline => true,
                };
                const style: CursorStyle = switch (value) {
                    .default, .blinking_block, .steady_block => .block,
                    .blinking_bar, .steady_bar => .bar,
                    .blinking_underline, .steady_underline => .underline,
                };
                self.terminal.modes.set(.cursor_blinking, blink);
                self.terminal.screen.cursor.cursor_style = style;
            },
            .erase_display_below => self.terminal.eraseDisplay(.below, value),
            .erase_display_above => self.terminal.eraseDisplay(.above, value),
            .erase_display_complete => self.terminal.eraseDisplay(.complete, value),
            .erase_display_scrollback => self.terminal.eraseDisplay(.scrollback, value),
            .erase_display_scroll_complete => self.terminal.eraseDisplay(.scroll_complete, value),
            .erase_line_right => self.terminal.eraseLine(.right, value),
            .erase_line_left => self.terminal.eraseLine(.left, value),
            .erase_line_complete => self.terminal.eraseLine(.complete, value),
            .erase_line_right_unless_pending_wrap => self.terminal.eraseLine(.right_unless_pending_wrap, value),
            .delete_chars => self.terminal.deleteChars(value),
            .erase_chars => self.terminal.eraseChars(value),
            .insert_lines => self.terminal.insertLines(value),
            .insert_blanks => self.terminal.insertBlanks(value),
            .delete_lines => self.terminal.deleteLines(value),
            .scroll_up => self.terminal.scrollUp(value),
            .scroll_down => self.terminal.scrollDown(value),
            .horizontal_tab => try self.horizontalTab(value),
            .horizontal_tab_back => try self.horizontalTabBack(value),
            .tab_clear_current => self.terminal.tabClear(.current),
            .tab_clear_all => self.terminal.tabClear(.all),
            .tab_set => self.terminal.tabSet(),
            .tab_reset => self.terminal.tabReset(),
            .set_mode => try self.setMode(value.mode, true),
            .reset_mode => try self.setMode(value.mode, false),
            .save_mode => self.terminal.modes.save(value.mode),
            .restore_mode => {
                const v = self.terminal.modes.restore(value.mode);
                try self.setMode(value.mode, v);
            },
            .top_and_bottom_margin => self.terminal.setTopAndBottomMargin(value.top_left, value.bottom_right),
            .left_and_right_margin => self.terminal.setLeftAndRightMargin(value.top_left, value.bottom_right),
            .left_and_right_margin_ambiguous => {
                if (self.terminal.modes.get(.enable_left_and_right_margin)) {
                    self.terminal.setLeftAndRightMargin(0, 0);
                } else {
                    self.terminal.saveCursor();
                }
            },
            .save_cursor => self.terminal.saveCursor(),
            .restore_cursor => try self.terminal.restoreCursor(),
            .invoke_charset => self.terminal.invokeCharset(value.bank, value.charset, value.locking),
            .configure_charset => self.terminal.configureCharset(value.slot, value.charset),
            .set_attribute => switch (value) {
                .unknown => {},
                else => self.terminal.setAttribute(value) catch {},
            },
            .protected_mode_off => self.terminal.setProtectedMode(.off),
            .protected_mode_iso => self.terminal.setProtectedMode(.iso),
            .protected_mode_dec => self.terminal.setProtectedMode(.dec),
            .mouse_shift_capture => self.terminal.flags.mouse_shift_capture = if (value) .true else .false,
            .kitty_keyboard_push => self.terminal.screen.kitty_keyboard.push(value.flags),
            .kitty_keyboard_pop => self.terminal.screen.kitty_keyboard.pop(@intCast(value)),
            .kitty_keyboard_set => self.terminal.screen.kitty_keyboard.set(.set, value.flags),
            .kitty_keyboard_set_or => self.terminal.screen.kitty_keyboard.set(.@"or", value.flags),
            .kitty_keyboard_set_not => self.terminal.screen.kitty_keyboard.set(.not, value.flags),
            .modify_key_format => {
                self.terminal.flags.modify_other_keys_2 = false;
                switch (value) {
                    .other_keys_numeric => self.terminal.flags.modify_other_keys_2 = true,
                    else => {},
                }
            },
            .active_status_display => self.terminal.status_display = value,
            .decaln => try self.terminal.decaln(),
            .full_reset => self.terminal.fullReset(),
            .start_hyperlink => try self.terminal.screen.startHyperlink(value.uri, value.id),
            .end_hyperlink => self.terminal.screen.endHyperlink(),
            .prompt_start => {
                self.terminal.screen.cursor.page_row.semantic_prompt = .prompt;
                self.terminal.flags.shell_redraws_prompt = value.redraw;
            },
            .prompt_continuation => self.terminal.screen.cursor.page_row.semantic_prompt = .prompt_continuation,
            .prompt_end => self.terminal.markSemanticPrompt(.input),
            .end_of_input => self.terminal.markSemanticPrompt(.command),
            .end_of_command => self.terminal.screen.cursor.page_row.semantic_prompt = .input,
            .mouse_shape => self.terminal.mouse_shape = value,
            .color_operation => try self.colorOperation(value.op, &value.requests),

            // No supported DCS commands have any terminal-modifying effects,
            // but they may in the future. For now we just ignore it.
            .dcs_hook,
            .dcs_put,
            .dcs_unhook,
            => {},

            // APC can modify terminal state (Kitty graphics) but we don't
            // currently support it in the readonly stream.
            .apc_start,
            .apc_end,
            .apc_put,
            => {},

            // Have no terminal-modifying effect
            .bell,
            .enquiry,
            .request_mode,
            .request_mode_unknown,
            .size_report,
            .xtversion,
            .device_attributes,
            .device_status,
            .kitty_keyboard_query,
            .kitty_color_report,
            .window_title,
            .report_pwd,
            .show_desktop_notification,
            .progress_report,
            .clipboard_contents,
            .title_push,
            .title_pop,
            => {},
        }
    }

    inline fn horizontalTab(self: *Handler, count: u16) !void {
        for (0..count) |_| {
            const x = self.terminal.screen.cursor.x;
            try self.terminal.horizontalTab();
            if (x == self.terminal.screen.cursor.x) break;
        }
    }

    inline fn horizontalTabBack(self: *Handler, count: u16) !void {
        for (0..count) |_| {
            const x = self.terminal.screen.cursor.x;
            try self.terminal.horizontalTabBack();
            if (x == self.terminal.screen.cursor.x) break;
        }
    }

    fn setMode(self: *Handler, mode: Mode, enabled: bool) !void {
        // Set the mode on the terminal
        self.terminal.modes.set(mode, enabled);

        // Some modes require additional processing
        switch (mode) {
            .autorepeat,
            .reverse_colors,
            => {},

            .origin => self.terminal.setCursorPos(1, 1),

            .enable_left_and_right_margin => if (!enabled) {
                self.terminal.scrolling_region.left = 0;
                self.terminal.scrolling_region.right = self.terminal.cols - 1;
            },

            .alt_screen_legacy => self.terminal.switchScreenMode(.@"47", enabled),
            .alt_screen => self.terminal.switchScreenMode(.@"1047", enabled),
            .alt_screen_save_cursor_clear_enter => self.terminal.switchScreenMode(.@"1049", enabled),

            .save_cursor => if (enabled) {
                self.terminal.saveCursor();
            } else {
                try self.terminal.restoreCursor();
            },

            .enable_mode_3 => {},

            .@"132_column" => try self.terminal.deccolm(
                self.terminal.screen.alloc,
                if (enabled) .@"132_cols" else .@"80_cols",
            ),

            .synchronized_output,
            .linefeed,
            .in_band_size_reports,
            .focus_event,
            => {},

            .mouse_event_x10 => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .x10;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },
            .mouse_event_normal => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .normal;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },
            .mouse_event_button => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .button;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },
            .mouse_event_any => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .any;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },

            .mouse_format_utf8 => self.terminal.flags.mouse_format = if (enabled) .utf8 else .x10,
            .mouse_format_sgr => self.terminal.flags.mouse_format = if (enabled) .sgr else .x10,
            .mouse_format_urxvt => self.terminal.flags.mouse_format = if (enabled) .urxvt else .x10,
            .mouse_format_sgr_pixels => self.terminal.flags.mouse_format = if (enabled) .sgr_pixels else .x10,

            else => {},
        }
    }

    fn colorOperation(
        self: *Handler,
        op: @import("osc/color.zig").Operation,
        requests: *const @import("osc/color.zig").List,
    ) !void {
        _ = op;
        if (requests.count() == 0) return;

        var it = requests.constIterator(0);
        while (it.next()) |req| {
            switch (req.*) {
                .set => |set| {
                    switch (set.target) {
                        .palette => |i| {
                            self.terminal.color_palette.colors[i] = set.color;
                            self.terminal.color_palette.mask.set(i);
                        },
                        .dynamic,
                        .special,
                        => {},
                    }
                },

                .reset => |target| switch (target) {
                    .palette => |i| {
                        const mask = &self.terminal.color_palette.mask;
                        self.terminal.color_palette.colors[i] = self.terminal.default_palette[i];
                        mask.unset(i);
                    },
                    .dynamic,
                    .special,
                    => {},
                },

                .reset_palette => {
                    const mask = &self.terminal.color_palette.mask;
                    var mask_iterator = mask.iterator(.{});
                    while (mask_iterator.next()) |i| {
                        self.terminal.color_palette.colors[i] = self.terminal.default_palette[i];
                    }
                    mask.* = .initEmpty();
                },

                .query,
                .reset_special,
                => {},
            }
        }
    }
};

test "basic print" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 10, .rows = 10 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    try s.nextSlice("Hello");
    try testing.expectEqual(@as(usize, 5), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.y);

    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("Hello", str);
}

test "cursor movement" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 10, .rows = 10 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Move cursor using escape sequences
    try s.nextSlice("Hello\x1B[1;1H");
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.y);

    // Move to position 2,3
    try s.nextSlice("\x1B[2;3H");
    try testing.expectEqual(@as(usize, 2), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 1), t.screen.cursor.y);
}

test "erase operations" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 20, .rows = 10 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Print some text
    try s.nextSlice("Hello World");
    try testing.expectEqual(@as(usize, 11), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.y);

    // Move cursor to position 1,6 and erase from cursor to end of line
    try s.nextSlice("\x1B[1;6H");
    try s.nextSlice("\x1B[K");

    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("Hello", str);
}

test "tabs" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 10 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    try s.nextSlice("A\tB");
    try testing.expectEqual(@as(usize, 9), t.screen.cursor.x);

    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("A       B", str);
}

test "modes" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Test wraparound mode
    try testing.expect(t.modes.get(.wraparound));
    try s.nextSlice("\x1B[?7l"); // Disable wraparound
    try testing.expect(!t.modes.get(.wraparound));
    try s.nextSlice("\x1B[?7h"); // Enable wraparound
    try testing.expect(t.modes.get(.wraparound));
}

test "scrolling regions" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Set scrolling region from line 5 to 20
    try s.nextSlice("\x1B[5;20r");
    try testing.expectEqual(@as(usize, 4), t.scrolling_region.top);
    try testing.expectEqual(@as(usize, 19), t.scrolling_region.bottom);
    try testing.expectEqual(@as(usize, 0), t.scrolling_region.left);
    try testing.expectEqual(@as(usize, 79), t.scrolling_region.right);
}

test "charsets" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Configure G0 as DEC special graphics
    try s.nextSlice("\x1B(0");
    try s.nextSlice("`"); // Should print diamond character

    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("◆", str);
}

test "alt screen" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 10, .rows = 5 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Write to primary screen
    try s.nextSlice("Primary");
    try testing.expectEqual(Terminal.ScreenType.primary, t.active_screen);

    // Switch to alt screen
    try s.nextSlice("\x1B[?1049h");
    try testing.expectEqual(Terminal.ScreenType.alternate, t.active_screen);

    // Write to alt screen
    try s.nextSlice("Alt");

    // Switch back to primary
    try s.nextSlice("\x1B[?1049l");
    try testing.expectEqual(Terminal.ScreenType.primary, t.active_screen);

    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("Primary", str);
}

test "cursor save and restore" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Move cursor to 10,15
    try s.nextSlice("\x1B[10;15H");
    try testing.expectEqual(@as(usize, 14), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 9), t.screen.cursor.y);

    // Save cursor
    try s.nextSlice("\x1B7");

    // Move cursor elsewhere
    try s.nextSlice("\x1B[1;1H");
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.y);

    // Restore cursor
    try s.nextSlice("\x1B8");
    try testing.expectEqual(@as(usize, 14), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 9), t.screen.cursor.y);
}

test "attributes" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Set bold and write text
    try s.nextSlice("\x1B[1mBold\x1B[0m");

    // Verify we can write attributes - just check the string was written
    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("Bold", str);
}

test "DECALN screen alignment" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 10, .rows = 3 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Run DECALN
    try s.nextSlice("\x1B#8");

    // Verify entire screen is filled with 'E'
    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("EEEEEEEEEE\nEEEEEEEEEE\nEEEEEEEEEE", str);

    // Cursor should be at 1,1
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.y);
}

test "full reset" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Make some changes
    try s.nextSlice("Hello");
    try s.nextSlice("\x1B[10;20H");
    try s.nextSlice("\x1B[5;20r"); // Set scroll region
    try s.nextSlice("\x1B[?7l"); // Disable wraparound

    // Full reset
    try s.nextSlice("\x1Bc");

    // Verify reset state
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.screen.cursor.y);
    try testing.expectEqual(@as(usize, 0), t.scrolling_region.top);
    try testing.expectEqual(@as(usize, 23), t.scrolling_region.bottom);
    try testing.expect(t.modes.get(.wraparound));
}

test "ignores query actions" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // These should be ignored without error
    try s.nextSlice("\x1B[c"); // Device attributes
    try s.nextSlice("\x1B[5n"); // Device status report
    try s.nextSlice("\x1B[6n"); // Cursor position report

    // Terminal should still be functional
    try s.nextSlice("Test");
    const str = try t.plainString(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("Test", str);
}

test "OSC 4 set and reset palette" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 10, .rows = 10 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Save default color
    const default_color_0 = t.default_palette[0];

    // Set color 0 to red
    try s.nextSlice("\x1b]4;0;rgb:ff/00/00\x1b\\");
    try testing.expectEqual(@as(u8, 0xff), t.color_palette.colors[0].r);
    try testing.expectEqual(@as(u8, 0x00), t.color_palette.colors[0].g);
    try testing.expectEqual(@as(u8, 0x00), t.color_palette.colors[0].b);
    try testing.expect(t.color_palette.mask.isSet(0));

    // Reset color 0
    try s.nextSlice("\x1b]104;0\x1b\\");
    try testing.expectEqual(default_color_0, t.color_palette.colors[0]);
    try testing.expect(!t.color_palette.mask.isSet(0));
}

test "OSC 104 reset all palette colors" {
    var t: Terminal = try .init(testing.allocator, .{ .cols = 10, .rows = 10 });
    defer t.deinit(testing.allocator);

    var s: Stream = .initAlloc(testing.allocator, .init(&t));
    defer s.deinit();

    // Set multiple colors
    try s.nextSlice("\x1b]4;0;rgb:ff/00/00\x1b\\");
    try s.nextSlice("\x1b]4;1;rgb:00/ff/00\x1b\\");
    try s.nextSlice("\x1b]4;2;rgb:00/00/ff\x1b\\");
    try testing.expect(t.color_palette.mask.isSet(0));
    try testing.expect(t.color_palette.mask.isSet(1));
    try testing.expect(t.color_palette.mask.isSet(2));

    // Reset all palette colors
    try s.nextSlice("\x1b]104\x1b\\");
    try testing.expectEqual(t.default_palette[0], t.color_palette.colors[0]);
    try testing.expectEqual(t.default_palette[1], t.color_palette.colors[1]);
    try testing.expectEqual(t.default_palette[2], t.color_palette.colors[2]);
    try testing.expect(!t.color_palette.mask.isSet(0));
    try testing.expect(!t.color_palette.mask.isSet(1));
    try testing.expect(!t.color_palette.mask.isSet(2));
}
