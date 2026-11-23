--[[
	Analytics: thin, crash-proof wrapper around Roblox AnalyticsService.
	Shows up in Creator Dashboard -> Analytics:
	  * Onboarding funnel: where new players drop out of the tutorial
	  * Economy: what coins / gems are earned and spent on
	  * Custom events: steals, star eggs, trades ...
	Every call is pcall'd so analytics can never break gameplay.
]]
local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

function Analytics:Funnel(player: Player, step: number, stepName: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

-- flow: "Source" (earned) | "Sink" (spent)
function Analytics:Economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	sku: string?
)
	if amount <= 0 then
		return
	end
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if flow == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source,
			currency,
			math.floor(amount),
			math.floor(balance),
			transaction,
			sku
		)
	end)
end

function Analytics:Custom(player: Player, eventName: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1)
	end)
end

return Analytics
