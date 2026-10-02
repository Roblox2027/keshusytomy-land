// build-probe-rbxm.js
// Genera un `.rbxm` minimo con UNA Part bien formada.
//
// POR QUE EXISTE
// --------------
// Cuando la geometria llega a Studio sin su posicion, hay que distinguir si
// el fallo esta en la GENERACION del `.rbxm` o en la IMPORTACION de Studio.
// Probarlo con el mapa entero no sirve: cualquier fallo contaminaria el
// resultado y no se podria atribuir la causa.
//
// Este archivo lleva una sola Part, con las mismas propiedades que usa el
// generador real (`Position`, `size` en minuscula, `Color3uint8`). Si al
// importar aparece en su sitio, la importacion funciona y el problema es del
// mapa; si aparece en el origen, el problema es del `.rbxm`.
//
// Uso:
//   node tools/build-probe-rbxm.js .cache/probe.rbxm

const fs = require("fs");
const path = require("path");

const out = process.argv[2] || path.join(__dirname, "..", ".cache", "probe.rbxm");

// Se escribe a mano el XML, con las MISMAS claves que produce Rojo, para que
// la prueba mida el formato real y no una idealizacion.
const xml = `<roblox version="4">
  <Item class="Folder">
    <Properties>
      <string name="Name">ProbeRoot</string>
    </Properties>
    <Item class="Part" referent="1">
      <Properties>
        <string name="Name">ProbePart</string>
        <bool name="Anchored">true</bool>
        <bool name="CanCollide">true</bool>
        <bool name="CanTouch">false</bool>
        <token name="Material">816</token>
        <Vector3 name="size">
          <X>8</X>
          <Y>8</Y>
          <Z>8</Z>
        </Vector3>
        <token name="Transparency">0.4</token>
      </Properties>
    </Item>
  </Item>
</roblox>
`;

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, xml, "utf8");
console.log("probe escrito en " + out);
