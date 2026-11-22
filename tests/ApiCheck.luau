--[[
	Static Roblox API check - run with Lune:
	    lune run tests/ApiCheck.luau

	Uses Roblox's reflection database (bundled with Lune) to verify that
	  * every property set on an instance created in the code exists on that class
	  * every Enum.X.Y used exists
	  * every game:GetService("X") names a real service
	It is a heuristic scanner (pattern based), not a full type checker.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local db = roblox.getReflectionDatabase()
local failures = 0

local function report(file: string, line: number, message: string)
	failures += 1
	print(string.format("❌ %s:%d  %s", file, line, message))
end

local propertyCache = {}
local function hasProperty(className: string, prop: string): boolean?
	local key = className .. "." .. prop
	if propertyCache[key] ~= nil then
		return propertyCache[key]
	end
	local class = db:GetClass(className)
	if not class then
		return nil
	end
	local found = false
	while class do
		if class.Properties[prop] then
			found = true
			break
		end
		class = class.Superclass and db:GetClass(class.Superclass)
	end
	propertyCache[key] = found
	return found
end

local function listFiles(dir: string, out)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			listFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	return out
end

-- returns the top-level keys of a table literal starting at `start` (index of "{")
local function tableKeys(source: string, start: number)
	local depth = 0
	local keys = {}
	local i = start
	local len = #source
	local inString = nil
	while i <= len do
		local c = string.sub(source, i, i)
		if inString then
			if c == "\\" then
				i += 1
			elseif c == inString then
				inString = nil
			end
		elseif c == '"' or c == "'" then
			inString = c
		elseif c == "{" or c == "(" or c == "[" then
			depth += 1
		elseif c == "}" or c == ")" or c == "]" then
			depth -= 1
			if depth == 0 then
				break
			end
		elseif depth == 1 then
			local key = string.match(source, "^([%a_][%w_]*)%s*=[^=]", i)
			local prev = string.sub(source, i - 1, i - 1)
			if key and not string.match(prev, "[%w_%.]") then
				table.insert(keys, { Key = key, Pos = i })
				i += #key - 1
			end
		end
		i += 1
	end
	return keys
end

local function lineAt(source: string, pos: number): number
	local _, count = string.gsub(string.sub(source, 1, pos), "\n", "")
	return count + 1
end

-- callbacks are not listed as properties in the reflection database
local IGNORE = { Parent = true, OnServerInvoke = true, OnClientInvoke = true, OnInvoke = true }
local CUSTOM_KEYS = { MaxTextSize = true, Outline = true } -- Lib.Text extras

local function checkProps(file, source, className, keys, extraIgnore)
	for _, entry in keys do
		if not IGNORE[entry.Key] and not (extraIgnore and extraIgnore[entry.Key]) then
			local ok = hasProperty(className, entry.Key)
			if ok == nil then
				report(file, lineAt(source, entry.Pos), "unknown class " .. className)
				return
			elseif not ok then
				report(file, lineAt(source, entry.Pos), string.format("%s has no property '%s'", className, entry.Key))
			end
		end
	end
end

for _, file in listFiles("src", {}) do
	local source = fs.readFile(file)

	-- New("Class", { ... }) / Lib.New("Class", { ... })
	for pos, className, brace in string.gmatch(source, '()New%("(%w+)",%s*()') do
		if string.sub(source, brace, brace) == "{" then
			checkProps(file, source, className, tableKeys(source, brace))
		end
	end
	-- Lib.Text({ ... }) -> TextLabel
	for brace in string.gmatch(source, "Lib%.Text%(()") do
		if string.sub(source, brace, brace) == "{" then
			checkProps(file, source, "TextLabel", tableKeys(source, brace), CUSTOM_KEYS)
		end
	end
	-- newPart({ ... }) (WorldService) and part({ ... }) (PetModel) -> Part
	for brace in string.gmatch(source, "[^%w_]newPart%(()") do
		if string.sub(source, brace, brace) == "{" then
			checkProps(file, source, "Part", tableKeys(source, brace))
		end
	end
	if string.find(file, "PetModel") then
		for brace in string.gmatch(source, "[^%w_]part%(()") do
			if string.sub(source, brace, brace) == "{" then
				checkProps(file, source, "Part", tableKeys(source, brace))
			end
		end
	end

	-- local x = Instance.new("Class") ... x.Prop = value
	local types = {}
	local lineNumber = 0
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		lineNumber += 1
		local var, className = string.match(line, 'local%s+([%w_]+)%s*=%s*Instance%.new%("(%w+)"%)')
		if not var then
			var, className = string.match(line, '^%s*([%w_]+)%s*=%s*Instance%.new%("(%w+)"%)')
		end
		if var then
			if db:GetClass(className) == nil then
				report(file, lineNumber, "unknown class " .. className)
			end
			types[var] = className
		else
			local reassigned = string.match(line, "local%s+([%w_]+)%s*=")
			if reassigned and types[reassigned] then
				types[reassigned] = nil
			end
		end
		local target, prop = string.match(line, "^%s*([%w_]+)%.([%w_]+)%s*=[^=]")
		local className2 = target and types[target]
		if className2 and not IGNORE[prop] and not hasProperty(className2, prop) then
			report(file, lineNumber, string.format("%s has no property '%s' (variable %s)", className2, prop, target))
		end
		-- Enum.X.Y
		for enumName, item in string.gmatch(line, "Enum%.([%w_]+)%.([%w_]+)") do
			local ok = pcall(function()
				local _ = (roblox.Enum :: any)[enumName][item]
			end)
			if not ok then
				report(file, lineNumber, "unknown enum Enum." .. enumName .. "." .. item)
			end
		end
		-- services
		for service in string.gmatch(line, 'GetService%("(%w+)"%)') do
			if db:GetClass(service) == nil then
				report(file, lineNumber, "unknown service " .. service)
			end
		end
	end
end

if failures > 0 then
	print(string.format("\n%d API problem(s) found", failures))
	process.exit(1)
end
print("✅ API check passed")
