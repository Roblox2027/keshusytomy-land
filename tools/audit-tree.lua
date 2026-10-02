-- audit-tree.lua
-- Inventario completo del DataModel REAL de Studio.
local lines = {}
local function w(s) table.insert(lines, s) end

local function countChildren(inst)
	local n = 0
	for _ in inst:GetChildren() do n = n + 1 end
	return n
end

local function walk(inst, depth, path, out, maxDepth)
	local p = path == "" and inst.Name or (path .. "." .. inst.Name)
	table.insert(out, {
		path = p,
		class = inst.ClassName,
		depth = depth,
		children = countChildren(inst),
	})
	if depth >= maxDepth then return end
	for _, c in inst:GetChildren() do
		walk(c, depth + 1, p, out, maxDepth)
	end
end

local out = {}
for _, svc in ipairs({
	game:GetService("ServerScriptService"),
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("Workspace"),
	game:GetService("ServerStorage"),
}) do
	walk(svc, 0, "", out, 3)
end

w("TOTAL_INSTANCES=" .. #out)

-- Desglose por clase
local byClass = {}
for _, e in ipairs(out) do
	byClass[e.class] = (byClass[e.class] or 0) + 1
end
local classes = {}
for c in pairs(byClass) do table.insert(classes, c) end
table.sort(classes)
w("BY_CLASS:")
for _, c in ipairs(classes) do
	w(string.format("  %s = %d", c, byClass[c]))
end

w("TREE:")
for _, e in ipairs(out) do
	if e.depth >= 1 then
		w(string.format("%s%s [%s] (%d)", string.rep("  ", e.depth), e.path, e.class, e.children))
	end
end

return table.concat(lines, "\n")
