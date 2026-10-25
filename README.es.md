# Sandy

<img src="Resources/AppIcon.png" alt="Sandy" width="160">

[English](README.md) · [Русский](README.ru.md) · [Қазақша](README.kk.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md)

Guía completa: [English](README.md) · [Русский](README.ru.md).
El acceso desde el teléfono aún está previsto. Sandy se basa en
[Cyclop](https://github.com/akalikbergenov/cyclop), con licencia MIT.

Una aplicación nativa de macOS que convierte la muesca del MacBook en un espacio
de trabajo. Acerca el puntero a la muesca para abrir los controles multimedia,
el estante de archivos, el historial del portapapeles, los fragmentos de texto,
el calendario, la traducción, la conversión de divisas, el teleprónter y las notas.

La pestaña **Agentes** supervisa las sesiones compatibles de Claude Code y Codex
mediante el auxiliar local `sandy-agent`. Muestra sesiones simultáneas, operaciones
actuales y estadísticas guardadas por proyecto. Las notificaciones de respuesta
lista, solicitud de entrada y error son opcionales. Activa el seguimiento y las
fuentes en Ajustes; los hooks de Claude solo se instalan con el botón específico.
Consulta la configuración y las limitaciones en [seguimiento de agentes](docs/agent-monitor.md)
(en ruso).

Abdirakhym mantiene Sandy. El proyecto comienza en la versión **0.1.0** con un
historial de Git independiente. Las atribuciones del código de terceros se recogen
en `THIRD_PARTY_NOTICES.md`.

## Idiomas

La interfaz está disponible en inglés, ruso, kazajo, alemán, francés, español y
chino simplificado y japonés. Elige el idioma en Ajustes → General → Idioma; el panel cambia
al instante. «Idioma del sistema» sigue la preferencia de macOS. Los diálogos de
permisos del sistema cambian de idioma después de reiniciar Sandy.
El idioma de la interfaz no cambia el par de idiomas de la pestaña «Traducir».

## Atajo de teclado

Pulsa **Control + Option + Espacio** para abrir el panel en la pantalla donde está
el puntero. Pulsa de nuevo el atajo, Esc o haz clic en otra aplicación para cerrarlo.
El panel permanece abierto mientras lo usas con el teclado. En Ajustes → General
puedes elegir otra combinación o desactivar el atajo. Esta función no necesita
permiso de accesibilidad.

## Compilar y ejecutar

Requiere macOS 15 o posterior y Swift 6. Las Xcode Command Line Tools son suficientes.
Desde la carpeta del proyecto:

```sh
./Scripts/bundle.sh
open build/Sandy.app
```

La compilación local usa una firma ad hoc. Para publicar una versión firmada con
Developer ID y notarizada por Apple necesitas tus propias credenciales de Apple
Developer; consulta [la firma](docs/signing.md) (en ruso).

```sh
./Scripts/test.sh        # Comprobar las pruebas y las traducciones
./Scripts/test-helper.sh # Comprobar el auxiliar multimedia tras compilar
./Scripts/dmg.sh         # Crear build/Sandy-0.1.0.dmg
```

La versión se define en `Scripts/version`. Configura tu propio repositorio remoto
antes de usar `Scripts/release.sh`.

## Datos y permisos

- Identificador de la aplicación: `com.abdirakhym.sandy`.
- Ajustes, fragmentos y notas: `~/Library/Application Support/Sandy`.
- Capturas del portapapeles: `~/Pictures/Sandy`.
- El calendario y el bloqueo del teclado solicitan acceso al calendario y a
  accesibilidad cuando se usan las funciones correspondientes.
- El permiso para las notificaciones de agentes se solicita solo al activarlas.
  El historial permanece en `~/Library/Application Support/Sandy/Agents/history.json`;
  la interfaz de seguimiento no almacena los prompts ni las respuestas.
- La traducción utiliza el framework Translation de macOS y los paquetes de idiomas descargados.
- El conversor obtiene tipos de cambio públicos. El mecanismo alternativo de Spotify
  puede descargar carátulas. Las estadísticas de agentes permanecen en este Mac;
  no hay telemetría ni servicio de actualización automática.

Sandy usa sus propios ajustes y almacenamiento. Los datos de otra aplicación no
se importan automáticamente. Más información: [SECURITY.md](SECURITY.md) (en ruso).

## Desarrollo

El código SwiftUI y AppKit está en `Sources/Sandy`, y el auxiliar multimedia en
`Sources/SandyMediaHelper`. Las traducciones y el icono están en `Resources`,
y los scripts de compilación y empaquetado en `Scripts`.

Antes de cambiar el comportamiento, lee [la arquitectura](docs/architecture.md)
(en inglés), [la guía de contribución](CONTRIBUTING.md) y [la lista de comprobación
de versiones](docs/release-checklist.md) (en ruso). Now Playing usa un framework
privado de macOS y un auxiliar Perl del sistema; futuras versiones de macOS pueden
requerir adaptaciones. La aplicación no es apta para distribuirse en el App Store.

## Licencia

[MIT](LICENSE). Conserva la licencia y los avisos del código de terceros al
distribuir las fuentes o la aplicación. Los documentos incluidos en el paquete
se encuentran en `Sandy.app/Contents/Resources`.
