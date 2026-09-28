# SoundFast — Estado del proyecto

Qué quedó integrado en la app, qué no y qué se descartó.
Última versión: **0.5.0 (build 8)** · 2026-09-28 · iPhone 16 Pro Max.

**Leyenda**
- ✅ Integrado y confirmado por Edgar en el iPhone
- 🧪 Integrado y compilado, **sin prueba confirmada** en el iPhone
- ⏳ Pendiente (se quiere hacer)
- 🚫 Descartado o fuera del alcance por ahora

---

## 1. Base y cadena de compilación

| Qué | Estado | Nota |
|---|---|---|
| App nativa SwiftUI (sin Mac) | ✅ | iOS 17 o superior. Proyecto definido con XcodeGen (`project.yml`). |
| Compilación en GitHub Actions | ✅ | Cada push a `main` genera `SoundFast.ipa` sin firmar. Repositorio público: compilaciones ilimitadas. |
| Compilación en Codemagic | ✅ | Queda de respaldo (`codemagic.yaml`), manual desde su panel. |
| Instalación con Sideloadly y Apple ID gratis | ✅ | Hay que reinstalar cada 7 días; los datos se conservan. |
| Errores de compilación visibles como avisos en GitHub | ✅ | Claude los lee sin iniciar sesión. |
| Renovación automática de la firma (AltStore/SideStore) | ⏳ | Anotado en los pendientes de Edgar. |
| Cuenta Apple Developer + TestFlight (sin modo desarrollador, 90 días) | ⏳ | En evaluación (USD 99/año). Codemagic puede subir a TestFlight sin Mac. |

## 2. Meter canciones

| Qué | Estado | Nota |
|---|---|---|
| Importar archivos (MP3, M4A, AAC, FLAC, WAV, AIFF) desde Archivos o iCloud | ✅ | Botón `+` en Canciones. Se copian a la carpeta de la app. |
| Carpeta **SoundFast** visible en Archivos y en "Dispositivos Apple" de Windows | ✅ | Confirmado: lo importado aparece ahí. |
| Botón **Actualizar** en la biblioteca | ✅ | Avisa cuántas canciones nuevas encontró o cuántas se quitaron. |
| Actualización automática al volver a la app | 🧪 | |
| Biblioteca de Música del iPhone (canciones descargadas o pasadas con iTunes) | 🧪 | Solo las que no tienen DRM. |
| "Abrir en SoundFast" desde otras apps (WhatsApp, Telegram…) | 🧪 | |
| Canciones de Apple Music por suscripción | 🚫 | Tienen DRM: iOS no deja pasarlas por el ecualizador. |

## 3. Biblioteca

| Qué | Estado | Nota |
|---|---|---|
| Pestañas Canciones, Favoritos y Listas | ✅ | |
| Buscador por título, artista o álbum | ✅ | El teclado se cierra al abrir una canción. |
| Índice A–Z lateral con vibración | ✅ | Solo con orden por título ascendente. |
| Ordenar por título, artista, álbum, fecha o duración, ascendente o descendente | ✅ | Menú en la biblioteca y también en Ajustes. |
| Fila Reproducir / Aleatorio / Ordenar / Actualizar que se oculta con el scroll | ✅ | |
| Duración total en horas y minutos ("3 h 40 min") | ✅ | |
| Encabezado "SoundFast - Edgardo Rocha" | ✅ | |
| Deslizar una fila: a continuación, favorito o añadir a lista | ✅ | |
| Menú al mantener presionada una canción | ✅ | A continuación, cola, favorito, lista, editar información, portada, eliminar. |
| Eliminar del iPhone una canción importada | 🧪 | Pide confirmación. |
| Crear, renombrar y eliminar listas | ✅ | |
| Reordenar canciones dentro de una lista (botón **Ordenar**) | 🧪 | |
| Centrar la canción que suena al volver de la reproducción (como Poweramp) | ✅ | |

## 4. Reproducción

| Qué | Estado | Nota |
|---|---|---|
| Reproducir, pausar, anterior y siguiente | ✅ | |
| Aleatorio y repetir (todas o una) | ✅ | |
| Cola "A continuación" con reordenar y quitar | 🧪 | |
| Sonido en segundo plano y con el iPhone bloqueado | ✅ | |
| Pantalla de bloqueo, Centro de Control, Dynamic Island y widget | ✅ | Con portada y barra de posición. |
| Pausa al desconectar audífonos | 🧪 | |
| Reanudar al conectar audífonos (opcional) | 🧪 | |
| Pausa y reanudación con llamadas, alarmas y Siri | 🧪 | |
| Salida de audio: AirPlay o Bluetooth | 🧪 | Botón en la reproducción y en Ajustes. |
| Recordar la canción, la posición y la cola al reabrir la app | ✅ | |
| Fundido entre canciones al terminar solas (0–12 s) | ✅ | Confirmado: se siente suave. |
| Fundido al cambiar de canción a mano | ✅ | La canción actual sigue completa hasta que la nueva está lista y ahí se cruzan. |
| Reproducción sin pausas (gapless) | 🧪 | Solo entre canciones del mismo formato. |
| Normalizar volumen entre canciones | 🧪 | Mide cada canción una sola vez en segundo plano. Sube hasta +8 dB y baja hasta −9 dB. |
| Sin vibración al pasar canción | ✅ | |
| Cierre de la app al cambiar de canción (0.4 y 0.4.1) | ✅ | Corregido en 0.4.2. |

## 5. Pantalla "Sonando ahora"

