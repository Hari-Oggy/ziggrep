pub const packages = struct {
    pub const @"clap-0.10.0-oBajB434AQBDh-Ei3YtoKIRxZacVPF1iSwp3IX_ZB8f0" = struct {
        pub const build_root = "/home/hareesh/.cache/zig/p/clap-0.10.0-oBajB434AQBDh-Ei3YtoKIRxZacVPF1iSwp3IX_ZB8f0";
        pub const build_zig = @import("clap-0.10.0-oBajB434AQBDh-Ei3YtoKIRxZacVPF1iSwp3IX_ZB8f0");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"regex-0.1.3-axC357jaAQBRENglwG9NTcuej8pYz1IZmfwER_AXMlHZ" = struct {
        pub const build_root = "/home/hareesh/.cache/zig/p/regex-0.1.3-axC357jaAQBRENglwG9NTcuej8pYz1IZmfwER_AXMlHZ";
        pub const build_zig = @import("regex-0.1.3-axC357jaAQBRENglwG9NTcuej8pYz1IZmfwER_AXMlHZ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "regex", "regex-0.1.3-axC357jaAQBRENglwG9NTcuej8pYz1IZmfwER_AXMlHZ" },
    .{ "clap", "clap-0.10.0-oBajB434AQBDh-Ei3YtoKIRxZacVPF1iSwp3IX_ZB8f0" },
};
