--[[
	Lang: tiny localization layer (English source text -> translations).

	* Every player-facing string is written in English and passed through
	  Lang.F(locale, text, ...) (server) or Lang.T(text, ...) (client).
	* Korean comes from LangKO. Missing entries fall back to English, so the
	  game never breaks - tests/LangCheck.luau reports anything untranslated.
	* String format arguments are translated too (zone names, rarities ...).
	* A player can force a language (data.Settings.Lang -> attribute "Lang"),
	  otherwise their Roblox language (LocaleId) decides.
]]
local KO = require(script.Parent.LangKO)

local Lang = {}
Lang.Locale = "en" -- client-side current locale

local function isKorean(locale): boolean
	return type(locale) == "string" and string.lower(string.sub(locale, 1, 2)) == "ko"
end
Lang.IsKorean = isKorean

function Lang.Translate(locale, text)
	if type(text) ~= "string" then
		return text
	end
	if isKorean(locale) then
		return KO[text] or text
	end
	return text
end

-- format + translate; string args are translated as well
function Lang.F(locale, text, ...)
	local fmt = Lang.Translate(locale, text)
	local count = select("#", ...)
	if count == 0 then
		return fmt
	end
	local args = table.pack(...)
	for i = 1, count do
		if type(args[i]) == "string" then
			args[i] = Lang.Translate(locale, args[i])
		elseif args[i] == nil then
			args[i] = ""
		end
	end
	local ok, result = pcall(string.format, fmt, table.unpack(args, 1, count))
	return if ok then result else fmt
end

-- client convenience (uses Lang.Locale)
function Lang.T(text, ...)
	return Lang.F(Lang.Locale, text, ...)
end

function Lang.SetLocale(locale)
	Lang.Locale = if isKorean(locale) then "ko" else "en"
end

-- the locale the server should use for a player
function Lang.LocaleOf(player): string
	local forced = player:GetAttribute("Lang")
	if forced == "ko" or forced == "en" then
		return forced
	end
	local ok, locale = pcall(function()
		return player.LocaleId
	end)
	return if ok and isKorean(locale) then "ko" else "en"
end

return Lang
