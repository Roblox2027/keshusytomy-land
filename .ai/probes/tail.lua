local inst = game.StarterPlayer.StarterPlayerScripts.Controllers.UIController
local s = inst.Source

local r = ""
for i = 1, #s do
	local c = s:sub(i, i)
	if c ~= "\r" then
		r = r .. c
	end
end

-- Se devuelve el FUENTE ENTERO, sin truncar ni modificar. Es lo que hace
-- falta para comparar el texto real de Studio con el del disco: los hashes
-- por trozo Nicolas dan "difiere" sin decir QUE.
return r