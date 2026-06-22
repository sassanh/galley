const std = @import("std");
const builtin = @import("builtin");
const Context = @import("root").data_structures.Context;
const parser = @import("parser");

pub fn ASTAllocator(comptime PayloadType: type) type {
    return struct {
        const ASTNodeType = ASTNode(PayloadType);
        const invalid_pointer = parser.preallocated_nodes;
        const default: ASTNodeType = .{
            .text_start = 0,
            .text_length = 0,
            .first_child = invalid_pointer,
            .last_child = invalid_pointer,
            .parent = invalid_pointer,
            .prior = invalid_pointer,
            .next = invalid_pointer,
            .variable = ASTNodeType.invalid_variable,
            .payload = undefined,
        };

        counter: ASTNodeType.Pointer = 0,
        memory: []ASTNodeType,

        const Self = @This();

        pub fn init_capacity(allocator: std.mem.Allocator) !ASTAllocator(PayloadType) {
            const memory = try allocator.alloc(ASTNodeType, parser.preallocated_nodes + 1);

            @memset(memory, default);

            return .{ .memory = memory };
        }

        pub fn reset(self: *Self) void {
            @memset(self.memory[0..self.counter], default);
            self.counter = 0;
        }

        pub inline fn at(self: *Self, address: ASTNodeType.Pointer) *ASTNodeType {
            return &self.memory[address];
        }

        pub inline fn create(self: *Self, start: Context.Size, variable: u16) ASTNodeType.Pointer {
            const address = self.counter;
            self.counter += 1;

            if (comptime builtin.mode == .Debug) {
                if (self.counter >= self.memory.len) {
                    std.debug.print("Ran out of preallocated ast nodes of {d}.\n", .{self.memory.len});
                    unreachable;
                }
            }

            const node = &self.memory[address];
            node.text_start = start;
            node.variable = variable;
            node.payload = .{};

            return address;
        }

        pub inline fn terminal_node(terminal: u8) ASTNodeType.Pointer {
            return terminal;
        }

        pub inline fn index(self: *const Self, node: *const ASTNodeType) ASTNodeType.Pointer {
            return @intCast((node - &self.memory[0]) / @sizeOf(ASTNodeType));
        }
    };
}

