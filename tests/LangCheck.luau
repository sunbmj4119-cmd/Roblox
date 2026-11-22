--[[
	Localization runtime test - run with Lune:
	    lune run tests/LangCheck.luau

	Loads src/shared/Lang.luau + LangKO.luau outside Roblox and checks that
	  * every Korean entry formats without errors (same %s/%d as English)
	  * Lang.F translates the format AND string arguments
	  * unknown text falls back to English
	(Coverage of keys used in code is checked by tests/lang_keys.py.)
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local KO = luau.load(fs.readFile("src/shared/LangKO.luau"), { debugName = "LangKO" })()
local Lang = luau.load(fs.readFile("src/shared/Lang.luau"), {
	debugName = "Lang",
	environment = {
		script = { Parent = { LangKO = KO } },
		require = function(module)
			return module
		end,
	},
})()

local failures = 0
local function check(ok: boolean, message: string)
	if not ok then
		failures += 1
		print("❌ " .. message)
	end
end

-- 1) every entry formats with dummy arguments in both languages
local count = 0
for english, korean in KO do
	count += 1
	check(type(korean) == "string" and korean ~= "", "empty translation for " .. english)
	local args = {}
	for spec in string.gmatch(english, "%%[%-%+ #0]*%d*%.?%d*([sdifxXq%%])") do
		if spec == "s" then
			table.insert(args, "x")
		elseif spec ~= "%" then
			table.insert(args, 1)
		end
	end
	-- static text (no arguments) is never passed to string.format, so a lone
	-- "%" like "+10% coins" is fine there
	if #args > 0 or string.find(english, "%%%%") then
		local okEn = pcall(string.format, english, table.unpack(args))
		local okKo = pcall(string.format, korean, table.unpack(args))
		check(okEn, "English text does not format: " .. english)
		check(okKo, "Korean text does not format: " .. korean)
	end
end

-- 2) behaviour
local function eq(actual, expected, label)
	check(actual == expected, string.format("%s\n   got:      %s\n   expected: %s", label, tostring(actual), expected))
end

eq(Lang.F("ko", "Not enough %s! Need %s more.", "coins", "1.2K"), "코인 부족! 1.2K 더 필요해요.", "format + arg translation")
eq(Lang.F("en", "Not enough %s! Need %s more.", "coins", "1.2K"), "Not enough coins! Need 1.2K more.", "English untouched")
eq(Lang.F("ko", "Unlock %s first!", "Frost Cavern"), "먼저 서리 동굴 해금이 필요해요!", "zone name arg")
eq(Lang.F("ko", "Some brand new text"), "Some brand new text", "fallback to English")
eq(Lang.F("ko", "Tier %d", 7), "티어 7", "number arg")
eq(Lang.F("ko", "Tier %d", "oops"), "티어 %d", "bad args never error")
eq(Lang.F("ko", "%s", nil), "", "nil arg")
eq(Lang.Translate("ko-kr", "Pets"), "펫", "ko-kr locale")
eq(Lang.Translate("en-us", "Pets"), "Pets", "en-us locale")
Lang.SetLocale("ko-kr")
eq(Lang.T("⭐ LEVEL %s!", "12"), "⭐ 레벨 12!", "client T")
Lang.SetLocale("en-us")
eq(Lang.T("⭐ LEVEL %s!", "12"), "⭐ LEVEL 12!", "client T english")

-- forced language attribute
local fakePlayer = {
	attrs = { Lang = "ko" },
	LocaleId = "en-us",
	GetAttribute = function(self, name)
		return self.attrs[name]
	end,
}
eq(Lang.LocaleOf(fakePlayer), "ko", "forced Korean")
fakePlayer.attrs.Lang = nil
eq(Lang.LocaleOf(fakePlayer), "en", "auto from LocaleId")

if failures > 0 then
	print(string.format("%d localization problem(s)", failures))
	process.exit(1)
end
print(string.format("✅ Localization check passed (%d Korean entries)", count))
