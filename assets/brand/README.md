# Recursos de marca — Mavric

Archivos que van en esta carpeta. Todos son PNG con **fondo transparente**
y recortados sin márgenes sobrantes (que el arte toque los bordes), porque
se muestran muy chicos y cualquier aire extra los achica todavía más.

| Archivo | Qué es | Dónde se usa |
|---|---|---|
| `mavric-logo-light.png` | Logotipo completo (hexágono + "MAVRIC TECHNOLOGIES") en azul oscuro | Pantalla de carga, tema claro |
| `mavric-logo-dark.png` | El mismo logotipo con el texto en blanco/claro | Pantalla de carga, tema oscuro |
| `mavric-mark-light.png` | Solo el hexágono, versión para fondos claros (cuadrado) | Pie de página, tema claro |
| `mavric-mark-dark.png` | Solo el hexágono, versión para fondos oscuros (cuadrado) | Pie de página, tema oscuro |

Medidas sugeridas: logotipo ~1200×300 px, isotipo ~256×256 px.

Si falta alguno, la app no se rompe: `BrandImage` prueba el siguiente
candidato y, si no hay ninguno, muestra solo el texto.
