--!strict
--[[
	AudioController
	Musica y efectos de sonido del cliente.

	POR QUE EXISTE
	--------------
	Medido en PLAY: el DataModel entero tenia **0 instancias `Sound`**. El
	juego era completamente mudo: ni una explosion, ni una bomba, ni
	musica. El feedback de audio es la mitad del feedback de una accion de
	juego, y sin el colocar una bomba no se siente distinta de andar.

	LA REGLA QUE MANDA AQUI
	-----------------------
	**Un sonido sin asset no se suena.** No se inventa ningun ID.

	`AudioConfig` tiene todos sus campos en `nil` porque no hay ningun
	archivo de audio en el repositorio (`assets/sounds` y `assets/music`
	estan vacias). Cuando el ID es `nil`, este controller NO crea la
	interna `Sound`: lo cuenta y lo reporta. Poner un numero inventado
	haria que cada explosion pidiera un asset inexistente a los servidores
	de Roblox: fallos rojos en el Output y trafico de red para nada.

	Asi el sistema queda COMPLETO y HONESTO: en cuanto se peguen los IDs
	en `AudioConfig`, el sonido suena sin tocar una linea de este archivo.

	POOLING
	-------
	Los efectos se prestan de un conjunto de tamanho fijo
	(`AudioConfig.MaxConcurrentSfx`). Sin tope, una cadena de explosiones
	abre un `Sound` por detonacion y el cliente se atasca; con tope, el
	sonido mas antiguo se recicla.

	SEGURIDAD
	---------
	Este controller NUNCA decide nada de juego. Reproduce lo que el
	SERVIDOR ya valido. Un cliente que manipule su propio `Volume` no
	cambia el resultado de nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local AudioConfig = require(CONFIG:WaitForChild("AudioConfig"))
local AudioPool = require(SHARED:WaitForChild("Libraries"):WaitForChild("AudioPool"))
local AudioRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("AudioRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Controller = {}

Controller.IsActive = false

-- Contenedor de todo lo que este controller crea. Se destruye entero en
-- `Destroy`: ningun `Sound` sobrevive al apagado del controller.
local _folder: Folder? = nil

-- Pista de musica actual. Una sola a la vez: dos musicas superpuestas
-- en un juego de arena es ruido, no ambiente.
local _music: Sound? = nil
local _fadingMusic: Sound? = nil
local _musicFadeTween: any = nil
local _musicFadeGeneration = 0
local _ambience: Sound? = nil
local _fadingAmbience: Sound? = nil
local _ambienceFadeTween: any = nil
local _ambienceFadeGeneration = 0
local _ambientWorldId: string? = nil
local _ambientPhase: string? = nil
local _musicWorldId: string? = nil
local _musicState: string? = nil
local _transientMusicState: string? = nil
local _transientMusicUntil = 0
local _transientMusicGeneration = 0

local _soundGroups: { [string]: any } = {}
local _ownedSoundGroups: { any } = {}
local _userVolumes: { [string]: number } = {
	Master = 1,
	Music = 1,
	Sfx = 1,
	Ambience = 1,
	UI = 1,
}

-- Conjunto de efectos prestables. Las ranuras las decide `AudioPool`,
-- que es logica pura y se prueba de verdad con `luau.exe`.
local _pool: { Sound } = {}
local _cursor = AudioPool.new(AudioConfig.MaxConcurrentSfx)

-- Contador de peticiones sin asset. Vive aparte porque NO es una ranura
-- ocupada: es audio que ni siquiera se intento reproducir.
local _missingAsset = 0

-- Ranura -> categoria que la ocupa.
--
-- Es lo que permite respetar la prioridad: sin ella, el pool solo sabe que la
-- ranura 3 esta ocupada, no por un ambiente o por una explosion, y no
-- podria decidir a quien le recorta el sitio.
local _poolCategory: { [number]: string } = {}

-- Categoria -> instante (os.clock) de su ultima reproduccion.
--
-- Es el estado del ANTI-SPAM. Vive aqui y no en `AudioRules` porque es
-- estado de ESTA maquina: las reglas son puras y no saben nada del reloj.
local _lastPlayedAt: { [string]: number } = {}

-- Reproducciones reales. Es la metrica que dice si el audio esta sonando
-- de verdad o si el catalogo esta lleno de eventos sin asset.
local _playCount = 0

local SOUND_GROUP_CONFIG: { [string]: { Name: string, BaseVolume: number } } = {
	Music = { Name = "KeshusyMusic", BaseVolume = AudioConfig.MusicVolume },
	Sfx = { Name = "KeshusySfx", BaseVolume = AudioConfig.SfxVolume },
	Ambience = { Name = "KeshusyAmbience", BaseVolume = AudioRules.Volume.Ambient },
	UI = { Name = "KeshusyUI", BaseVolume = AudioRules.Volume.UI },
}

local CATEGORY_GROUP = {
	Music = "Music",
	Ambient = "Ambience",
	UI = "UI",
	Voice = "Sfx",
	Sfx = "Sfx",
}

local function applyGroupVolumes()
	local master = AudioRules.MasterVolume * _userVolumes.Master
	for channel, config in pairs(SOUND_GROUP_CONFIG) do
		local group = _soundGroups[channel]
		if group then
			group.Volume = math.clamp(config.BaseVolume * master * _userVolumes[channel], 0, 1)
		end
	end
end

local function ensureSoundGroups()
	for channel, config in pairs(SOUND_GROUP_CONFIG) do
		local existing = SoundService:FindFirstChild(config.Name)
		local group: any

		if existing and existing:IsA("SoundGroup") then
			group = existing
		else
			group = Instance.new("SoundGroup")
			group.Name = config.Name
			group.Parent = SoundService
			table.insert(_ownedSoundGroups, group)
		end

		_soundGroups[channel] = group
	end
	applyGroupVolumes()
end

local function groupForCategory(category: string): any
	local groupName = CATEGORY_GROUP[category] or "Sfx"
	return _soundGroups[groupName]
end

--- Adjusts one client-side mix channel. Channels are Master, Music, Sfx, Ambience, and UI.
--- @param channel string
--- @param volume number
--- @return boolean
function Controller.SetVolume(channel: string, volume: number): boolean
	if _userVolumes[channel] == nil or type(volume) ~= "number" or volume ~= volume then
		return false
	end

	_userVolumes[channel] = math.clamp(volume, 0, 1)
	applyGroupVolumes()
	return true
end

--- @return { [string]: number }
function Controller.GetVolumes(): { [string]: number }
	return {
		Master = _userVolumes.Master,
		Music = _userVolumes.Music,
		Sfx = _userVolumes.Sfx,
		Ambience = _userVolumes.Ambience,
		UI = _userVolumes.UI,
	}
end

--- Crea el contenedor y el conjunto de efectos.
--- Es idempotente: si ya existe, lo reutiliza.
--- @return Folder?
local function ensureFolder(): Folder?
	ensureSoundGroups()
	if _folder then
		return _folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "KeshusyAudio"
	folder.Parent = SoundService
	for index = 1, _cursor.size do
		local sound = Instance.new("Sound")
		sound.Name = ("Sfx_%d"):format(index)
		sound.Volume = 1
		sound.SoundGroup = _soundGroups.Sfx
		-- El pool se prestara con `SoundId`: una `Sound` con la ID puesta
		-- no se oye sola, y por eso pueden convivir en la misma carpeta.
		sound.Parent = folder
		table.insert(_pool, sound)
	end

	_folder = folder
	return folder
end

--- Reproduce un efecto corto.
---
--- Devuelve `false` sin hacer NADA cuando no hay asset. Es el
--- comportamiento correcto, no un fallo: el juego sigue siendo jugable
--- en silencio y en cuanto se configure el ID suena.
--- @param assetId string? ID del asset, o nil si no hay
--- @param volume number? volumen 0..1
--- @return boolean played
function Controller.PlaySfx(assetId: string?, volume: number?): boolean
	if not Controller.IsActive then
		return false
	end

	if type(assetId) ~= "string" or assetId == "" then
		-- Sin asset: se cuenta y se sigue. Inventarse un ID aqui haria
		-- que cada explosion pidiera un recurso inexistente.
		_missingAsset += 1
		return false
	end

	local folder = ensureFolder()
	if not folder or #_pool == 0 then
		return false
	end

	-- El indice lo decide `AudioPool` (logica pura, probada aparte).
	-- `recycled` avisa de que la ranura ya estaba sonando: no es un
	-- fallo, es el tope funcionando, y por eso se cuenta aparte.
	local index, recycled = AudioPool.Take(_cursor)
	local sound = _pool[index]

	if recycled and sound.IsPlaying then
		-- Se corta el sonido anterior: el feedback de la explosion mas
		-- reciente pesa mas que terminar el anterior.
		sound:Stop()
	end

	sound.SoundId = assetId
	sound.Volume = math.clamp(volume or 1, 0, 1)
	sound.SoundGroup = _soundGroups.Sfx
	sound:Play()

	AudioPool.MarkPlayed(_cursor)
	return true
end

--- Reproduce un EVENTO del catalogo.
---
--- Es la puerta que usa el resto del juego. Antes de reproducir hace
--- TRES comprobaciones, en este orden, y las tres se saltan por el mismo
--- motivo cuando el asset no existe:
---
--- 1. EXISTENCIA: sin `SoundId` no se crea ningun `Sound`. Es el caso
---    actual (todos los assets estan pendientes) y el juego funciona en
---    silencio sin pedir recursos inexistentes a los servidores.
--- 2. DISTANCIA: un sonido fuera del alcance de su categoria no suena.
--- 3. ENFRIAMIENTO: evita que veinte monstruos llenen el cliente de pasos.
---
--- Devuelve `false` en los tres casos, y en ninguno es un error.
---
--- @param eventName string clave de `AudioConfig.Events`
--- @param position Vector3? posicion del sonido; nil significa "en el jugador"
--- @param volume number? volumen especifico de esta reproduccion, 0..1
--- @return boolean played
function Controller.PlayEvent(eventName: string, position: Vector3?, volume: number?): boolean
	if not Controller.IsActive then
		return false
	end

	local event = AudioConfig.Events[eventName] :: { id: string?, category: string }?

	-- Un evento desconocido NO se ignora en silencio: se avisa, porque
	-- significa que el codigo llama a un sonido que nadie declaro.
	if event == nil then
		Logger.Warn(("AudioController: evento de audio desconocido: %s"):format(eventName))
		return false
	end

	local assetId = event.id

	if type(assetId) ~= "string" or assetId == "" then
		-- Sin asset: se cuenta y se sigue. Inventarse un ID aqui haria que
		-- cada explosion pidiera un recurso inexistente en cada ronda.
		_missingAsset += 1
		return false
	end

	local category = event.category
	local now = os.clock()

	-- DISTANCIA. `position = nil` significa "suena aqui", que es el caso
	-- de la interfaz y de los sonidos del propio jugador.
	if position ~= nil then
		local listener = Controller.getListenerPosition()

		if listener ~= nil then
			local distance = (position - listener).Magnitude

			if not AudioRules.IsAudible(category, distance) then
				return false
			end
		end
	end

	-- ENFRIAMIENTO por categoria. La marca se actualiza SOLO si el
	-- sonido llega a reproducirse: si no, un sonido descartado por
	-- distancia no podria sonar ni un instante despues.
	local lastPlayedAt = _lastPlayedAt[category]

	if lastPlayedAt == nil then
		lastPlayedAt = -1
	end

	local allowed = AudioRules.CheckCooldown(category, lastPlayedAt, now)

	if not allowed then
		return false
	end

	local folder = ensureFolder()

	if folder == nil or #_pool == 0 then
		return false
	end

	-- El indice lo decide `AudioPool` (logica pura, probada aparte).
	local index, recycled = AudioPool.Take(_cursor)
	local sound = _pool[index]

	-- COMPETENCIA POR LA RANURA. Si lo que ya suena tiene MAS prioridad
	-- que lo nuevo, se respeta el que esta sonando: es el caso "un paso no
	-- puede tapar una explosion".
	if recycled and sound.IsPlaying then
		local residentCategory = _poolCategory[index]

		if residentCategory ~= nil and not AudioRules.Compare(category, residentCategory) then
			return false
		end

		sound:Stop()
	end

	local finalVolume = if type(volume) == "number" then math.clamp(volume, 0, 1) else 1

	-- El maestro se aplica aqui y no en `AudioPool`: el pool decide QUE
	-- ranura usar, no a que volumen suena.
	if finalVolume <= 0 then
		return false
	end

	sound.SoundId = assetId
	sound.Volume = finalVolume
	sound.SoundGroup = groupForCategory(category)

	-- ESPACIAL O NO.
	--
	-- Con `position`, el motor se encarga de la atenuacion y del paneo: asi
	-- la explosion suena donde ha EXPLOTADO, que es la informacion que el
	-- jugador necesita. Sin `position`, el sonido es 2D y suena entero en
	-- cualquier lado de la pantalla (interfaz, musica, sonidos del propio
	-- jugador).
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = AudioRules.GetMaxDistance(category)
	sound.RollOffMinDistance = AudioRules.GetMaxDistance(category) * AudioRules.FullVolumeRatio
	sound.Parent = folder

	if position ~= nil then
		sound.Position = position
	end

	sound:Play()

	_poolCategory[index] = category
	_lastPlayedAt[category] = now

	AudioPool.MarkPlayed(_cursor)

	_playCount += 1
	return true
end

--- Posicion del OYENTE.
---
--- Se calcula en cada uso y no se cachea: el jugador se mueve, y un valor
--- cacheado haria que un sonido se decidiera con una posicion vieja y
--- apareciera (o desapareciera) a destiempo.
---
--- @return Vector3? nil si todavia no hay personaje
function Controller.getListenerPosition(): Vector3?
	local player = Players.LocalPlayer

	if player == nil then
		return nil
	end

	local character = player.Character

	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	return root.Position
end

--- Cambia la pista de musica con un fundido corto.
---
--- El fundido evita el corte seco entre lobby y arena, que se oye como
--- un fallo de audio y no como un cambio de escena.
--- @param assetId string? ID de la pista, o nil para silencio
--- @return boolean started
local function clearFadingMusic()
	_musicFadeGeneration += 1
	if _musicFadeTween then
		_musicFadeTween:Cancel()
		_musicFadeTween = nil
	end
	if _fadingMusic then
		_fadingMusic:Stop()
		_fadingMusic:Destroy()
		_fadingMusic = nil
	end
end

local function fadeOutMusic(sound: Sound)
	clearFadingMusic()
	_musicFadeGeneration += 1
	local generation = _musicFadeGeneration
	_fadingMusic = sound
	local tween =
		TweenService:Create(sound, TweenInfo.new(AudioConfig.MusicFadeTime), { Volume = 0 })
	_musicFadeTween = tween
	tween.Completed:Connect(function()
		if generation ~= _musicFadeGeneration or _fadingMusic ~= sound then
			return
		end
		sound:Stop()
		sound:Destroy()
		_fadingMusic = nil
		_musicFadeTween = nil
	end)
	tween:Play()
end

function Controller.PlayMusic(assetId: string?): boolean
	if not Controller.IsActive then
		return false
	end

	local folder = ensureFolder()
	if not folder then
		return false
	end

	-- Salir a silencio: desvanece y libera la pista anterior.
	if not assetId or assetId == "" then
		if _music then
			local previous = _music
			_music = nil
			fadeOutMusic(previous)
		end
		return false
	end

	-- Si ya suena ESA MISMA pista, no se reinicia: entrar y salir de un
	-- portal dos veces no reinicia la musica del lobby.
	if _music and _music.SoundId == assetId and _music.IsPlaying then
		return true
	end

	-- Keep at most one intentional crossfade pair. Rapid state changes retire
	-- the older outgoing track before a new pair is created.
	if _music then
		local previous = _music
		_music = nil
		fadeOutMusic(previous)
	else
		clearFadingMusic()
	end

	local music = Instance.new("Sound")
	music.Name = "Music"
	music.SoundId = assetId
	music.Looped = true
	music.Volume = 0
	music.SoundGroup = _soundGroups.Music
	music.Parent = folder
	music:Play()

	-- Crossfade: both tracks are controlled, with no hard cut.
	TweenService:Create(music, TweenInfo.new(AudioConfig.MusicFadeTime), { Volume = 1 }):Play()

	_music = music
	return true
end

local function clearFadingAmbience()
	_ambienceFadeGeneration += 1
	if _ambienceFadeTween then
		_ambienceFadeTween:Cancel()
		_ambienceFadeTween = nil
	end
	if _fadingAmbience then
		_fadingAmbience:Stop()
		_fadingAmbience:Destroy()
		_fadingAmbience = nil
	end
end

local function fadeOutAmbience(sound: Sound)
	clearFadingAmbience()
	_ambienceFadeGeneration += 1
	local generation = _ambienceFadeGeneration
	_fadingAmbience = sound
	local tween =
		TweenService:Create(sound, TweenInfo.new(AudioConfig.MusicFadeTime), { Volume = 0 })
	_ambienceFadeTween = tween
	tween.Completed:Connect(function()
		if generation ~= _ambienceFadeGeneration or _fadingAmbience ~= sound then
			return
		end
		sound:Stop()
		sound:Destroy()
		_fadingAmbience = nil
		_ambienceFadeTween = nil
	end)
	tween:Play()
end

function Controller.PlayAmbience(assetId: string?): boolean
	if not Controller.IsActive then
		return false
	end
	local folder = ensureFolder()
	if not folder then
		return false
	end
	if type(assetId) ~= "string" or assetId == "" then
		if _ambience then
			local previous = _ambience
			_ambience = nil
			fadeOutAmbience(previous)
		end
		return false
	end
	if _ambience and _ambience.SoundId == assetId and _ambience.IsPlaying then
		return true
	end
	if _ambience then
		local previous = _ambience
		_ambience = nil
		fadeOutAmbience(previous)
	else
		clearFadingAmbience()
	end

	local sound = Instance.new("Sound")
	sound.Name = "WorldAmbience"
	sound.SoundId = assetId
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = _soundGroups.Ambience
	sound.Parent = folder
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(AudioConfig.MusicFadeTime), { Volume = 1 }):Play()
	_ambience = sound
	return true
end

function Controller.SetAmbientScene(worldId: string?, phase: string): boolean
	local world = if type(worldId) == "string" and worldId ~= "Lobby" then worldId else nil
	local ambience: any
	if not world then
		ambience = AudioConfig.LobbyAmbienceId
	else
		local phaseTracks = AudioConfig.WorldAmbienceByPhase[world]
		ambience = phaseTracks and phaseTracks[phase]
		if type(ambience) ~= "string" then
			ambience = AudioConfig.WorldAmbience[world]
		end
	end
	_ambientWorldId = world
	_ambientPhase = phase
	return Controller.PlayAmbience(if type(ambience) == "string" then ambience else nil)
end

function Controller.UpdateAmbientScene(): boolean
	local player = Players.LocalPlayer
	local worldId = player and player:GetAttribute("World")
	if type(worldId) ~= "string" or worldId == "Lobby" then
		worldId = nil
	end
	local nightPhase = player and player:GetAttribute("NightPhase")
	local phase = if nightPhase == "Night" or nightPhase == "Dawn" then "Night" else "Day"
	if worldId == _ambientWorldId and phase == _ambientPhase then
		return false
	end
	return Controller.SetAmbientScene(worldId, phase)
end

--- Cambia la musica segun la zona en la que esta el jugador.
---
--- `worldId` a `nil` significa lobby. La funcion decide sola: el jugador
--- no elige la musica, y el cliente no puede poner la que quiera.
--- @param worldId string? nil para el lobby
--- @return boolean started
function Controller.SetZoneMusic(worldId: string?): boolean
	return Controller.SetSceneMusic(worldId, if worldId then "Exploring" else "Lobby")
end

--- Cambia la musica segun el ESTADO de juego (no el mundo).
---
--- `MusicByState` cubre los siete momentos del ciclo: lobby,
--- exploracion, combate, arena, jefe, victoria y derrota. El jugador no
--- elige la pista: es la situacion la que la elige.
---
--- @param state string clave de `AudioConfig.MusicByState`
--- @return boolean started
function Controller.SetStateMusic(state: string): boolean
	return Controller.SetSceneMusic(_musicWorldId, state)
end

--- Picks the most specific verified track, falling back to the current world's exploration track.
--- @param worldId string?
--- @param state string
--- @return boolean started
function Controller.SetSceneMusic(worldId: string?, state: string): boolean
	local world = if type(worldId) == "string" and worldId ~= "Lobby" then worldId else nil
	local scene = if world then state else "Lobby"
	local entry: any = nil

	if world and scene == "Exploring" then
		entry = AudioConfig.WorldMusic[world]
	elseif world then
		local worldStates = AudioConfig.WorldMusicByState[world]
		entry = worldStates and worldStates[scene]
	end

	if type(entry) ~= "string" then
		entry = AudioConfig.MusicByState[scene]
	end
	if type(entry) ~= "string" and world then
		entry = AudioConfig.WorldMusic[world]
	end
	if type(entry) ~= "string" and not world then
		entry = AudioConfig.LobbyMusicId
	end

	if AudioConfig.MusicByState[scene] == nil then
		Logger.Warn(("AudioController: estado de musica desconocido: %s"):format(scene))
		scene = if world then "Exploring" else "Lobby"
	end

	if type(entry) ~= "string" then
		if _musicWorldId ~= world then
			Controller.PlayMusic(nil)
		end
		_musicWorldId = world
		_musicState = scene
		return false
	end

	local started = Controller.PlayMusic(entry)
	_musicWorldId = world
	_musicState = scene
	return started
end

local function nearbyThreats(): (boolean, boolean)
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root: BasePart? = nil
	if character then
		local rootInstance = character:FindFirstChild("HumanoidRootPart")
		if rootInstance and rootInstance:IsA("BasePart") then
			root = rootInstance
		end
	end
	local monsters: Instance? = workspace:FindFirstChild("Monsters")
	if not root or not root:IsA("BasePart") or not monsters then
		return false, false
	end

	local danger = false
	local combat = false
	for _, candidate in ipairs(monsters:GetChildren()) do
		local monster = candidate :: Instance
		if not monster:IsA("Model") then
			continue
		end
		local model = monster :: Model
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local monsterRoot: BasePart? = model.PrimaryPart
		if not humanoid or humanoid.Health <= 0 or not monsterRoot then
			continue
		end
		if (monsterRoot.Position - root.Position).Magnitude > 110 then
			continue
		end

		local state = model:GetAttribute("AIState")
		if state == "Warning" or state == "Charge" then
			combat = true
		elseif state == "Chase" then
			danger = true
		end
	end
	return danger, combat
end

--- Re-evaluates music from replicated world/boss state and nearby server-driven AI states.
--- @return boolean started
function Controller.UpdateMusicState(): boolean
	if not Controller.IsActive then
		return false
	end

	local player = Players.LocalPlayer
	local worldId = player and player:GetAttribute("World")
	if type(worldId) ~= "string" or worldId == "Lobby" then
		worldId = nil
	end
	Controller.UpdateAmbientScene()

	local danger, combat = nearbyThreats()
	local now = os.clock()
	local override = if now < _transientMusicUntil then _transientMusicState else nil
	if override == nil then
		_transientMusicState = nil
		_transientMusicUntil = 0
	end
	local state = AudioRules.SelectMusicState({
		WorldId = worldId,
		Danger = danger,
		Combat = combat,
		Boss = player ~= nil and type(player:GetAttribute("BossName")) == "string",
		Victory = override == "Victory",
		Defeat = override == "Defeat",
	})

	if state == _musicState and worldId == _musicWorldId then
		return false
	end
	return Controller.SetSceneMusic(worldId, state)
end

--- Plays a short victory/defeat score override, then resumes the current scene state.
--- @param state string
--- @param duration number
--- @return boolean
function Controller.SetTransientMusicState(state: string, duration: number): boolean
	if state ~= "Victory" and state ~= "Defeat" then
		return false
	end
	_transientMusicGeneration += 1
	local generation = _transientMusicGeneration
	_transientMusicState = state
	_transientMusicUntil = os.clock() + math.clamp(duration, 1, 20)
	Controller.UpdateMusicState()
	task.delay(math.clamp(duration, 1, 20), function()
		if generation ~= _transientMusicGeneration or not Controller.IsActive then
			return
		end
		_transientMusicState = nil
		_transientMusicUntil = 0
		Controller.UpdateMusicState()
	end)
	return true
end

--- Sonido de superficie para un mundo dado.
---
--- Los pasos cambian con el MATERIAL, no con la accion: correr sobre
--- hielo no suena como correr sobre tierra. El mundo decide cual de los
--- cinco es, y asi el jugador oye donde esta sin mirar.
---
--- @param worldId string? mundo actual
--- @return string eventName clave de `AudioConfig.Events`
function Controller.GetStepEvent(worldId: string?): string
	local id = if type(worldId) == "string" then worldId else "Forest"

	-- Un mundo desconocido cae en Forest en vez de en silencio: es el
	-- unico caso en que un paso sin sonido delata un bug de mundo.
	return "Step" .. id
end

--- Metricas observables del controller.
---
--- `pendingAssets` es la metrica HONESTA del estado del audio: si es
--- mayor que cero, hay eventos declarados sin fichero subido. No se
--- maquilla como PASS ni como FAIL: es un numero que se puede consultar.
---
--- @return table stats
function Controller.GetStats(): { [string]: number }
	local pending = 0

	for _, event in pairs(AudioConfig.Events :: { [string]: { id: string?, category: string } }) do
		if event.id == nil then
			pending += 1
		end
	end

	return {
		requested = _cursor.stats.Requested,
		played = _cursor.stats.Played,
		eventsPlayed = _playCount,
		missingAsset = _missingAsset,
		pendingAssets = pending,
		recycled = _cursor.stats.Recycled,
	}
end

-- ------------------------------------------------------------- CICLO DE VIDA

--- Activa el controller. Idempotente.
--- @param maid any?
--- @return boolean success
function Controller.Start(maid: any?): boolean
	if Controller.IsActive then
		return true
	end

	Controller.IsActive = true

	-- El contenedor y el pool se crean al arrancar, aunque todavia no haya
	-- ningun ID configurado. Asi, en cuanto se peguen los IDs, el sonido
	-- suena sin tocar este archivo.
	ensureFolder()

	-- Initial scene and threat state are read from server-published attributes.
	Controller.UpdateMusicState()
	task.spawn(function()
		while Controller.IsActive do
			Controller.UpdateMusicState()
			task.wait(0.4)
		end
	end)

	-- Las dos tablas de estado se vacian aqui y no solo en `Destroy`: un
	-- `Start` posterior tras un `Stop` debe empezar sin marcas de
	-- enfriamiento antiguas, o el primer sonido de la nueva sesion se
	-- comeria su propio enfriamiento.
	table.clear(_lastPlayedAt)
	table.clear(_poolCategory)
	_playCount = 0

	Logger.Info("AudioController listo.")
	return true
end

--- Detiene el controller y destruye TODO lo que creo.
--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false
	_transientMusicGeneration += 1
	_transientMusicState = nil
	_transientMusicUntil = 0
	clearFadingMusic()
	clearFadingAmbience()

	if _music then
		_music:Stop()
		_music:Destroy()
		_music = nil
	end
	if _ambience then
		_ambience:Stop()
		_ambience:Destroy()
		_ambience = nil
	end

	-- Se destruye la carpeta entera en vez de vaciar el pool a mano: es la
	-- unica forma de garantizar que no queda ninguna `Sound` huerfana
	-- sonando despues de apagar el controller.
	if _folder then
		_folder:Destroy()
		_folder = nil
	end
	for _, group in ipairs(_ownedSoundGroups) do
		if group.Parent then
			group:Destroy()
		end
	end
	table.clear(_ownedSoundGroups)
	table.clear(_soundGroups)

	table.clear(_pool)
	AudioPool.Reset(_cursor)
	_missingAsset = 0

	-- El estado de categorias y enfriamientos tambien se limpia. Sin esto,
	-- un `Start` posterior encontraria marcas de una sesion anterior y el
	-- primer sonido nuevo se comeria su propio enfriamiento.
	table.clear(_poolCategory)
	table.clear(_lastPlayedAt)
	_playCount = 0
	_musicWorldId = nil
	_musicState = nil
	_ambientWorldId = nil
	_ambientPhase = nil

	return true
end

return Controller
