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
	CoinRewardId = nil :: string,

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