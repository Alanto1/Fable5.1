--!strict
-- AssetIds: uploaded mesh and image ids. Empty string = not uploaded yet; the game falls back to
-- the generated part models (meshes) or plain shapes (images). Fill from assets/export/manifest.json
-- after Studio's bulk import.

local AssetIds = {
	Meshes = {
		-- PieceId = "rbxassetid://0",
	} :: { [string]: string },

	Images = {
		Coin = "",
		Gem = "",
		Hammer = "",
		Raid = "",
		Build = "",
		Shop = "",
		League = "",
		Quests = "",
		Settings = "",
		Shield = "",
	} :: { [string]: string },

	Sounds = {
		Click = "rbxassetid://6895079853",
		Coin = "rbxassetid://5852470908",
		Hit = "rbxassetid://5801257793",
		Break = "rbxassetid://8595966963",
		Fling = "rbxassetid://5709777425",
		Win = "rbxassetid://6026984224",
		Lose = "rbxassetid://6026985153",
		Tick = "rbxassetid://9114221374",
		Place = "rbxassetid://9114217470",
		Alarm = "rbxassetid://5808200787",
	} :: { [string]: string },
}

function AssetIds.mesh(pieceId: string): string?
	local id = AssetIds.Meshes[pieceId]
	if id and id ~= "" then
		return id
	end
	return nil
end

return AssetIds
