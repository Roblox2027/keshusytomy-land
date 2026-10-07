--!strict
--[[
	AudioConfig
	Catalogo de sonido del juego.

	POR QUE UN CATALOGO Y NO IDS SUELTOS EN EL CODIGO
	-------------------------------------------------
	Los identificadores de asset son datos, no logica. Centralizarlos
	permite cambiarlos sin tocar el servicio, y deja escrito de forma
	explicita lo que TODAVIA NO EXISTE.

	ESTADO REAL (medido, 2026-10-02)
	--------------------------------
	`Workspace` y todo el DataModel tienen **0 instancias `Sound`**, y las
	carpetas `assets/sounds` y `assets/music` estan VACIAS. No hay ningun
	archivo de audio en el repositorio.

	Por eso los campos de abajo estan en `nil` a proposito, y
	`AudioService` lo trata como "sin sonido" en vez de inventarse un ID.
	Poner un numero cualquiera aqui haria que el juego intentara cargar
	un asset inexistente en cada ronda: fallos rojos en el Output y
	consumo de red para nada.

	PARA ACTIVAR UN SONIDO
	----------------------
	1. Sube el archivo al Creator Dashboard (Audio > Upload).
	2. Pega el ID numerico en la tabla de abajo.
	3. Nada mas: `AudioService` lo recoge al arrancar.

	El servicio no depende de que haya IDs: arranca vacio y funciona.
]]

