const std = @import("std");
const OutStream = std.io.OutStream;
const Allocator = std.mem.Allocator;

const getAutoHashFn = std.hash_map.getAutoHashFn;
const getAutoEqlFn = std.hash_map.getAutoEqlFn;

const NodeColor = enum {
    Red,
    Black,

    pub fn swap(color: NodeColor) NodeColor {
        return switch (color) {
            .Red => .Black,
            .Black => .Red,
        };
    }

    pub fn toBool(color: NodeColor) bool {
        return color == .Red;
    }

    pub fn fromBool(value: bool) NodeColor {
        return if (value) .Red else .Black;
    }
};

pub fn RedBlackTree(comptime T: type, comptime comparator: fn (T, T) i32) type {
    return struct {
        allocator: *Allocator,
        len: u32,
        root: ?*Node,

        const Tree = @This();

        pub fn init(allocator: *Allocator) Tree {
            return Tree{
                .allocator = allocator,
                .len = 0,
                .root = null,
            };
        }

        fn deinitNode(self: *Tree, node: ?*Node) void {
            if (node) |node_value| {
                self.deinitNode(node_value.children[0]);
                self.deinitNode(node_value.children[1]);
                
                self.allocator.destroy(node);
            }
        }

        pub fn deinit(self: *Tree) void {
            self.deinitNode(self.root);
        }

        pub fn move (self: *Tree) Tree {
            const root = self.root;
            const len = self.len;
            
            self.root = null;
            self.len = 0;

            return Tree{
                .allocator = self.allocator,
                .len = self.len,
                .root = root,
            };
        }

        pub fn getDepth(self: *Tree) u32 {
            if (self.root) |node| {
                return node.getDepth();
            }

            return 0;
        }

        fn rotateLeft(self: *Tree, root: *Node) *Node {
            const save = root.children[1].?;

            root.children[1] = save.children[0];
            if (save.children[0]) |node| node.parent = root;
            save.children[0] = root;

            save.parent = root.parent;
            root.parent = save;

            root.color = .Red;
            save.color = .Black;

            return save;
        }

        fn rotateRightLeft(self: *Tree, root: *Node) *Node {
            root.children[1] = self.rotateRight(root.children[1].?);

            return self.rotateLeft(root);
        }

        fn rotateRight(self: *Tree, root: *Node) *Node {
            const save = root.children[0].?;

            root.children[0] = root.children[1];
            if (save.children[1]) |node| node.parent = root;
            save.children[1] = root;

            save.parent = root.parent;
            root.parent = save;

            root.color = .Red;
            save.color = .Black;

            return save;
        }

        fn rotateLeftRight(self: *Tree, root: *Node) *Node {
            root.children[0] = self.rotateLeft(root.children[0].?);

            return self.rotateRight(root);
        }

        fn insertRecursive(self: *Tree, root: ?*Node, value: T) @TypeOf(Node.create).ReturnType.ErrorSet!*Node {
            if (root) |root_node| {
                // When cmp > 0, root.value is greater than value
                // We do not allow repeated values in our tree (cmp == 0)
                const cmp = comparator(root_node.value, value);

                if (cmp > 0) {
                    const left = try self.insertRecursive(root_node.children[0], value);
                    left.parent = root_node;
                    root_node.children[0] = left;

                    const left_color = Node.getColor(root_node.children[0]);

                    if (left_color == .Red) {
                        const right_color = Node.getColor(root_node.children[1]);

                        if (right_color == .Red) {
                            root_node.color = .Red;
                            // When a node's color is Red, that node is always NOT NULL
                            // So if both left and right are Red, they are both NOT NULL
                            root_node.children[0].?.color = .Black;
                            root_node.children[1].?.color = .Black;
                        } else {
                            // When a node's color is Red, that node is always NOT NULL
                            const left_node = root_node.children[0].?;

                            if (Node.getColor(left_node.children[0]) == .Red) {
                                return self.rotateRight(root_node);
                            } else if (Node.getColor(left_node.children[1]) == .Red) {
                                return self.rotateLeftRight(root_node);
                            }
                        }
                    }
                } else if (cmp < 0) {
                    const right = try self.insertRecursive(root_node.children[1], value);
                    right.parent = root_node;
                    root_node.children[1] = right;

                    const right_color = Node.getColor(root_node.children[1]);

                    if (right_color == .Red) {
                        const left_color = Node.getColor(root_node.children[0]);

                        if (left_color == .Red) {
                            root_node.color = .Red;
                            // When a node's color is Red, that node is always NOT NULL
                            // So if both left and right are Red, they are both NOT NULL
                            root_node.children[0].?.color = .Black;
                            root_node.children[1].?.color = .Black;
                        } else {
                            // When a node's color is Red, that node is always NOT NULL
                            const right_node = root_node.children[1].?;

                            if (Node.getColor(right_node.children[1]) == .Red) {
                                return self.rotateLeft(root_node);
                            } else if (Node.getColor(right_node.children[0]) == .Red) {
                                return self.rotateRightLeft(root_node);
                            }
                        }
                    }
                }

                return root_node;
            } else {
                return Node.create(self.allocator, null, value);
            }
        }

        pub fn insert(self: *Tree, value: T) !void {
            self.len += 1;

            const root = try self.insertRecursive(self.root, value);
            if (root.children[0]) |node| node.parent = root;
            if (root.children[1]) |node| node.parent = root;

            root.color = .Black;

            self.root = root;
        }

        fn rotate(self: *Tree, node: *Node, dir: usize) *Node {
            if (dir == 0) {
                return self.rotateLeft(node);
            } else {
                return self.rotateRight(node);
            }
        }

        fn rotateDouble(self: *Tree, node: *Node, dir: usize) *Node {
            if (dir == 0) {
                return self.rotateRightLeft(node);
            } else {
                return self.rotateLeftRight(node);
            }
        }

        pub fn delete(self: *Tree, value: T) void {
            if (self.root) |root| {
                // TODO: Does this need to be allocated on the heap? And if so,
                // when should it be freed
                var head = Node.init(null, undefined);
                var q: *Node = &head;
                var p: *Node = undefined;
                var g: *Node = undefined;
                var f: ?*Node = null;

                var dir: usize = 1;
                var ord: i32 = 0;

                // Set up helpers
                q.children[1] = self.root;
                while (q.children[dir]) |child| {
                    var last = dir;

                    g = p;
                    p = q;
                    q = child;
                    ord = comparator(q.value, value);
                    dir = if (ord < 0) 1 else 0;

                    if (ord == 0) {
                        f = q;
                        self.len -= 1;
                    }

                    //...
                    if (Node.getColor(q) == .Black and Node.getColor(q.children[dir]) == .Black) {
                        if (Node.getColor(q.children[1 - dir]) == .Red) {
                            p.children[last] = self.rotate(q, dir);
                            p = p.children[last].?;
                        } else if (Node.getColor(q.children[1 - dir]) == .Black) {
                            const s = p.children[1 - last];

                            if (s) |sv| {
                                const both_black = Node.getColor(sv.children[1 - last]) == .Black and Node.getColor(sv.children[last]) == .Black;
                                if (both_black) {
                                    p.color = .Black;
                                    sv.color = .Red;
                                    q.color = .Red;
                                } else {
                                    var dir2: usize = if (g.children[1] == p) 1 else 0;

                                    if (Node.getColor(sv.children[last]) == .Red) {
                                        g.children[dir2] = self.rotateDouble(p, last); // jsw_double(p, last);
                                    } else if (Node.getColor(sv.children[1 - last]) == .Red) {
                                        g.children[dir2] = self.rotate(p, last);
                                    }

                                    // Ensure correct coloring
                                    q.color = .Red;
                                    g.children[dir2].?.color = .Red;
                                    g.children[dir2].?.children[0].?.color = .Black;
                                    g.children[dir2].?.children[1].?.color = .Black;
                                }
                            }
                        }
                    }
                }

                if (f != null) {
                    f.?.value = q.value;

                    // This tells us whether q is the left or right child of p
                    var q_index: usize = if (p.children[1] == q) 1 else 0;
                    // This get's us a non-null child index of q
                    var q_child_index: usize = if (q.children[0] == null) 1 else 0;

                    p.children[q_index] = q.children[q_child_index];

                    self.allocator.destroy(q);
                }

                // Update root and make it black
                self.root = head.children[1];

                if (self.root) |new_root| {
                    new_root.color = .Black;
                }
            }
        }

        pub fn firstNode(self: *Tree) ?*Node {
            if (self.root) |root| {
                var cursor = root;

                while (cursor.children[0]) |node| {
                    cursor = cursor.children[0];
                }

                return cursor;
            }

            return null;
        }

        pub fn lastNode(self: *Tree) ?*Node {
            if (self.root) |root| {
                var cursor = root;

                while (cursor.children[1]) |node| {
                    cursor = cursor.children[1];
                }

                return cursor;
            }

            return null;
        }

        pub fn closestSmaller(self: *Tree, value: T) ?*Node {
            var cursor: ?*Node = self.root;
            var closest: ?*Node = null;

            while (cursor) |c_node| {
                const ord = comparator(c_node.value, value);

                if (ord == 0) {
                    return c_node;
                }

                if (ord < 0) {
                    closest = c_node;
                    cursor = c_node.children[1];
                } else {
                    cursor = c_node.children[0];
                }
            }

            return closest;
        }

        pub fn closestLarger(self: *Tree, value: T) ?*Node {
            var cursor: ?*Node = self.root;
            var closest: ?*Node = null;

            while (cursor) |c_node| {
                const ord = comparator(c_node.value, value);

                if (ord == 0) return c_node;

                if (ord < 0) {
                    cursor = c_node.children[1];
                } else {
                    closest = c_node;
                    cursor = c_node.children[0];
                }
            }

            return closest;
        }

        pub fn iterPreStruct(self: *const Tree, reverse: bool) PreOrderStructureIterator {
            return PreOrderStructureIterator.init(self.root, reverse);
        }

        pub fn iterPre(self: *const Tree, reverse: bool) PreOrderIterator {
            return PreOrderIterator.init(self.root, reverse);
        }

        pub fn print(self: *const Tree, out: var, value_print: fn (var, T) anyerror!void) !void {
            var iter = self.iterPreStruct(false);

            var ident: i32 = 0;
            var i: i32 = 0;

            while (iter.next()) |step| {
                switch (step) {
                    .Value => |v| {
                        i = 0;
                        while (i < ident) : (i += 1) _ = try out.write("  ");

                        _ = try out.write("NODE(");

                        // TODO: Remove printing color
                        if (iter.cursor.?.color == .Red) {
                            _ = try out.write("R ");
                        } else {
                            _ = try out.write("B ");
                        }
                        try value_print(out, v);
                    },
                    .ChildLeft => |has| {
                        _ = try out.write("; ");
                        if (!has) {
                            _ = try out.write("NULL");
                        } else {
                            _ = try out.write("\n");
                        }
                        ident += 1;
                    },
                    .ChildRight => |has| {
                        _ = try out.write(", ");
                        if (!has) {
                            _ = try out.write("NULL");
                        } else {
                            _ = try out.write("\n");
                        }
                        ident += 1;
                    },
                    .ParentLeft => {
                        ident -= 1;
                    },
                    .ParentRight => {
                        ident -= 1;
                        _ = try out.write(")");
                    },
                }
            }
            _ = try out.write("\n");
        }

        pub const Node = struct {
            children: [2]?*Node,
            color: NodeColor,
            value: T,
            parent: ?*Node,

            fn getColor(node: ?*Node) NodeColor {
                if (node) |ref| {
                    return ref.color;
                }

                return .Black;
            }

            pub fn create(allocator: *Allocator, parent: ?*Node, value: T) !*Node {
                var ptr = try allocator.create(Node);
                ptr.* = Node.init(parent, value);
                return ptr;
            }

            pub fn destroyRecursive(self: *Node, allocator: *Allocator) void {
                if (self.children[0]) |child| {
                    child.destroyRecursive(allocator);
                }

                if (self.children[1]) |child| {
                    child.destroyRecursive(allocator);
                }

                self.destroy(allocator);
            }

            pub fn destroy(self: *Node, allocator: *Allocator) void {
                allocator.destroy(self);
            }

            pub fn init(parent: ?*Node, value: T) Node {
                return Node{
                    .parent = parent,
                    .value = value,
                    .color = .Red,
                    .children = [2]?*Node{ null, null },
                };
            }

            pub fn getUncle(self: *Node) ?*Node {
                if (self.parent) |parent| {
                    return parent.getSibling();
                }

                return null;
            }

            pub fn getSibling(self: *Node) ?*Node {
                if (self.parent) |parent| {
                    if (self.parent.children[0] == self) {
                        return self.parent.children[1];
                    } else {
                        return self.parent.children[0];
                    }
                }

                return null;
            }

            pub fn getGrandparent(self: *Node) ?*Node {
                if (self.parent) |parent| {
                    return parent.parent;
                }

                return null;
            }

            pub fn getDepth(self: *Node) i32 {
                var sub_depth = 0;

                if (self.children[0]) |child| {
                    sub_depth = child.getDepth();
                }

                if (self.children[1]) |child| {
                    sub_depth = std.math.max(sub_depth, child.getDepth());
                }

                return 1 + sub_depth;
            }
        };

        pub const PreOrderIterator = struct {
            structure_iterator: PreOrderStructureIterator,

            pub fn init(cursor: ?*Node, reverse: bool) PreOrderIterator {
                const iter = PreOrderStructureIterator.init(cursor, reverse);

                return PreOrderIterator{ .structure_iterator = iter };
            }

            pub fn next(self: *PreOrderIterator) ?T {
                while (self.structure_iterator.next()) |next_atom| {
                    switch (next_atom) {
                        .Value => |v| return v,
                        else => {},
                    }
                }

                return null;
            }
        };

        pub const PreOrderStructureIterator = struct {
            pub const Atom = union(enum) {
                Value: T, ChildLeft: bool, ChildRight: bool, ParentLeft: void, ParentRight: void
            };

            cursor: ?*Node,
            last_action: Atom,
            reverse: bool,

            pub fn init(cursor: ?*Node, reverse: bool) PreOrderStructureIterator {
                return PreOrderStructureIterator{
                    .cursor = cursor,
                    .reverse = reverse,
                    .last_action = if (reverse) Atom{ .ChildLeft = true } else Atom{ .ChildRight = true },
                };
            }

            pub fn next(self: *PreOrderStructureIterator) ?Atom {
                if (self.cursor) |*cursor_ptr| {
                    const cursor = cursor_ptr.*;

                    switch (self.last_action) {
                        Atom.Value => {
                            if (!self.reverse) {
                                // Left to Right
                                if (cursor.children[0]) |left_child| {
                                    self.last_action = Atom{ .ChildLeft = true };

                                    cursor_ptr.* = left_child;
                                } else {
                                    self.last_action = Atom{ .ChildLeft = false };
                                }
                            } else {
                                // Right to Left
                                if (cursor.children[1]) |right_child| {
                                    self.last_action = Atom{ .ChildRight = true };

                                    cursor_ptr.* = right_child;
                                } else {
                                    self.last_action = Atom{ .ChildRight = false };
                                }
                            }
                        },
                        Atom.ChildLeft => |has_child| {
                            if (has_child) {
                                self.last_action = Atom{ .Value = cursor.value };
                            } else {
                                // From here, .ParentLeft will go to the right child
                                self.last_action = Atom{ .ParentLeft = {} };
                            }
                        },
                        Atom.ChildRight => |has_child| {
                            if (has_child) {
                                self.last_action = Atom{ .Value = cursor.value };
                            } else {
                                self.last_action = Atom{ .ParentRight = {} };
                            }
                        },
                        Atom.ParentLeft => {
                            if (!self.reverse) {
                                // Left to Right
                                if (cursor.children[1]) |right_child| {
                                    self.last_action = Atom{ .ChildRight = true };

                                    cursor_ptr.* = right_child;
                                } else {
                                    self.last_action = Atom{ .ChildRight = false };
                                }
                            } else {
                                // Right to Left
                                if (cursor.parent) |parent| {
                                    const is_left = parent.children[0] == cursor;

                                    self.last_action = if (is_left)
                                        Atom{ .ParentLeft = {} }
                                    else
                                        Atom{ .ParentRight = {} };

                                    cursor_ptr.* = parent;
                                } else {
                                    self.cursor = null;

                                    return null;
                                }
                            }
                        },
                        Atom.ParentRight => {
                            if (!self.reverse) {
                                // Left to Right
                                if (cursor.parent) |parent| {
                                    const is_left = parent.children[0] == cursor;

                                    self.last_action = if (is_left)
                                        Atom{ .ParentLeft = {} }
                                    else
                                        Atom{ .ParentRight = {} };

                                    cursor_ptr.* = parent;
                                } else {
                                    self.cursor = null;

                                    return null;
                                }
                            } else {
                                // Right to Left
                                if (cursor.children[0]) |left_child| {
                                    self.last_action = Atom{ .ChildLeft = true };

                                    cursor_ptr.* = left_child;
                                } else {
                                    self.last_action = Atom{ .ChildLeft = false };
                                }
                            }
                        },
                    }

                    return self.last_action;
                } else {
                    return null;
                }
            }
        };
    };
}
