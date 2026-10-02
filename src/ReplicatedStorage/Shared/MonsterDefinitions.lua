--!strict
--[[
	MonsterDefinitions
	DATOS de los monstruos. Ni una linea de logica aqui.

	POR QUE UN ARCHIVO APARTE
	--------------------------
	Un monstruo no es "un NPC con 30 de vida": es vida, velocidad, radio de
	agresion, alcance de ataque, dano, recompensa y un color. Si esos numeros
	viven dentro de `MonsterService`, cambiar la dificultad de un monstruo
	obliga a editar codigo, y no hay forma de comprobar que un monstruo nuevo
	no se solapa con otro.

	Aqui son una tabla. Anadir un monstruo es anadir una entrada, y
	`GetIds` permite que una prueba verifique que cada definicion tiene los
	campos obligatorios: un monstruo con `AttackRange = nil` no puede
	aparecer, y es mejor que lo diga el test y no el Output de un playtest.

	EL TOPE `MaxAlive` ES POR DEFINICION
	-----------------------------------
	No es decorativo: `MonsterService.Spawn` lo consulta. Sin el, un jugador
	que muere muchas veces con bomba de cadena deja el Workspace saturado de
	NPC, que es la forma mas rapida de matar un servidor.
]]

export type MonsterDefinition = {
	Id: string,
	Name: string,
	Health: number,
	Speed: number,
	Damage: number,
	AttackRange: number,
	DetectionRange: number,
	AggroRadius: number,
	ChaseMultiplier: number,
	AttackCooldown: number,
	XP: number,
	Coins: number,
	MaxAlive: number,
	Color: Color3,
	Material: Enum.Material,
}

-- Definiciones por mundo. El indice es el `Id` que usa el resto del juego.
local DEFINITIONS: { [string]: MonsterDefinition } = {}

--- Declara un monstruo. Reutilizado por todos los mundos.
--- @param def table
local function define(def: { [string]: any })
	DEFINITIONS[def.Id] = {
		Id = def.Id,
		Name = def.Name or def.Id,
		Health = def.Health or 30,
		Speed = def.Speed or 8,
		Damage = def.Damage or 8,
		AttackRange = def.AttackRange or 6,
		DetectionRange = def.DetectionRange or 35,
		AggroRadius = def.AggroRadius or 40,
		ChaseMultiplier = def.ChaseMultiplier or 1.2,
		AttackCooldown = def.AttackCooldown or 1.5,
		XP = def.XP or 15,
		Coins = def.Coins or 5,
		MaxAlive = def.MaxAlive or 12,
		Color = def.Color or Color3.fromRGB(140, 190, 140),
		Material = def.Material or Enum.Material.SmoothPlastic,
	}
end

-- Forest (nivel 1): los mas debiles del juego.
define({ Id = "Slime", Name = "Slime", Health = 30, Speed = 6, Damage = 6,
	XP = 15, Coins = 5, Color = Color3.fromRGB(120, 210, 130), MaxAlive = 10 })
define({ Id = "BombBug", Name = "Bomb Bug", Health = 40, Speed = 9, Damage = 10,
	XP = 22, Coins = 8, DetectionRange = 45, MaxAlive = 8,
	Color = Color3.fromRGB(200, 90, 90) })
define({ Id = "Shadow", Name = "Shadow", Health = 35, Speed = 11, Damage = 9,
	XP = 25, Coins = 9, DetectionRange = 50, ChaseMultiplier = 1.5, MaxAlive = 8,
	Color = Color3.fromRGB(70, 70, 100) })

-- Desert (nivel 10).
define({ Id = "Hunter", Name = "Hunter", Health = 70, Speed = 12, Damage = 16,
	XP = 40, Coins = 15, DetectionRange = 55, ChaseMultiplier = 1.6,
	Color = Color3.fromRGB(210, 170, 90), MaxAlive = 8 })
define({ Id = "Guardian", Name = "Guardian", Health = 140, Speed = 5, Damage = 24,
	XP = 70, Coins = 25, DetectionRange = 30, ChaseMultiplier = 1.1,
	AttackRange = 8, Color = Color3.fromRGB(160, 130, 80), MaxAlive = 5 })

-- Ice (nivel 20).
define({ Id = "IceBeast", Name = "Ice Beast", Health = 120, Speed = 10, Damage = 22,
	XP = 60, Coins = 22, DetectionRange = 45, Color = Color3.fromRGB(150, 210, 235),
	MaxAlive = 8 })

-- Volcano (nivel 35).
define({ Id = "FireBeast", Name = "Fire Beast", Health = 180, Speed = 11, Damage = 30,
	XP = 95, Coins = 35, DetectionRange = 50, Color = Color3.fromRGB(230, 110, 50),
	MaxAlive = 7 })
define({ Id = "BomberMonster", Name = "Bomber", Health = 90, Speed = 14, Damage = 45,
	XP = 85, Coins = 30, DetectionRange = 60, ChaseMultiplier = 1.8,
	AttackRange = 10, Color = Color3.fromRGB(180, 60, 40), MaxAlive = 5 })

-- Cyber (nivel 50).
define({ Id = "CyberStalker", Name = "Cyber Stalker", Health = 260, Speed = 13, Damage = 38,
	XP = 130, Coins = 50, DetectionRange = 60, ChaseMultiplier = 1.7,
	Color = Color3.fromRGB(80, 230, 230), MaxAlive = 6 })

local Definitions = {}

--- Definicion de un monstruo, o nil si no existe.
--- @param id string
--- @return MonsterDefinition?
function Definitions.Get(id: string): MonsterDefinition?
	return DEFINITIONS[id]
end

--- Todos los identificadores, en orden estable.
--- @return { string }
function Definitions.GetIds(): { string }
	local ids = {}
	for id in pairs(DEFINITIONS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--- Tabla completa (diagnostico y pruebas).
--- @return { [string]: MonsterDefinition }
function Definitions.GetAll(): { [string]: MonsterDefinition }
	return DEFINITIONS
end

return Definitions