pub fn ASTNode(comptime PayloadType: type) type {
    return struct {
        pub const Pointer = u16;
        pub const invalid_pointer: u16 = ASTAllocator(Self).invalid_pointer;
        pub const invalid_variable: u16 = std.math.maxInt(u16);

        text_start: Context.Size,
        text_length: Context.Size,

        first_child: Pointer,
        last_child: Pointer,
        parent: Pointer,
        prior: Pointer,
        next: Pointer,

        variable: u16 = invalid_variable,
        payload: PayloadType,

        const Self = @This();

        pub fn Iterator(comptime ContextType: type) type {
            return struct {
                context: ContextType,
                current: Pointer,

                pub fn next(self: *@This()) ?Self.Pointer {
                    const current_address = self.current;
                    if (current_address == invalid_pointer) {
                        return null;
                    }
                    const item = self.context.node_allocator.at(current_address);
                    self.current = item.next;
                    return current_address;
                }
            };
        }

        // Find the last node in the chain. This is extremely fast for single nodes (common case).
        fn getLastNode(context: *Context, first_node: Pointer) Pointer {
            const first = context.node_allocator.at(first_node);
            if (first.next != invalid_pointer) {
                var curr = first.next;
                while (context.node_allocator.at(curr).next != invalid_pointer) {
                    curr = context.node_allocator.at(curr).next;
                }
                return curr;
            }
            return first_node;
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately before `self_address`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insert_before(self_address: Pointer, context: *Context, first_node: Pointer) !void {
            const self = context.node_allocator.at(self_address);
            const first = context.node_allocator.at(first_node);

            if (comptime builtin.mode == .Debug) {
                std.debug.assert(first.parent == invalid_pointer);
                std.debug.assert(first.prior == invalid_pointer);
            }

            const last_node = getLastNode(context, first_node);
            const last = context.node_allocator.at(last_node);

            // 1. Wire siblings
            first.prior = self.prior;
            last.next = self_address;
            if (self.prior != invalid_pointer) {
                context.node_allocator.at(self.prior).next = first_node;
            }
            self.prior = last_node;

            // 2. Conditionally update parent
            if (self.parent != invalid_pointer) {
                const parent_node = context.node_allocator.at(self.parent);
                // Update parent pointers on all nodes in the inserted chain
                var current = first_node;
                while (true) {
                    const node = context.node_allocator.at(current);
                    node.parent = self.parent;
                    if (current == last_node) break;
                    current = node.next;
                }

                // If self_address was the first_child of the parent, update first_child to first_node
                if (parent_node.first_child == self_address) {
                    parent_node.first_child = first_node;
                }
            }
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately after `self_address`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insert_after(self_address: Pointer, context: *Context, first_node: Pointer) !void {
            const self = context.node_allocator.at(self_address);
            const first = context.node_allocator.at(first_node);

            if (comptime builtin.mode == .Debug) {
                std.debug.assert(first.parent == invalid_pointer);
                std.debug.assert(first.prior == invalid_pointer);
            }

            const last_node = getLastNode(context, first_node);
            const last = context.node_allocator.at(last_node);

            // 1. Wire siblings
            first.prior = self_address;
            last.next = self.next;
            if (self.next != invalid_pointer) {
                context.node_allocator.at(self.next).prior = last_node;
            }
            self.next = first_node;

            // 2. Conditionally update parent
            if (self.parent != invalid_pointer) {
                const parent_node = context.node_allocator.at(self.parent);
                // Update parent pointers on all nodes in the inserted chain
                var current = first_node;
                while (true) {
                    const node = context.node_allocator.at(current);
                    node.parent = self.parent;
                    if (current == last_node) break;
                    current = node.next;
                }

                // If self_address was the last_child of the parent, update last_child to last_node
                if (parent_node.last_child == self_address) {
                    parent_node.last_child = last_node;
                }
            }
        }

        /// Insert `first_node` (and any chain) into `self.children` at position `index`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insert_children(self_address: Pointer, context: *Context, index: u8, first_node: Pointer) !void {
            const self = context.node_allocator.at(self_address);
            if (comptime builtin.mode == .Debug) {
                std.debug.assert(context.node_allocator.at(first_node).parent == invalid_pointer);
                std.debug.assert(context.node_allocator.at(first_node).prior == invalid_pointer);
            }

            if (self.first_child == invalid_pointer) {
                if (comptime builtin.mode == .Debug) {
                    std.debug.assert(index == 0);
                }
                self.first_child = first_node;
                const last_node = getLastNode(context, first_node);
                self.last_child = last_node;

                // Update parent pointer on the inserted chain
                var current = first_node;
                while (true) {
                    const node = context.node_allocator.at(current);
                    node.parent = self_address;
                    if (current == last_node) break;
                    current = node.next;
                }
            } else {
                if (comptime builtin.mode == .Debug) {
                    // Ensure index is valid
                    var count: u8 = 0;
                    var curr = self.first_child;
                    while (curr != invalid_pointer) {
                        count += 1;
                        curr = context.node_allocator.at(curr).next;
                    }
                    std.debug.assert(index <= count);
                }

                if (index == 0) {
                    try Self.insert_before(self.first_child, context, first_node);
                } else {
                    // Traverse to find the child at index - 1
                    var current_child = self.first_child;
                    var i: u8 = 0;
                    while (i < index - 1) : (i += 1) {
                        if (current_child != invalid_pointer) {
                            current_child = context.node_allocator.at(current_child).next;
                        } else {
                            break;
                        }
                    }
                    if (current_child != invalid_pointer) {
                        try Self.insert_after(current_child, context, first_node);
                    } else {
                        return error.IndexOutOfBounds;
                    }
                }
            }
        }

        /// Append `first_node` (and any chain) to `self.children` in the end.
        /// The appended nodes must be detached orphans (no parent, no prior).
        pub fn append_children(self_address: Pointer, context: *Context, first_node: Pointer) !void {
            const self = context.node_allocator.at(self_address);
            const first = context.node_allocator.at(first_node);

            if (comptime builtin.mode == .Debug) {
                std.debug.assert(first.parent == invalid_pointer);
                std.debug.assert(first.prior == invalid_pointer);
            }

            const last_node = getLastNode(context, first_node);

            // Update parent pointers on all nodes in the appended chain
            var current = first_node;
            while (true) {
                const node = context.node_allocator.at(current);
                node.parent = self_address;
                if (current == last_node) break;
                current = node.next;
            }

            if (self.last_child != invalid_pointer) {
                const last_addr = self.last_child;
                const last = context.node_allocator.at(last_addr);
                // Wire siblings
                first.prior = last_addr;
                context.node_allocator.at(last_node).next = invalid_pointer; // End of list
                last.next = first_node;
                self.last_child = last_node;
            } else {
                // First child in the parent
                self.first_child = first_node;
                self.last_child = last_node;
                first.prior = invalid_pointer;
                context.node_allocator.at(last_node).next = invalid_pointer;
            }
        }

        /// Immediately append a single orphan child node to `self_address` with zero overhead.
        /// This assumes the child is a single node (not a chain) and is already an orphan and the parent has no children.
        pub inline fn immediate_insert_child(
            self: *Self,
            self_address: Pointer,
            child_address: Pointer,
            context: *Context,
        ) void {
            const child = context.node_allocator.at(child_address);
            const last_child_node = context.node_allocator.at(self.last_child);

            child.parent = self_address;
            child.prior = self.last_child;
            child.next = invalid_pointer;

            if (self.first_child == invalid_pointer) {
                self.first_child = child_address;
            }
            last_child_node.next = child_address;
            self.last_child = child_address;
        }

        /// Remove `count` consecutive siblings starting at `self_address`, detaching them from parent
        /// and sibling chains. Returns a caller-owned slice of the removed nodes.
        pub fn remove(self_address: Pointer, context: *Context, count: u8) ![]Pointer {
            if (count == 0) {
                return &[0]Pointer{};
            }

            const self = context.node_allocator.at(self_address);

            var last_removed_address = self_address;
            var i: u8 = 1;
            while (i < count) : (i += 1) {
                const last_removed = context.node_allocator.at(last_removed_address);
                last_removed_address = last_removed.next;
                if (last_removed_address == invalid_pointer) return error.CountExceedsRemainingSiblings;
            }

            const prior_node_address = self.prior;
            const next_node_address = context.node_allocator.at(last_removed_address).next;

            if (prior_node_address != invalid_pointer) {
                context.node_allocator.at(prior_node_address).next = next_node_address;
            }
            if (next_node_address != invalid_pointer) {
                context.node_allocator.at(next_node_address).prior = prior_node_address;
            }

            self.prior = invalid_pointer;
            context.node_allocator.at(last_removed_address).next = invalid_pointer;

            const removed_items = try context.arena_allocator.alloc(Pointer, count);

            if (self.parent != invalid_pointer) {
                const parent_node = context.node_allocator.at(self.parent);

                // Update parent's first_child and last_child if they were removed
                if (parent_node.first_child == self_address) {
                    parent_node.first_child = next_node_address;
                }
                if (parent_node.last_child == last_removed_address) {
                    parent_node.last_child = prior_node_address;
                }

                // Extract to the return slice and clear parents
                var current = self_address;
                var idx: u8 = 0;
                while (current != invalid_pointer) : (idx += 1) {
                    const node = context.node_allocator.at(current);
                    removed_items[idx] = current;
                    node.parent = invalid_pointer;
                    if (current == last_removed_address) break;
                    current = node.next;
                }
            } else {
                var current = self_address;
                var idx: u8 = 0;
                while (current != invalid_pointer) : (idx += 1) {
                    const node = context.node_allocator.at(current);
                    removed_items[idx] = current;
                    if (current == last_removed_address) break;
                    current = node.next;
                }
            }

            return removed_items;
        }

        /// Remove `self_address`, detaching from parent and sibling chains.
        /// Returns the removed node address.
        pub fn remove_self(self_address: Pointer, context: *Context) !Pointer {
            return (try Self.remove(self_address, context, 1))[0];
        }

        /// Remove `count` consecutive children starting at `index`, detaching them from parent
        /// and sibling chains. Returns a caller-owned slice of the removed nodes.
        pub fn remove_children(self_address: Pointer, context: *Context, index: u8, count: u8) ![]Pointer {
            const self = context.node_allocator.at(self_address);
            if (count == 0) {
                return &[0]Pointer{};
            }

            // Find the child at index
            var current_child = self.first_child;
            var i: u8 = 0;
            while (i < index) : (i += 1) {
                if (current_child != invalid_pointer) {
                    current_child = context.node_allocator.at(current_child).next;
                } else {
                    break;
                }
            }

            if (current_child != invalid_pointer) {
                return try Self.remove(current_child, context, count);
            } else {
                return error.IndexOutOfBounds;
            }
        }

        /// Remove one child at `index`, detaching it from parent and sibling chains.
        /// Returns a caller-owned pointer to the removed node.
        pub fn remove_child(self_address: Pointer, context: *Context, index: u8) !Pointer {
            const removed_address = (try Self.remove_children(self_address, context, index, 1))[0];
            return removed_address;
        }

        /// Clean all children detaching them from parent and sibling chains.
        /// Returns a caller-owned slice of the removed nodes.
        pub fn clean_children(self_address: Pointer, context: *Context) ![]Pointer {
            // Count children
            var count: u8 = 0;
            var curr = context.node_allocator.at(self_address).first_child;
            while (curr != invalid_pointer) {
                count += 1;
                curr = context.node_allocator.at(curr).next;
            }
            return try Self.remove_children(self_address, context, 0, count);
        }

        pub fn augmented_back_length(self_address: Pointer, node_allocator: *ASTAllocator(PayloadType)) u8 {
            const self = node_allocator.at(self_address);
            if (self.prior != invalid_pointer) return 1 + Self.augmented_back_length(self.prior, node_allocator);
            return 0;
        }

        pub fn augmented_length(self_address: Pointer, node_allocator: *ASTAllocator(PayloadType)) u8 {
            return Self.augmented_back_length(self_address, node_allocator) +
                1 +
                Self.augmented_front_length(self_address, node_allocator);
        }

        pub fn augmented_front_length(self_address: Pointer, node_allocator: *ASTAllocator(PayloadType)) u8 {
            const self = node_allocator.at(self_address);
            if (self.next != invalid_pointer) return 1 + Self.augmented_front_length(self.next, node_allocator);
            return 0;
        }

        pub fn augmented_text(self_address: Pointer, context: *Context) ![]const u8 {
            const self = context.node_allocator.at(self_address);
            if (self.first_child == invalid_pointer) {
                return context.get_text_slice(self.text_start, self.text_length);
            }

            var combined_text = try std.ArrayList(u8).initCapacity(context.arena_allocator, 256 * 256);
            var current_child = self.first_child;
            while (current_child != invalid_pointer) {
                try combined_text.appendSlice(context.arena_allocator, try Self.augmented_text(current_child, context));
                current_child = context.node_allocator.at(current_child).next;
            }
            return combined_text.items;
        }

        pub fn augmented_first(self_address: Pointer, node_allocator: *ASTAllocator(PayloadType)) Pointer {
            if (self_address != invalid_pointer) {
                const self = node_allocator.at(self_address);
                if (self.prior != invalid_pointer) {
                    return Self.augmented_first(self.prior, node_allocator);
                }
            }
            return self_address;
        }

        pub fn iterate_augmented(self_address: Pointer, context: *Context) Iterator(@TypeOf(context)) {
            return .{
                .context = context,
                .current = Self.augmented_first(self_address, context.node_allocator),
            };
        }
    };
}

// Mock types for tests
const TestASTNode = ASTNode(void);

const MockNodeAllocator = struct {
    nodes: []TestASTNode,

    pub fn at(self: MockNodeAllocator, address: u16) *TestASTNode {
        return &self.nodes[address];
    }
};

const MockContext = struct {
    arena_allocator: std.mem.Allocator,
    node_allocator: MockNodeAllocator,
    text: []const u8,

    pub fn get_text_slice(self: *MockContext, start: usize, length: usize) ![]const u8 {
        return self.text[start..][0..length];
    }
};

test "zero length augmented node" {
    var nodes = [_]TestASTNode{
        .{
            .text_start = 0,
            .text_length = 1,
            .payload = {},
        },
    };
    var mock_context = MockContext{
        .arena_allocator = std.testing.allocator,
        .node_allocator = .{ .nodes = &nodes },
        .text = "-",
    };

    try std.testing.expectEqual(@as(usize, 0), TestASTNode.augmented_back_length(0, &mock_context));
    try std.testing.expectEqual(@as(usize, 1), TestASTNode.augmented_length(0, &mock_context));
    try std.testing.expectEqual(@as(usize, 0), TestASTNode.augmented_front_length(0, &mock_context));
}

test "augmented length" {
    var nodes: [20]TestASTNode = undefined;
    @memset(&nodes, std.mem.zeroes(TestASTNode));

    var mock_context = MockContext{
        .arena_allocator = std.testing.allocator,
        .node_allocator = .{ .nodes = &nodes },
        .text = "-",
    };

    for (&nodes, 0..) |*node, index| {
        if (index > 0) {
            nodes[index - 1].next = @intCast(index);
        }
        node.* = .{
            .text_start = 0,
            .text_length = 1,
            .prior = if (index > 0) @intCast(index - 1) else TestASTNode.invalid_pointer,
            .payload = {},
        };
    }

    for (nodes, 0..) |_, index| {
        try std.testing.expectEqual(@as(usize, index), TestASTNode.augmented_back_length(@intCast(index), &mock_context));
        try std.testing.expectEqual(@as(usize, 20), TestASTNode.augmented_length(@intCast(index), &mock_context));
        try std.testing.expectEqual(@as(usize, 19 - index), TestASTNode.augmented_front_length(@intCast(index), &mock_context));
    }
}

test "augmented iterate" {
    var nodes: [20]TestASTNode = undefined;
    @memset(&nodes, std.mem.zeroes(TestASTNode));

    var mock_context = MockContext{
        .arena_allocator = std.testing.allocator,
        .node_allocator = .{ .nodes = &nodes },
        .text = "-",
    };

    for (&nodes, 0..) |*node, index| {
        if (index > 0) {
            nodes[index - 1].next = @intCast(index);
        }
        node.* = .{
            .text_start = 0,
            .text_length = 1,
            .prior = if (index > 0) @intCast(index - 1) else TestASTNode.invalid_pointer,
            .payload = {},
        };
    }

    const initial_node: u16 = 10;
    var iterator = TestASTNode.iterate_augmented(initial_node, &mock_context);
    var counter: usize = 0;
    while (iterator.next()) |current| {
        try std.testing.expectEqual(current, &nodes[counter]);
        counter += 1;
    }
}

const TestFixture = struct {
    arena: std.heap.ArenaAllocator,
    nodes: []TestASTNode,
    root: u16,
    free_nodes: []u16,

    pub fn allocator(self: *TestFixture) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn getContext(self: *TestFixture) MockContext {
        return MockContext{
            .arena_allocator = self.allocator(),
            .node_allocator = .{ .nodes = self.nodes },
            .text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        };
    }

    pub fn init() !TestFixture {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        const alloc = arena.allocator();

        const nodes = try alloc.alloc(TestASTNode, 30);
        for (nodes) |*node| {
            node.* = .{
                .text_start = 0,
                .text_length = 0,
                .payload = {},
            };
        }

        var init_context = MockContext{
            .arena_allocator = alloc,
            .node_allocator = .{ .nodes = nodes },
            .text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        };

        const root: u16 = 0;
        nodes[root] = .{
            .text_start = 0,
            .text_length = 1,
            .payload = {},
        };

        // Append root's children (1..4)
        for (1..5) |index| {
            const child_addr: u16 = @intCast(index);
            nodes[child_addr] = .{
                .text_start = 0,
                .text_length = 1,
                .payload = {},
            };
            try TestASTNode.append_children(root, &init_context, child_addr);
        }

        // For each of root's children, append 3 children
        var counter: u16 = 5;
        for (1..5) |parent_index| {
            const parent_addr: u16 = @intCast(parent_index);
            for (0..3) |_| {
                const child_addr = counter;
                counter += 1;
                nodes[child_addr] = .{
                    .text_start = 0,
                    .text_length = 1,
                    .payload = {},
                };
                try TestASTNode.append_children(parent_addr, &init_context, child_addr);
            }
        }

        // Remaining nodes are free nodes (17..29)
        const free_nodes = try alloc.alloc(u16, 30 - counter);
        for (free_nodes, 0..) |*fn_addr, idx| {
            fn_addr.* = counter + @as(u16, @intCast(idx));
            nodes[fn_addr.*] = .{
                .text_start = 0,
                .text_length = 1,
                .payload = {},
            };
        }

        return TestFixture{
            .arena = arena,
            .nodes = nodes,
            .root = root,
            .free_nodes = free_nodes,
        };
    }

    pub fn deinit(self: *TestFixture) void {
        self.arena.deinit();
    }
};

fn run_with_context(test_fn: *const fn (*TestFixture) anyerror!void) !void {
    var fixture = try TestFixture.init();
    defer fixture.deinit();
    try test_fn(&fixture);
}

fn test_remove(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;
    const root = fixture.root;

    // Root initially has 4 children (1, 2, 3, 4)
    var count: usize = 0;
    var curr = fixture.nodes[root].first_child;
    while (curr != TestASTNode.invalid_pointer) {
        count += 1;
        curr = fixture.nodes[curr].next;
    }
    try std.testing.expectEqual(@as(usize, 4), count);

    // Remove 2 children starting at index 1 (child2 = 2, child3 = 3)
    const removed = try TestASTNode.remove(2, ctx, 2);

    // Parent (root) now has 2 children: 1, 4
    count = 0;
    curr = fixture.nodes[root].first_child;
    while (curr != TestASTNode.invalid_pointer) {
        count += 1;
        curr = fixture.nodes[curr].next;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(as_u16(1), fixture.nodes[root].first_child);
    try std.testing.expectEqual(as_u16(4), fixture.nodes[root].last_child);

    // Sibling chain updated correctly
    try std.testing.expectEqual(as_u16(4), fixture.nodes[1].next);
    try std.testing.expectEqual(as_u16(1), fixture.nodes[4].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[1].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[4].next);

    // Removed nodes are detached orphans
    try std.testing.expectEqual(@as(usize, 2), removed.len);
    try std.testing.expectEqual(as_u16(2), removed[0]);
    try std.testing.expectEqual(as_u16(3), removed[1]);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[2].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[2].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[3].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[3].next);
}

fn as_u16(val: anytype) u16 {
    return @intCast(val);
}

test "remove" {
    try run_with_context(test_remove);
}

fn test_insert_before(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;
    const root = fixture.root;

    // Use two free nodes as fresh orphans, linked into a chain
    const new_a = fixture.free_nodes[0];
    const new_b = fixture.free_nodes[1];
    fixture.nodes[new_a].next = new_b;
    fixture.nodes[new_b].prior = new_a;

    // Insert the chain before root's children[2] (child3 = 3)
    try TestASTNode.insert_before(3, ctx, new_a);

    // Root should now have 6 children: 1, 2, new_a, new_b, 3, 4
    var count: usize = 0;
    var curr = fixture.nodes[root].first_child;
    var children_list: [6]u16 = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(as_u16(1), children_list[0]);
    try std.testing.expectEqual(as_u16(2), children_list[1]);
    try std.testing.expectEqual(new_a, children_list[2]);
    try std.testing.expectEqual(new_b, children_list[3]);
    try std.testing.expectEqual(as_u16(3), children_list[4]);
    try std.testing.expectEqual(as_u16(4), children_list[5]);

    // Parent pointers set
    try std.testing.expectEqual(root, fixture.nodes[new_a].parent);
    try std.testing.expectEqual(root, fixture.nodes[new_b].parent);

    // Sibling chain is contiguous
    try std.testing.expectEqual(new_a, fixture.nodes[2].next);
    try std.testing.expectEqual(as_u16(2), fixture.nodes[new_a].prior);
    try std.testing.expectEqual(new_b, fixture.nodes[new_a].next);
    try std.testing.expectEqual(as_u16(3), fixture.nodes[new_b].next);
    try std.testing.expectEqual(new_b, fixture.nodes[3].prior);
}

test "insert_before" {
    try run_with_context(test_insert_before);
}

fn test_insert_after(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;
    const root = fixture.root;

    const new_a = fixture.free_nodes[0];
    const new_b = fixture.free_nodes[1];
    fixture.nodes[new_a].next = new_b;
    fixture.nodes[new_b].prior = new_a;

    // Insert chain after root's children[1] (child2 = 2)
    try TestASTNode.insert_after(2, ctx, new_a);

    // Root: 1, 2, new_a, new_b, 3, 4
    var count: usize = 0;
    var curr = fixture.nodes[root].first_child;
    var children_list: [6]u16 = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(as_u16(2), children_list[1]);
    try std.testing.expectEqual(new_a, children_list[2]);
    try std.testing.expectEqual(new_b, children_list[3]);
    try std.testing.expectEqual(as_u16(3), children_list[4]);

    try std.testing.expectEqual(root, fixture.nodes[new_a].parent);
    try std.testing.expectEqual(root, fixture.nodes[new_b].parent);

    try std.testing.expectEqual(new_a, fixture.nodes[2].next);
    try std.testing.expectEqual(as_u16(2), fixture.nodes[new_a].prior);
    try std.testing.expectEqual(new_b, fixture.nodes[new_a].next);
    try std.testing.expectEqual(as_u16(3), fixture.nodes[new_b].next);
}

test "insert_after" {
    try run_with_context(test_insert_after);
}

fn test_insert_children(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;
    const parent = as_u16(1); // child1 (has 3 children: 5, 6, 7)

    const new_node = fixture.free_nodes[0];

    // Insert at the beginning (index 0)
    try TestASTNode.insert_children(parent, ctx, 0, new_node);

    var count: usize = 0;
    var curr = fixture.nodes[parent].first_child;
    var children_list: [5]u16 = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectEqual(new_node, children_list[0]);
    try std.testing.expectEqual(parent, fixture.nodes[new_node].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[new_node].prior);
    try std.testing.expectEqual(as_u16(5), fixture.nodes[new_node].next);
    try std.testing.expectEqual(new_node, fixture.nodes[5].prior);

    // Insert at the end (index 4)
    const new_node2 = fixture.free_nodes[1];
    try TestASTNode.insert_children(parent, ctx, 4, new_node2);

    count = 0;
    curr = fixture.nodes[parent].first_child;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expectEqual(new_node2, children_list[4]);
    try std.testing.expectEqual(parent, fixture.nodes[new_node2].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[new_node2].next);
    try std.testing.expectEqual(as_u16(7), fixture.nodes[new_node2].prior);
}

test "insert_children" {
    try run_with_context(test_insert_children);
}

fn test_augmented_text(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;

    // Leaf nodes return their own text
    fixture.nodes[5].text_start = 0;
    fixture.nodes[5].text_length = 1;
    const leaf_text = try TestASTNode.augmented_text(5, ctx);
    try std.testing.expectEqualStrings("A", leaf_text);

    // Set distinguishable leaf texts on child1's children (5, 6, 7)
    fixture.nodes[5].text_start = 0;
    fixture.nodes[5].text_length = 1; // "A"
    fixture.nodes[6].text_start = 1;
    fixture.nodes[6].text_length = 1; // "B"
    fixture.nodes[7].text_start = 2;
    fixture.nodes[7].text_length = 1; // "C"

    const combined = try TestASTNode.augmented_text(1, ctx);
    try std.testing.expectEqualStrings("ABC", combined);
}

test "augmented_text" {
    try run_with_context(test_augmented_text);
}

fn test_remove_count_exceeds(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;
    // child 4 (address 4) is the last child of root; asking for 2 beyond it should error
    const result = TestASTNode.remove(4, ctx, 2);
    try std.testing.expectError(error.CountExceedsRemainingSiblings, result);
}

test "remove count exceeds remaining siblings" {
    try run_with_context(test_remove_count_exceeds);
}

fn test_immediate_insert_child(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;

    const parent = fixture.free_nodes[0];
    const child1 = fixture.free_nodes[1];
    const child2 = fixture.free_nodes[2];

    // Insert first child
    TestASTNode.immediate_insert_child(parent, ctx, child1);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child1, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child1].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[child1].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[child1].next);

    // Insert second child
    TestASTNode.immediate_insert_child(parent, ctx, child2);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child2, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child2].parent);
    try std.testing.expectEqual(child1, fixture.nodes[child2].prior);
    try std.testing.expectEqual(child2, fixture.nodes[child1].next);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[child2].next);
}

test "immediate_insert_child" {
    try run_with_context(test_immediate_insert_child);
}
