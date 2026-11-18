//! Jam related structs.

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const AuthParam = ArrayList(u8);

const Authorization = ArrayList(u8);

const WorkPayload = ArrayList(u8);

const CodeHash = [32]u8;

const HeaderHash = [32]u8;

const StateRootHash = [32]u8;

const BeefyRootHash = [32]u8;

const WorkPackageHash = [32]u8;

const CoreIndex = u16;

const ServiceId = u32;

const Slot = u32;

const Gas = u64;

const BoundedArray = @import("utils.zig").BoundedArray;

// TODO if it gets big change workpackage items container.
const max_workitems_per_package = 4;

pub const AuthParams = struct {
    const Self = @This();
    param: AuthParam,
    package: WorkPackage,
    core: CoreIndex,
    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.param.deinit(alloc);
        self.package.deinit(alloc);
    }
};

const WorkPackage = struct {
    const Self = @This();
    version: u32,
    authorization: Authorization,
    auth_code_host: ServiceId,
    authorizer: Authorizer,
    context: RefineContext,
    items: BoundedArray(WorkItem, max_workitems_per_package),
    // TODO deinit should be automated.
    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.authorization.deinit(alloc);
        self.authorizer.deinit(alloc);
        for (self.items.slice()) |item| {
            @constCast(&item).deinit(alloc);
        }
    }
};

const Authorizer = struct {
    const Self = @This();
    code_hash: CodeHash,
    param: AuthParam,
    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.param.deinit(alloc);
    }
};

const RefineContext = struct {
    const Self = @This();
    anchor: HeaderHash,
    state_root: StateRootHash,
    beefy_root: BeefyRootHash,
    lookup_anchor: HeaderHash,
    lookup_anchor_slot: Slot,
    prerequisite: ?WorkPackageHash,
};

const WorkItem = struct {
    const Self = @This();
    service: ServiceId,
    code_hash: CodeHash,
    payload: WorkPayload,
    gas_limit: Gas,
    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.payload.deinit(alloc);
    }
};
