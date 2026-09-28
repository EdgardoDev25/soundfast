# SoundFast

Reproductor de música nativo para iPhone (SwiftUI). Se desarrolla **sin Mac**:
se compila en la nube (GitHub Actions o Codemagic) y se instala desde Windows
con un Apple ID gratuito.

## Estructura

| Ruta | Qué es |
|---|---|
| `SoundFast/` | Código Swift de la app |
| `project.yml` | Definición del proyecto; XcodeGen genera el `.xcodeproj` al compilar |
| `scripts/build-ipa.sh` | Compila sin firmar y deja `build/SoundFast.ipa` |
| `.github/workflows/build-ios.yml` | Compilación en GitHub Actions (cada push a `main`, o manual) |
| `codemagic.yaml` | Compilación en Codemagic (manual desde su panel) |
| `prototipo/` | Prototipo original de Claude Design (solo referencia visual) |

## Obtener el .ipa

**GitHub Actions:** pestaña *Actions* → *Compilar iOS* → última ejecución →
sección *Artifacts* → `SoundFast-build-N`. Se descarga un `.zip`; adentro está
`SoundFast.ipa`.

**Codemagic:** panel de la app → *Start new build* → workflow
*SoundFast iOS (sin firmar)* → al terminar, descargar `SoundFast.ipa`.

## Instalar en el iPhone (Windows, Apple ID gratis)

Requisitos una sola vez en el PC: **iTunes** e **iCloud** instalados desde la
web de Apple (no la versión de Microsoft Store) y **Sideloadly**
(sideloadly.io).

1. Conectar el iPhone por cable y aceptar "Confiar en este ordenador".
2. Abrir Sideloadly, arrastrar `SoundFast.ipa`, escribir el Apple ID y darle *Start*.
3. Primera vez en el iPhone:
   - Ajustes → General → VPN y gestión de dispositivos → confiar en tu Apple ID.
   - Ajustes → Privacidad y seguridad → **Modo de desarrollador** → activar y reiniciar.

**La firma gratuita vence a los 7 días.** Para renovarla, volver a instalar el
mismo `.ipa` con Sideloadly (los datos de la app se conservan). Con AltStore y
AltServer abierto en el PC, la renovación es automática por WiFi.

Límites del Apple ID gratis: 3 apps instaladas así a la vez y 10 App IDs por semana.

## Etapas

1. ✅ Base: cadena compilar → firmar → instalar, más una prueba de audio en segundo plano.
2. Biblioteca y reproducción (importar canciones, cola, pantalla de bloqueo).
3. Pantallas del prototipo (biblioteca, Sonando ahora, listas, favoritos, buscador).
4. Sonido: ecualizador de 10 bandas, graves, crossfade.
5. Ajustes y apariencia.
