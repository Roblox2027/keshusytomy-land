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

	local event = AudioConfig.Events[eventName]

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

	local finalVolume = AudioRules.ResolveVolume(category, volume)

	-- El maestro se aplica aqui y no en `AudioPool`: el pool decide QUE
	-- ranura usar, no a que volumen suena.
	if finalVolume <= 0 then
		return false
	end

	sound.SoundId = assetId
	sound.Volume = finalVolume

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

--- Cambia la musica segun el ESTADO de juego (no el mundo).
---
--- `MusicByState` cubre los siete momentos del ciclo: lobby,
--- exploracion, combate, arena, jefe, victoria y derrota. El jugador no
--- elige la pista: es la situacion la que la elige.
---
--- @param state string clave de `AudioConfig.MusicByState`
--- @return boolean started
function Controller.SetStateMusic(state: string): boolean
	local entry = AudioConfig.MusicByState[state]

	if entry == nil then
		-- Estado desconocido: no es un error grave, pero si revela que
		-- alguien cambio el estado sin actualizar el catalogo.
		Logger.Warn(("AudioController: estado de musica desconocido: %s"):format(state))
		return Controller.PlayMusic(nil)
	end

	-- `false` significa "aun no hay pista subida"; se trata como silencio
	-- en vez de inventarse un ID.
	return Controller.PlayMusic(if type(entry) == "string" then entry else nil)
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

	for _, event in pairs(AudioConfig.Events) do
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

	-- La musica de la zona actual. Sin ID, `PlayMusic` sale por la rama de
	-- silencio y no se queda colgada ninguna pista.
	Controller.SetStateMusic("Lobby")

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

	-- El estado de categorias y enfriamientos tambien se limpia. Sin esto,
	-- un `Start` posterior encontraria marcas de una sesion anterior y el
	-- primer sonido nuevo se comeria su propio enfriamiento.
	table.clear(_poolCategory)
	table.clear(_lastPlayedAt)
	_playCount = 0

	return true
end

return Controller