return {
	-- -------------------------------------------------------------------
	-- MUSICA
	-- -------------------------------------------------------------------
	-- Fondo del lobby. Sondeado en bucle (`Looped`).
	LobbyMusicId = nil :: string?,

	-- Fondo de cada mundo. La clave es el `Id` de `WorldDefinitions`.
	--
	-- Se declaran los CINCO mundos del contrato, no solo los habilitados.
	-- El valor `false` significa "este mundo todavia no tiene musica
	-- subida"; `nil` significaria "no existe esta entrada", que es otra
	-- cosa: una tabla con todos los valores en `nil` esta VACIA, y
	-- `AudioConfig.spec` lo detecto al exigir que las cinco claves
	-- existan. Anadir un mundo no obliga a tocar este archivo mas que
	-- anadiendo su entrada.
	WorldMusic = {
		Forest = false,
		Desert = false,
		Ice = false,
		Volcano = false,
		Cyber = false,
	} :: { [string]: string | boolean },

	-- Overrides for states that need a distinct score within each world.
	-- False keeps the world exploration theme playing until a verified track is uploaded.
	WorldMusicByState = {
		Forest = { Danger = false, Combat = false, Boss = false, Victory = false, Defeat = false },
		Desert = { Danger = false, Combat = false, Boss = false, Victory = false, Defeat = false },
		Ice = { Danger = false, Combat = false, Boss = false, Victory = false, Defeat = false },
		Volcano = { Danger = false, Combat = false, Boss = false, Victory = false, Defeat = false },
		Cyber = { Danger = false, Combat = false, Boss = false, Victory = false, Defeat = false },
	} :: { [string]: { [string]: string | boolean } },

	LobbyAmbienceId = false :: string | boolean,
	WorldAmbience = {
		Forest = false,
		Desert = false,
		Ice = false,
		Volcano = false,
		Cyber = false,
	} :: { [string]: string | boolean },
	WorldAmbienceByPhase = {
		Forest = { Day = false, Night = false },
		Desert = { Day = false, Night = false },
		Ice = { Day = false, Night = false },
		Volcano = { Day = false, Night = false },
		Cyber = { Day = false, Night = false },
	} :: { [string]: { [string]: string | boolean } },

	-- -------------------------------------------------------------------
	-- EFECTOS
	-- -------------------------------------------------------------------
	BombPlaceId = nil :: string?,
	BombFuseId = nil :: string?,
	ExplosionId = nil :: string?,
	BlockDestroyId = nil :: string?,
	PlayerHurtId = nil :: string?,
	PlayerDeathId = nil :: string?,
	PowerUpId = nil :: string?,
	RoundStartId = nil :: string?,
	RoundWinId = nil :: string?,
	-- El sonido de recoger monedas. Era `nil :: string` (sin `?`), lo que
	-- hacia que el analizador fallara: un campo declarado `string` no
	-- puede valer `nil`. Ahora es opcional, que es lo que significa
	-- "todavia sin asset subido".
	CoinRewardId = nil :: string?,
	-- El Core. `CoreIdle` en bucle mientras esta activo; `CoreCharge` al
	-- aportar un fragmento; `CoreActivate` al llegar a la carga maxima.
	CoreIdleId = nil :: string?,
	CoreChargeId = nil :: string?,
	CoreActivateId = nil :: string?,

	-- Portales: `PortalOpen` al entrar en un mundo, `PortalDenied` al
	-- rechazar el viaje.
	PortalOpenId = nil :: string?,
	PortalDeniedId = nil :: string?,

	-- UI: clic de boton y confirmacion.
	UiClickId = nil :: string?,
	UiConfirmId = nil :: string?,

	-- -------------------------------------------------------------------
	-- EVENTOS
	-- -------------------------------------------------------------------
	--
	-- Cada accion de juego que tenga que COMUNICAR algo tiene aqui su
	-- entrada: que sonido y de que categoria.
	--
	-- Por que una tabla y no una llamada directa en cada sitio:
	-- 1. La regla de negocio lo exige ("si algo importante se mueve, lo
	--    comunica"). Una tabla la hace COMPROBABLE: `AudioRules.spec`
	--    recorre esta tabla y falla si falta un evento obligatorio.
	-- 2. Centraliza los IDs: pegar uno nuevo es cambiar un dato, no
	--    editar logica.
	-- 3. Permite categorias: un paso y una explosion no se mezclan.
	--
	-- FORMATO: { id = nil | string, category = "Sfx" }
	--
	-- `id = nil` significa "sin asset todavia". NO se inventa un numero:
	-- el juego lo trata como silencio y lo cuenta. Es honesto y no genera
	-- fallos rojos en el Output pidiendo recursos inexistentes.
	Events = {
		-- ---------------------------------------------------------- BOMBA
		BombPlace = { id = nil, category = "Sfx" },
		-- La mecha: `CLICK` al ponerla, `TICK` repetido mientras arde.
		BombFuse = { id = nil, category = "Sfx" },
		-- El `BOOM`. El sonido mas importante del juego, y el que mas
		-- lejos tiene que oirse.
		Explosion = { id = nil, category = "Sfx" },
		-- `CRACK / BREAK` al romperse un bloque.
		BlockBreak = { id = nil, category = "Sfx" },
		-- `REWARD` cuando la bomba deja al descubierto un powerup.
		PowerupReveal = { id = nil, category = "Sfx" },

		-- --------------------------------------------------------- JUGADOR
		-- Los pasos varian por SUPERFICIE: tierra en Forest, arena en
		-- Desert, hielo en Ice, roca en Volcano, metal en Cyber.
		StepForest = { id = nil, category = "Sfx" },
		StepDesert = { id = nil, category = "Sfx" },
		StepIce = { id = nil, category = "Sfx" },
		StepVolcano = { id = nil, category = "Sfx" },
		StepCyber = { id = nil, category = "Sfx" },
		Jump = { id = nil, category = "Sfx" },
		Land = { id = nil, category = "Sfx" },
		PlayerHurt = { id = nil, category = "Sfx" },
		PlayerDeath = { id = nil, category = "Sfx" },
		CoinPickup = { id = nil, category = "Sfx" },
		GemPickup = { id = nil, category = "Sfx" },
		LevelUp = { id = nil, category = "Sfx" },
		QuestComplete = { id = nil, category = "Sfx" },
		SecretFound = { id = nil, category = "Sfx" },
		PortalEnter = { id = nil, category = "Sfx" },
		PortalDenied = { id = nil, category = "Sfx" },
		WorldExit = { id = nil, category = "Sfx" },

		-- ------------------------------------------------------------ UI
		UiClick = { id = nil, category = "UI" },
		UiConfirm = { id = nil, category = "UI" },
		UiOpen = { id = nil, category = "UI" },
		Purchase = { id = nil, category = "UI" },
		Equip = { id = nil, category = "UI" },
		Unlock = { id = nil, category = "UI" },
		-- Anuncio de ronda: "empieza", "gana", "pierde".
		RoundStart = { id = nil, category = "UI" },
		RoundWin = { id = nil, category = "UI" },
		RoundLose = { id = nil, category = "UI" },
		-- ------------------------------------------------------ MONSTRUOS
		--
		-- Cada criatura tiene su PROPIA identidad, no un "sonido de
		-- monstruo" comun. Es lo que permite reconocer un Guardian por el
		-- oido antes de verlo.
		MonsterSpawn = { id = nil, category = "Voice" },
		MonsterAlert = { id = nil, category = "Voice" },
		MonsterAttack = { id = nil, category = "Voice" },
		MonsterHurt = { id = nil, category = "Voice" },
		MonsterDeath = { id = nil, category = "Voice" },
		MonsterStep = { id = nil, category = "Voice" },
		-- Telegraph: el aviso previo a un ataque. Es OBLIGATORIO que el
		-- jugador pueda reaccionar, y el aviso tiene que oirse aunque este
		-- mirando hacia otro lado.
		MonsterTelegraph = { id = nil, category = "Voice" },

		-- --------------------------------------------------------- MUNDOS
		-- Ambiente por mundo. Cada uno tiene su identidad: el Forest no
		-- puede sonar como el Volcano.
		AmbientForest = { id = nil, category = "Ambient" },
		AmbientDesert = { id = nil, category = "Ambient" },
		AmbientIce = { id = nil, category = "Ambient" },
		AmbientVolcano = { id = nil, category = "Ambient" },
		AmbientCyber = { id = nil, category = "Ambient" },

		-- --------------------------------------------------------- BOSSES
		-- Cada boss tiene su ciclo completo. El cambio de fase TIENE que
		-- sentirse: es el momento en que la dificultad cambia de verdad.
		BossSpawn = { id = nil, category = "Music" },
		BossIntro = { id = nil, category = "Voice" },
		BossTelegraph = { id = nil, category = "Voice" },
		BossAttack = { id = nil, category = "Voice" },
		BossSpecial = { id = nil, category = "Voice" },
		BossHurt = { id = nil, category = "Voice" },
		-- El cambio de fase es un evento MUSICAL, no un efecto: tiene que
		-- cambiar la cama de fondo, no solo sonar encima.
		BossPhaseChange = { id = nil, category = "Music" },
		BossDeath = { id = nil, category = "Music" },
		Victory = { id = nil, category = "Music" },
		Defeat = { id = nil, category = "Music" },
	} :: { [string]: { id: string?, category: string } },

	-- -------------------------------------------------------------------
	-- MUSICA POR ESTADO
	-- -------------------------------------------------------------------
	--
	-- La musica cambia segun donde este el jugador y que pase. Se declara
	-- como tabla y no como un `if` en el controller para que los estados
	-- que faltan se vean de un vistazo.
	--
	-- OJO: los valores son `false`, NO `nil`. En Lua una clave con valor
	-- `nil` no existe, asi que la tabla quedaria VACIA y no se podria ni
	-- enumerar ni comprobar. `false` significa "este estado todavia no
	-- tiene pista subida"; `nil` significaria "no existe este estado".
	-- Es la misma distincion que usa `WorldMusic` mas abajo.
	MusicByState = {
		Lobby = false,
		Exploring = false,
		Danger = false,
		Combat = false,
		Arena = false,
		Boss = false,
		Victory = false,
		Defeat = false,
	} :: { [string]: string | boolean },

	-- -------------------------------------------------------------------
	-- MEZCLA
	-- -------------------------------------------------------------------
	-- Volumen maestro de la musica (0..1). Baja de serie: la musica no
	-- debe tapar los efectos, que son los que dan feedback de gameplay.
	MusicVolume = 0.35,

	-- Volumen de los efectos (0..1).
	SfxVolume = 0.8,

	-- Segundos de desvanecido al cambiar de pista. Un corte seco entre
	-- lobby y arena se oye como un fallo.
	MusicFadeTime = 1.5,

	-- Tope de sonidos de efecto simultaneos. Sin este tope, veinte
	-- explosiones en cadena abren veinte `Sound` y el cliente se atasca.
	-- Es el mismo criterio de `PerformanceConfig.Limits.MaxVFX`.
	MaxConcurrentSfx = 12,
}
