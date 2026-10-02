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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local AudioConfig = require(CONFIG:WaitForChild("AudioConfig"))
local AudioPool = require(SHARED:WaitForChild("Libraries"):WaitForChild("AudioPool"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Controller = {}

Controller.IsActive = false

-- Contenedor de todo lo que este controller crea. Se destruye entero en
-- `Destroy`: ningun `Sound` sobrevive al apagado del controller.
local _folder: Folder? = nil

-- Pista de musica actual. Una sola a la vez: dos musicas superpuestas
-- en un juego de arena es ruido, no ambiente.
local _music: Sound? = nil

-- Conjunto de efectos prestables. Las ranuras las decide `AudioPool`,
-- que es logica pura y se prueba de verdad con `luau.exe`.
local _pool: { Sound } = {}
local _cursor = AudioPool.new(AudioConfig.MaxConcurrentSfx)

-- Contador de peticiones sin asset. Vive aparte porque NO es una ranura
-- ocupada: es audio que ni siquiera se intento reproducir.
local _missingAsset = 0

--- Crea el contenedor y el conjunto de efectos.
--- Es idempotente: si ya existe, lo reutiliza.
--- @return Folder?
local function ensureFolder(): Folder?
	if _folder then
		return _folder
	end

	local folder = Instance.new("Folder")
	folder.Name = "KeshusyAudio"
	folder.Parent = SoundService

	for index = 1, _cursor.size do
		local sound = Instance.new("Sound")
		sound.Name = ("Sfx_%d"):format(index)
		sound.Volume = AudioConfig.SfxVolume
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
	sound.Volume = volume or AudioConfig.SfxVolume
	sound:Play()

	AudioPool.MarkPlayed(_cursor)
	return true
end

--- Cambia la pista de musica con un fundido corto.
---
--- El fundido evita el corte seco entre lobby y arena, que se oye como
--- un fallo de audio y no como un cambio de escena.
--- @param assetId string? ID de la pista, o nil para silencio
--- @return boolean started
function Controller.PlayMusic(assetId: string?): boolean
	if not Controller.IsActive then
		return false
	end

	local folder = ensureFolder()
	if not folder then
		return false
	end

	-- Salir a silencio: se detiene y se libera la pista anterior.
	if not assetId or assetId == "" then
		if _music then
			_music:Stop()
			_music:Destroy()
			_music = nil
		end
		return false
	end

	-- Si ya suena ESA MISMA pista, no se reinicia: entrar y salir de un
	-- portal dos veces no reinicia la musica del lobby.
	if _music and _music.SoundId == assetId and _music.IsPlaying then
		return true
	end

	-- La pista anterior se desvanece y se destruye al terminar.
	if _music then
		local previous = _music
		TweenService:Create(
			previous,
			TweenInfo.new(AudioConfig.MusicFadeTime),
			{ Volume = 0 }
		):Play()
		task.delay(AudioConfig.MusicFadeTime, function()
			if previous.Parent then
				previous:Destroy()
			end
		end)
	end

	local music = Instance.new("Sound")
	music.Name = "Music"
	music.SoundId = assetId
	music.Looped = true
	music.Volume = AudioConfig.MusicVolume
	music.Parent = folder
	music:Play()

	-- Entra con el mismo fundido, para que no haya un salto al arrancar.
	TweenService:Create(
		music,
		TweenInfo.new(AudioConfig.MusicFadeTime),
		{ Volume = AudioConfig.MusicVolume }
	):Play()

	_music = music
	return true
end

--- Cambia la musica segun la zona en la que esta el jugador.
---
--- `worldId` a `nil` significa lobby. La funcion decide sola: el jugador
--- no elige la musica, y el cliente no puede poner la que quiera.
--- @param worldId string? nil para el lobby
--- @return boolean started
function Controller.SetZoneMusic(worldId: string?): boolean
	if not worldId then
		return Controller.PlayMusic(AudioConfig.LobbyMusicId)
	end

	-- `WorldMusic` puede traer `false` ("este mundo aun no tiene musica
	-- subida") o `nil` ("no existe la entrada"). `PlayMusic` trata ambos
	-- como silencio, asi que se le pasa tal cual sin inventar nada.
	local entry = AudioConfig.WorldMusic[worldId]
	return Controller.PlayMusic(if type(entry) == "string" then entry else nil)
end

--- Metricas observables del controller.
--- @return { requested: number, played: number, missingAsset: number, recycled: number }
function Controller.GetStats(): { requested: number, played: number, missingAsset: number, recycled: number }
	return {
		requested = _cursor.stats.Requested,
		played = _cursor.stats.Played,
		missingAsset = _missingAsset,
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

	-- La musica de la zona actual. Sin ID, `PlayMusic` sale por la rama de
	-- silencio y no se queda colgada ninguna pista.
	Controller.SetZoneMusic(nil)

	Logger.Info("AudioController listo.")
	return true
end

--- Detiene el controller y destruye TODO lo que creo.
--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false

	if _music then
		_music:Stop()
		_music:Destroy()
		_music = nil
	end

	-- Se destruye la carpeta entera en vez de vaciar el pool a mano: es la
	-- unica forma de garantizar que no queda ninguna `Sound` huerfana
	-- sonando despues de apagar el controller.
	if _folder then
		_folder:Destroy()
		_folder = nil
	end

	table.clear(_pool)
	AudioPool.Reset(_cursor)
	_missingAsset = 0

	return true
end

return Controller
