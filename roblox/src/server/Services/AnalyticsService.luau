--!nonstrict
-- AnalyticsService: thin, crash-proof wrappers over Roblox's AnalyticsService so every system
-- reports economy, progression, funnel and custom events the same way.
-- Dashboards: Creator Hub > Analytics > Economy / Funnels / Custom.

local RobloxAnalytics = game:GetService("AnalyticsService")

local AnalyticsService = {}

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Analytics] " .. tostring(err))
	end
end

-- flow: "Source" | "Sink"; transactionType: "IAP" | "Shop" | "Gameplay" | "ContextualPurchase" |
-- "TimedReward" | "Onboarding" | any custom string.
function AnalyticsService.economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	customFields: { [string]: string }?
)
	if amount <= 0 then
		return
	end
	safe(function()
		RobloxAnalytics:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType[flow],
			currency,
			math.floor(amount),
			math.max(0, math.floor(endingBalance)),
			transactionType,
			itemSku,
			customFields
		)
	end)
end

-- status: "Start" | "Complete" | "Fail"
function AnalyticsService.progression(
	player: Player,
	pathName: string,
	status: string,
	level: number,
	levelName: string?,
	customFields: { [string]: string }?
)
	safe(function()
		RobloxAnalytics:LogProgressionEvent(
			player,
			pathName,
			Enum.AnalyticsProgressionType[status],
			level,
			levelName,
			customFields
		)
	end)
end

function AnalyticsService.funnel(
	player: Player,
	funnelName: string,
	step: number,
	stepName: string?,
	sessionId: string?,
	customFields: { [string]: string }?
)
	safe(function()
		RobloxAnalytics:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName, customFields)
	end)
end

function AnalyticsService.custom(
	player: Player,
	eventName: string,
	value: number?,
	customFields: { [string]: string }?
)
	safe(function()
		RobloxAnalytics:LogCustomEvent(player, eventName, value, customFields)
	end)
end

-- Onboarding funnel step names, in order. Systems call AnalyticsService.onboarding(player, "FirstRaid").
AnalyticsService.OnboardingSteps = {
	"Spawned",
	"TutorialRaidStarted",
	"TutorialRaidExtracted",
	"FirstPiecePlaced",
	"FirstRealRaid",
	"FirstUpgrade",
	"FirstRevenge",
}

local stepIndex = {}
for index, name in AnalyticsService.OnboardingSteps do
	stepIndex[name] = index
end

function AnalyticsService.onboarding(player: Player, stepName: string)
	local index = stepIndex[stepName]
	if not index then
		warn("[Analytics] unknown onboarding step " .. stepName)
		return
	end
	AnalyticsService.funnel(player, "Onboarding", index, stepName)
end

function AnalyticsService.init() end

return AnalyticsService
