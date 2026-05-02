const InternPool = @import("InternPool.zig").InternPool;
const Index = @import("InternPool.zig").Index;

pub const Type = struct {
    index: Index,

    pub fn init(index: Index) Type { return .{ .index = index }; }
    pub fn voidType() Type { return .init(InternPool.well_known.void_type); }
    pub fn boolType() Type { return .init(InternPool.well_known.bool_type); }
    pub fn string() Type { return .init(InternPool.well_known.string_type); }

    pub fn isVoid(t: Type) bool { return t.index == InternPool.well_known.void_type; }
    pub fn isBool(t: Type) bool { return t.index == InternPool.well_known.bool_type; }
    pub fn isString(t: Type) bool { return t.index == InternPool.well_known.string_type; }
    pub fn isInteger(t: Type) bool { return t.index >= InternPool.well_known.s8_type and t.index <= InternPool.well_known.u128_type; }
    pub fn isPointer(t: Type) bool { return t.index > InternPool.well_known.any_type and t.index != InternPool.well_known.vector3_type; }
    pub fn isFloat(t: Type) bool { return t.index == InternPool.well_known.float32_type or t.index == InternPool.well_known.float64_type; }
    pub fn isProcedure(t: Type) bool {
        const ip = @import("Sema.zig").activeInternPoolForTypeQueries() orelse return false;
        return switch (ip.key(t.index)) { .type_proc => true, else => false };
    }

    pub fn sizeOf(t: Type) u64 {
        return switch (t.index) {
            InternPool.well_known.void_type => 0,
            InternPool.well_known.bool_type => 1,
            InternPool.well_known.s8_type, InternPool.well_known.u8_type => 1,
            InternPool.well_known.s16_type, InternPool.well_known.u16_type => 2,
            InternPool.well_known.s32_type, InternPool.well_known.u32_type, InternPool.well_known.float32_type => 4,
            InternPool.well_known.s64_type, InternPool.well_known.u64_type, InternPool.well_known.float64_type => 8,
            InternPool.well_known.s128_type, InternPool.well_known.u128_type => 16,
            InternPool.well_known.string_type => 16,
            InternPool.well_known.vector3_type => 12,
            else => 8,
        };
    }
};
