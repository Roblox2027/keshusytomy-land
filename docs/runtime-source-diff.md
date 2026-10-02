# SOURCE <-> RUNTIME

> **ESTADO: DIVERGE — esperado; no es un fallo del generador.**
>
> El source subio a **264 instancias** al sustituir el placeholder de cuatro
> sectores por el lobby real (Keshusy Core, portales, estaciones, farolas).
> Studio conserva el arbol anterior porque **el plugin de Rojo no esta
> conectado**: `rojo serve` responde 200 en `/`, pero
> `/api/active-project` devuelve **404** (sin sesion).
>
> Para cerrar la diferencia:
> `Roblox Studio -> Plugins -> Rojo -> Connect -> 34872`
>
> MCP no puede ejecutar ese clic. Al conectar, el sync baja las 90
> instancias y el gate vuelve a PASS sin tocar el source.

SOURCE (rojo build) : 264 instancias
RUNTIME (Studio MCP): 184 instancias

FALTAN EN STUDIO (en source, no en runtime): 90
SOBRAN EN STUDIO (en runtime, no en source): 0
CLASE DISTINTA                          : 0

## Faltan en Studio

- Workspace.Lobby.CoreBase [Part]
- Workspace.Lobby.CoreDais [Part]
- Workspace.Lobby.CoreGlow [Part]
- Workspace.Lobby.CoreOrb [Part]
- Workspace.Lobby.CorePillarLight_0 [Part]
- Workspace.Lobby.CorePillarLight_1 [Part]
- Workspace.Lobby.CorePillarLight_2 [Part]
- Workspace.Lobby.CorePillarLight_3 [Part]
- Workspace.Lobby.CorePillar_0 [Part]
- Workspace.Lobby.CorePillar_1 [Part]
- Workspace.Lobby.CorePillar_2 [Part]
- Workspace.Lobby.CorePillar_3 [Part]
- Workspace.Lobby.CorePlinth [Part]
- Workspace.Lobby.CoreRing_A [Part]
- Workspace.Lobby.CoreRing_B [Part]
- Workspace.Lobby.LampGlow_0 [Part]
- Workspace.Lobby.LampGlow_1 [Part]
- Workspace.Lobby.LampGlow_2 [Part]
- Workspace.Lobby.LampGlow_3 [Part]
- Workspace.Lobby.LampGlow_4 [Part]
- Workspace.Lobby.LampGlow_5 [Part]
- Workspace.Lobby.LampGlow_6 [Part]
- Workspace.Lobby.LampGlow_7 [Part]
- Workspace.Lobby.Lamp_0 [Part]
- Workspace.Lobby.Lamp_1 [Part]
- Workspace.Lobby.Lamp_2 [Part]
- Workspace.Lobby.Lamp_3 [Part]
- Workspace.Lobby.Lamp_4 [Part]
- Workspace.Lobby.Lamp_5 [Part]
- Workspace.Lobby.Lamp_6 [Part]
- Workspace.Lobby.Lamp_7 [Part]
- Workspace.Lobby.Portal_Cyber_Base [Part]
- Workspace.Lobby.Portal_Cyber_Glow [Part]
- Workspace.Lobby.Portal_Cyber_Lintel [Part]
- Workspace.Lobby.Portal_Cyber_Panel [Part]
- Workspace.Lobby.Portal_Cyber_PostL [Part]
- Workspace.Lobby.Portal_Cyber_PostR [Part]
- Workspace.Lobby.Portal_Cyber_Sign [Part]
- Workspace.Lobby.Portal_Desert_Base [Part]
- Workspace.Lobby.Portal_Desert_Glow [Part]
- Workspace.Lobby.Portal_Desert_Lintel [Part]
- Workspace.Lobby.Portal_Desert_Panel [Part]
- Workspace.Lobby.Portal_Desert_PostL [Part]
- Workspace.Lobby.Portal_Desert_PostR [Part]
- Workspace.Lobby.Portal_Desert_Sign [Part]
- Workspace.Lobby.Portal_Forest_Base [Part]
- Workspace.Lobby.Portal_Forest_Glow [Part]
- Workspace.Lobby.Portal_Forest_Lintel [Part]
- Workspace.Lobby.Portal_Forest_Panel [Part]
- Workspace.Lobby.Portal_Forest_PostL [Part]
- Workspace.Lobby.Portal_Forest_PostR [Part]
- Workspace.Lobby.Portal_Forest_Sign [Part]
- Workspace.Lobby.Portal_Ice_Base [Part]
- Workspace.Lobby.Portal_Ice_Glow [Part]
- Workspace.Lobby.Portal_Ice_Lintel [Part]
- Workspace.Lobby.Portal_Ice_Panel [Part]
- Workspace.Lobby.Portal_Ice_PostL [Part]
- Workspace.Lobby.Portal_Ice_PostR [Part]
- Workspace.Lobby.Portal_Ice_Sign [Part]
- Workspace.Lobby.Portal_Volcano_Base [Part]
- Workspace.Lobby.Portal_Volcano_Glow [Part]
- Workspace.Lobby.Portal_Volcano_Lintel [Part]
- Workspace.Lobby.Portal_Volcano_Panel [Part]
- Workspace.Lobby.Portal_Volcano_PostL [Part]
- Workspace.Lobby.Portal_Volcano_PostR [Part]
- Workspace.Lobby.Portal_Volcano_Sign [Part]
- Workspace.Lobby.Station_Events_Lamp [Part]
- Workspace.Lobby.Station_Events_Pad [Part]
- Workspace.Lobby.Station_Events_Post [Part]
- Workspace.Lobby.Station_Inventory_Lamp [Part]
- Workspace.Lobby.Station_Inventory_Pad [Part]
- Workspace.Lobby.Station_Inventory_Post [Part]
- Workspace.Lobby.Station_Missions_Lamp [Part]
- Workspace.Lobby.Station_Missions_Pad [Part]
- Workspace.Lobby.Station_Missions_Post [Part]
- Workspace.Lobby.Station_Party_Lamp [Part]
- Workspace.Lobby.Station_Party_Pad [Part]
- Workspace.Lobby.Station_Party_Post [Part]
- Workspace.Lobby.Station_Rankings_Lamp [Part]
- Workspace.Lobby.Station_Rankings_Pad [Part]
- Workspace.Lobby.Station_Rankings_Post [Part]
- Workspace.Lobby.Station_Season_Lamp [Part]
- Workspace.Lobby.Station_Season_Pad [Part]
- Workspace.Lobby.Station_Season_Post [Part]
- Workspace.Lobby.Station_Shop_Lamp [Part]
- Workspace.Lobby.Station_Shop_Pad [Part]
- Workspace.Lobby.Station_Shop_Post [Part]
- Workspace.Lobby.Station_Training_Lamp [Part]
- Workspace.Lobby.Station_Training_Pad [Part]
- Workspace.Lobby.Station_Training_Post [Part]
