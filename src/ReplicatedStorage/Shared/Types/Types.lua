--!strict
--[[
	Types
	Contratos de datos compartidos (solo tipado, sin logica).

	Convencion de campos:
	- Las keys numericas simulan "ID numerico de Roblox" y son autoritativas.
	- Los IDs de mundo son strings estables definidos en WorldDefinitions.
]]

export type PlayerProfile = {
	UserId: number,
	Username: string,
	DisplayName: string,
	Level: number,
	XP: number,
	Coins: number,
	Gems: number,
	Inventory: { string },
	EquippedCharacter: string?,
	DataVersion: number,
	UpdatedAt: number,
}

export type BombData = {
	Id: number,
	OwnerId: number?,
	Position: Vector3,
	Radius: number,
	FuseTime: number,
	StartTime: number,
	Damage: number,
	WorldId: string?,
}

export type ExplosionData = {
	Id: number,
	Position: Vector3,
	Radius: number,
	Damage: number,
	SourceId: number?,
	SourceKind: "Bomb" | "Monster" | "Environment",
	CreatedAt: number,
}

export type MonsterData = {
	Id: number,
	DefinitionId: string,
	Name: string,
	Health: number,
	MaxHealth: number,
	Damage: number,
	MoveSpeed: number,
	WorldId: string?,
	IsBoss: boolean,
	Position: Vector3?,
}

export type WorldData = {
	Id: string,
	Name: string,
	DisplayName: string,
	RequiredLevel: number,
	Theme: string,
	Difficulty: number,
	MusicId: string?,
	MapFolder: string?,
	BossDefinitionId: string?,
	SpawnRules: { string },
	Rewards: {
		XP: number,
		Coins: number,
	},
}

export type RewardData = {
	PlayerId: number,
	XP: number,
	Coins: number,
	Placement: number?,
	WorldId: string?,
	Reason: string,
	GrantedAt: number,
}

export type QuestData = {
	Id: string,
	Title: string,
	Description: string,
	ObjectiveType: string,
	ObjectiveTarget: number,
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
	RewardXP: number,
	RewardCoins: number,
}

export type ItemData = {
	Id: string,
	DisplayName: string,
	Category: "Character" | "Bomb" | "Monster" | "Consumable" | "Cosmetic",
	Rarity: "Common" | "Rare" | "Epic" | "Legendary",
	Price: number,
	LevelRequirement: number,
	Enabled: boolean,
}

return {}