| Qué | Estado | Nota |
|---|---|---|
| Portada grande con forma elegible (redonda, recta o disco) | ✅ | |
| Deslizar la portada para cambiar de canción | ✅ | El audio cambia al soltar; la portada vieja sale con su imagen. |
| Bajar deslizando para cerrar, fluido y sin saltos | ✅ | Resorte según la velocidad del dedo. |
| Barra de progreso tipo onda con la forma real de la canción | ✅ | |
| Onda que late con la música y punto de posición | ✅ | |
| Barra de progreso tipo línea (opcional) | ✅ | |
| Adelantar arrastrando la onda, con indicador sobre la portada | ✅ | |
| Adelantar deslizando el minirreproductor | ✅ | |
| Título y artista con fundido al cambiar | ✅ | |
| Botones de vidrio y fila A lista / Sonido / Efectos / Cola | ✅ | |
| Editar información y buscar portada desde el título (mantener presionado) | 🧪 | |

## 6. Efectos de fondo

| Qué | Estado | Nota |
|---|---|---|
| 7 estilos: Aurora, Líquido, Ondas, Partículas, Espectro, Remolino y **Anillo** (tipo JBL) | ✅ | |
| Reaccionan a la música (análisis del audio en tiempo real) | ✅ | |
| Paletas: Portada (colores reales de la carátula), Acento, Arcoíris, Fuego, Océano, Neón | ✅ | |
| Intensidad, velocidad y encender/apagar desde la misma pantalla | ✅ | La hoja se cierra tocando por fuera. |
| Pausa del efecto con la pantalla cerrada (ahorra batería) | ✅ | |

## 7. Sonido

| Qué | Estado | Nota |
|---|---|---|
| Perillas de graves y agudos (giro circular o arrastre, halo al operarlas) | ✅ | Corregido con toque nativo de iOS. |
| Graves hasta **+36 dB** (dos campanas y un estante) | ✅ | Aviso desde el 70 %: puede bajar el resto o distorsionar. |
| Agudos hasta +8 dB | ✅ | |
| Punto de graves 40 / 60 / 80 / 120 Hz con descripción | ✅ | |
| Ecualizador de 10 bandas con curva en vivo | ✅ | |
| 7 presets (Plano, Rock, Pop, Electrónica, Vocal, Acústica, Noche) | ✅ | |
| Limitador contra saturación | ✅ | |

## 8. Apariencia

| Qué | Estado | Nota |
|---|---|---|
| Fuente Montserrat | ✅ | Se registra al arrancar; si fallara, usa la del sistema. Diagnóstico en Ajustes → Acerca de. |
| 8 colores de acento | ✅ | |
| Temas OLED, Grafito, Noche, Cálido y **Cristal** | ✅ | |
| Cristal con Liquid Glass de iOS 26 y "gota" al tocar | ✅ | En iOS anteriores queda vidrio esmerilado. |
| Desenfoque del vidrio ajustable | ✅ | |
| Barra superior de vidrio y barra inferior flotante | ✅ | |
| Fondo de la reproducción (portada suave, intenso o tema) | ✅ | |
| Botón de reproducir en círculo o cuadrado | ✅ | |
| Vibración (activable) | ✅ | |
| Sonido y Ajustes que se cierran deslizando, con el minirreproductor visible | ✅ | |
| Ícono de la app y "Desarrollado por Edgardo Rocha" (enlace a edgfast.com) en Ajustes | ✅ | |

## 9. Portadas e información de canciones

| Qué | Estado | Nota |
|---|---|---|
| Portadas incluidas en los archivos | ✅ | |
| Buscar y elegir la portada de una canción en internet | 🧪 | Usa el buscador público de iTunes. |
| Descargar todas las portadas que faltan | 🧪 | Unas 20 consultas por minuto (límite de Apple); se puede detener. |
| Portada desde Fotos | 🧪 | |
| Editar título, artista, álbum, género, año y pista | 🧪 | Se guarda en SoundFast; **el archivo no se modifica**. |

---

## ⏳ Pendiente o por optimizar

- Renovación automática de la firma, o TestFlight (ver sección 1).
- Detalles de optimización que Edgar anotará "con calma".
- Escribir la información editada dentro del archivo de audio: hoy solo queda en SoundFast.

## 🚫 Descartado por ahora

- Letras sincronizadas.
- Temporizador para dormir.
- PWA o app web: Edgar quiere solo app nativa.

## Del prototipo que no pasó a la app

| En el prototipo | Qué pasó |
|---|---|
| Vistas simuladas (pantalla de bloqueo, Centro de Control, primer inicio) | Reemplazadas por las reales de iOS. |
| Opción "Controles en pantalla de bloqueo" | Quitada: en iOS salen siempre. |
| "Caché de portadas" y "Borrar caché" | Quitadas: no aportan en la app real. |
| "Privacidad" y "Enviar comentarios" | Quitadas: app de uso personal. |
| Marco de celular 390×844 | Quitado: la app usa la pantalla real del 16 Pro Max. |

## Historial de versiones

| Versión | Build | Qué trajo |
|---|---|---|
| 0.1 | 1 | Base: compilar en la nube → firmar → instalar. |
| 0.2 | 2 | Reproductor completo según el prototipo. |
| 0.2 | 3 | Arreglo de perillas y portada deslizable. |
| 0.3 | 4 | Montserrat, tema Cristal, efectos, orden y actualizar, reordenar listas, gesto fluido. |
| 0.4 | 5 | Perillas nativas, paneles deslizables, Liquid Glass, +18 dB, normalizar, efecto Anillo, portadas. |
| 0.4.1 | 6 | Cambio manual suave, +24 dB, registro de fuentes, centrar canción. |
| 0.4.2 | 7 | Arreglo del cierre al cambiar de canción. |
| 0.5 | 8 | Vidrio en barras y reproducción, editar información, +36 dB. |
