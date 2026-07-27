--!strict
--[[
	Source-controlled image ids selected from the purchased
	"Simulator Icon Pack [100+ Icons]" asset 72859083217455.

	The pack has no semantic names, so this table records the intended role rather than its
	grid position in the catalog. Data only, zero requires.
]]

local Icons = {
	shop = "rbxassetid://92353483125582",
	--[[
		One money icon for every surface that talks about money: the coin bank, the buy
		buttons, the collect prompt, and the floating gain on the player.

		There were two before, a cash stack on buy buttons and a money bag on the coin bank.
		Two glyphs for one concept means a player has to learn that both mean coins, and the
		number they see on a buy button is denominated in the thing the bank counts. Same
		concept, same glyph.
	]]
	money = "rbxassetid://77216298800748",
	upgrade = "rbxassetid://99044944223614",
	error = "rbxassetid://105424546466549",
	success = "rbxassetid://113242667524418",
}

return Icons
