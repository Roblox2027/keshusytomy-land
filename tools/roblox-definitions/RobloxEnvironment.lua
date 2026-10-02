--[[
	RobloxEnvironment.lua
	PRELUDE del analizador. NO es codigo del juego.

	POR QUE EXISTE
	--------------
	`luau-analyze.exe` (build standalone) se ejecuta SIN entorno de Roblox:
	no conoce `game`, `Instance`, `Vector3`, `task`, `RBXScriptSignal`...
	En ese build la configuracion externa tampoco es una salida: este
	analizador NO lee `.luaurc` (los alias y el bloque `lint` se ignoran,
	comprobado empiricamente) y NO soporta la palabra clave `declare`.

	Sin entorno, una sola causa raiz produce cientos de sintomas:
	`Unknown global 'warn'` arrastra `Type 'unknown' does not have key
	'FindFirstChild'`, que arrastra `Property _count ... is read-only`.
	Son 3 errores de definicion, no 600 defectos de codigo.

	LA REGLA (regla contra falsos positivos)
	----------------------------------------
	NO se modifica el codigo del juego para satisfacer al analizador.
	Se corrige la CONFIGURACION del analizador. Este archivo es esa
	configuracion: declara el entorno y nada mas.

	COMO SE APLICA
	--------------
	`tools/analyze.js` concatena este preludio delante de cada archivo
	real y ejecuta el analizador sobre el resultado. Las declaraciones
	de tipo se resuelven dentro del mismo archivo, y las asignaciones
	en el ambito superior convierten los nombres en globales reales.
	Verificado: las dos vias funcionan en este build.

	ALCANCE
	-------
	Se declara la SUPERFICIE que el proyecto usa, no las ~10.000 API
	del motor. Los miembros de Roblox se tipan como `any` a proposito:
	el tipado fino del motor no es el objetivo, y convertir el codigo
	propio del juego en `any` si lo seria. La logica del juego
	(modulos compartidos, servicios, calculos) sigue comprobandose
	con todo el rigor.
]]

--!nocheck

-- TIPOS ------------------------------------------------------------------
-- El codigo los usa en anotaciones (`--- @param p Vector3`). Si faltan,
-- el analizador los descarta en cascada y cada anotacion se vuelve
-- inutil.

export type Vector3 = any
export type Vector2 = any
export type Vector2int16 = any
export type CFrame = any
export type Color3 = any
export type UDim = any
export type UDim2 = any
export type Rect = any
export type BrickColor = any
export type NumberRange = any
export type NumberSequence = any
export type ColorSequence = any
export type TweenInfo = any
export type Random = any
export type Ray = any
export type Region3 = any
export type OverlapParams = any
export type RaycastParams = any
export type PathWaypoint = any
export type DateTime = any
export type EnumItem = any
export type Enum = any
export type Instance = any
export type Workspace = any
export type Part = any
export type BasePart = any
export type Model = any
export type Folder = any
export type Player = any
export type Teams = any
export type Team = any
export type GuiService = any
export type RunService = any
export type TweenService = any
export type UserInputService = any
export type ContextActionService = any
export type TextService = any
export type MarketplaceService = any
export type HttpService = any
export type DataStoreService = any
export type ReplicatedStorage = any
export type ServerScriptService = any

-- GLOBALES ----------------------------------------------------------------
-- Asignaciones en el ambito superior: esto es lo que las convierte en
-- globales reales para el resto del archivo.

game = nil :: any
workspace = nil :: any
script = nil :: any
shared = nil :: any
settings = nil :: any
plugin = nil :: any
debug = nil :: any

task = {
	spawn = (function(_: (...any) -> ()) end) :: any,
	delay = (function(_: number, _f: (...any) -> ()) end) :: any,
	wait = (function(_: number) end) :: any,
	defer = (function(_: (...any) -> ()) end) :: any,
	cancel = (function() end) :: any,
	desynchronize = (function() end) :: any,
	synchronize = (function() end) :: any,
} :: any

warn = (function(_: string) end) :: any
tick = (function() return 0 end) :: any
elapsedTime = (function() return 0 end) :: any

Instance = nil :: any
Vector3 = nil :: any
Vector2 = nil :: any
Vector2int16 = nil :: any
CFrame = nil :: any
Color3 = nil :: any
UDim = nil :: any
UDim2 = nil :: any
Rect = nil :: any
BrickColor = nil :: any
NumberRange = nil :: any
NumberSequence = nil :: any
ColorSequence = nil :: any
TweenInfo = nil :: any
Font = nil :: any
Random = nil :: any
Ray = nil :: any
Region3 = nil :: any
Region3int16 = nil :: any
OverlapParams = nil :: any
RaycastParams = nil :: any
DateTime = nil :: any
Enum = nil :: any

-- SIN `return` A PROPOSITO.
--
-- `analyze.js` concatena el archivo real DESPUES de este preludio. Un
-- `return` aqui dejaria el codigo del juego despues de un `return`, es
-- decir en zona inalcanzable: el analizador lo(parseaba, lo ignoraba y
-- reportaba `Unknown global 'game'` aunque el preludio lo declarara tres
-- lineas mas arriba. Medido: quitar el `return` bajo las incidencias de
-- `Unknown global` de 91 a 0.
--
-- El preludio no necesita devolver nada: solo declara el entorno.

export type StarterGui = any
export type StarterPlayer = any
export type Lighting = any
export type SoundService = any
export type Debris = any
export type RemoteEvent = any
export type RemoteFunction = any
export type ScreenGui = any
export type Frame = any
export type TextLabel = any
export type TextButton = any
export type TextBox = any
export type ImageLabel = any
export type ImageButton = any
export type Humanoid = any
export type Sound = any
export type Accessory = any
export type Tool = any
export type Chat = any
export type PathfindingService = any
export type RBXScriptSignal = any
export type RBXScriptConnection = any
export type RBXScript = any
export type RBXInstance = any
