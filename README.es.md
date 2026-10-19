<div align="center">
  <img src="DyNotch/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="140" alt="Icono de DyNotch">
  <h1>DyNotch</h1>
  <p><strong>Una Dynamic Island para el notch de tu MacBook.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26%2B-blue" alt="macOS 26+">
    <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
    <img src="https://img.shields.io/badge/SwiftUI-Liquid%20Glass-8A2BE2" alt="SwiftUI + Liquid Glass">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="Licencia MIT">
  </p>
  <p>🇬🇧 <a href="README.md">Read in English</a></p>
</div>

---

DyNotch convierte el notch del MacBook en una Dynamic Island. Pasa el puntero por encima y se abre: lo que suena, el calendario, el tiempo, temporizadores, un estante para archivos y más. También sustituye el indicador de volumen y brillo del sistema, y muestra actividades en directo (carga, AirPods, concentración, temporizadores) justo al lado del notch.

## Instalación

Descarga el último `.dmg` desde la [página de Releases](https://github.com/juancarloslopez3/DyNotch/releases), ábrelo y arrastra **DyNotch** a tu carpeta Aplicaciones. Más adelante, **Buscar actualizaciones** en Ajustes › Acerca de te avisa cuando sale una versión nueva.

DyNotch es un agente de la barra de menús: tras abrirlo, búscalo en el notch y en la barra de menús, no en el Dock. Una visita de bienvenida te guía por los permisos y te hace probar el notch de verdad.

> [!IMPORTANT]
> La app está firmada localmente y no con un certificado de pago de Apple Developer, así que macOS bloquea la primera apertura. Para permitirla: abre **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el aviso sobre DyNotch y pulsa **Abrir igualmente**. Solo hace falta hacerlo una vez por versión.
>
> Por el mismo motivo, macOS deja de respetar los permisos de **Accesibilidad** y **Acceso total al disco** después de cada actualización: los interruptores siguen activados, pero el indicador y el estado de Concentración avisan de que vuelven a necesitar acceso. Abre **Ajustes › Permisos** en DyNotch, que borra la entrada caducada y te guía para volver a permitirlo.

## Funciones

- **Ábrelo a tu manera** — pasa el puntero por el notch (o haz clic; lo eliges en Ajustes) para abrirlo, o desliza dos dedos hacia abajo sobre él; desliza hacia arriba para cerrarlo. Desliza tres dedos (o dos) hacia la izquierda o la derecha para moverte entre pestañas. Una ligera respuesta háptica del trackpad confirma cada apertura.
- **Pestaña Inicio** — hasta tres columnas de widgets: En reproducción, Reloj, Tiempo, Calendario, Recordatorios, Batería y Temporizador, cada uno grande o pequeño y en el orden que quieras.
- **Editor de disposición** — Ajustes › Disposición muestra una vista previa en directo del notch: arrastra widgets entre columnas, a la bandeja para quitarlos y de vuelta para añadirlos, mueve las pestañas hacia los lados y haz clic derecho en un widget para cambiar su tamaño. Oculta las pestañas que no uses y elige en cuál se abre.
- **En reproducción** — funciona con cualquier app (Música, Spotify, navegadores…): portada, barra de progreso, reproducir, pausar y saltar. Mientras suena música, la portada del álbum y una forma de onda se colocan junto al notch; la onda se mueve con el audio que de verdad está sonando, en un degradado con los colores de la portada.
- **Indicador de volumen y brillo** — sustituye el indicador del sistema para el volumen, el brillo de la pantalla y la retroiluminación del teclado por uno en el notch que puedes arrastrar. <kbd>⇧⌥</kbd> ajusta en pasos más pequeños, y mantener pulsada <kbd>⌃</kbd> con las teclas de brillo cambia la retroiluminación del teclado (muy útil en los MacBook sin teclas de retroiluminación).
- **Monitores externos** — las teclas de brillo también ajustan las pantallas externas: las de Apple, como hace macOS, y los demás monitores por DDC/CI (como MonitorControl). Ajustan la pantalla en la que está el puntero o todas a la vez, y Ajustes › Volumen y brillo tiene un regulador para cada pantalla.
- **Calendario y Recordatorios** — el mes de un vistazo, con hoy en un círculo y puntos con los colores de tus calendarios en los días con eventos; haz clic para darle la vuelta y ver los próximos eventos de la semana. Marca los recordatorios de hoy y los vencidos.
- **Unirse a reuniones** — se detectan los enlaces de Zoom, Meet, Teams, Webex y FaceTime de tus eventos, y aparece un aviso *Unirse* 5 minutos antes y al empezar.
- **Tiempo** — condiciones actuales, máxima y mínima, y las próximas horas, de Open-Meteo (licencia abierta), para tu ubicación actual o cualquier ciudad que busques.
- **Reloj** — hora y fecha en grande y hasta dos relojes mundiales; la hora también puede mostrarse junto al notch en reposo.
- **Estante y AirDrop** — arrastra archivos hacia el notch y suéltalos en **Estante** para dejarlos aparcados o en **AirDrop** para enviarlos. El Estante funciona como una ventana del Finder: selecciona, usa Vista rápida, copia, reordena, vuelve a sacar los ítems arrastrándolos, compártelos o haz clic derecho para ver más opciones.
- **Temporizadores** — temporizador con valores predefinidos, cronómetro con vueltas y Pomodoro. Mientras funcionan, un anillo y la cuenta atrás se colocan junto al notch. Activa *Sonar hasta detenerlo* y sonará como el temporizador del iPhone.
- **Espejo de cámara** — una vista previa rápida de la webcam; haz clic para alternar entre verte como en un espejo y como te ven los demás. La cámara se apaga en cuanto se cierra el notch.
- **Actividades en directo** — cargador conectado o desconectado, batería baja, carga completa, dispositivos Bluetooth con su batería, concentración activada o desactivada y Bloq Mayús. Los AirPods tienen su propia animación al conectarse, con un anillo de batería para cada auricular y el estuche.
- **Dos a la vez** — como la Dynamic Island del iPhone: inicia un temporizador mientras suena música y la música conserva su sitio junto al notch mientras la cuenta atrás se separa en una burbuja propia, que vuelve a fundirse con él cuando termina. Haz clic en la burbuja para abrir su pestaña.
- **Todas las pantallas** — usa el notch real de la pantalla integrada, puede dibujar un notch virtual en las pantallas externas y mantiene las actividades en directo (temporizadores, música…) sobre las apps a pantalla completa, o se oculta en ellas si lo prefieres (los indicadores se siguen mostrando).

## Permisos

**Permitir todo**, en la visita de bienvenida y en Ajustes › Permisos, pide uno por uno cada permiso que falte. Accesibilidad y Acceso total al disco solo se pueden conceder en Ajustes del Sistema, así que DyNotch abre allí la lista correcta con una guía bajo la ventana: arrastra el icono de DyNotch a la lista. Cualquier ajuste que necesite un permiso lo indica justo debajo, con un botón para permitirlo.

| Permiso | Para qué se usa | ¿Necesario? |
|---|---|---|
| Accesibilidad | Interceptar las teclas de volumen, brillo y Bloq Mayús para sustituir el indicador del sistema | Obligatorio para los indicadores |
| Calendarios, Recordatorios | Tarjeta de agenda, unirse a reuniones | Opcional |
| Localización | Tiempo local (o elige una ciudad) | Opcional |
| Cámara | Pestaña del espejo de cámara | Opcional |
| Bluetooth | Avisos al conectarse dispositivos | Opcional |
| Notificaciones | Avisos de los temporizadores cuando no estás mirando | Opcional |
| Grabación de audio del sistema | Forma de onda que se mueve con la música (si no, una animación genérica) | Opcional |
| Acceso total al disco | Leer el estado de concentración y acceso completo para el estante | Opcional |

## Privacidad

- **Todo se queda en tu Mac.** Sin cuentas ni analíticas. Las únicas peticiones de red son las del tiempo: tus coordenadas (o el nombre de la ciudad que busques) van a Open-Meteo. **Buscar actualizaciones**, en Ajustes › Acerca de, pregunta a GitHub por la última versión, solo cuando lo pulsas.
- **No se graba nada.** La forma de onda de la música analiza el audio del sistema en seis bandas y descarta las muestras al instante. macOS muestra su punto morado de grabación mientras la forma de onda está en pantalla; desactívala en Ajustes › En reproducción › *Las barras se mueven con la música*.
- **La cámara, solo cuando miras.** El espejo solo funciona mientras está en pantalla y se detiene en cuanto se cierra el notch.

## Gestos y atajos

| Acción | Atajo |
|---|---|
| Abrir el notch | Pasar el puntero o hacer clic · deslizar dos dedos hacia abajo |
| Cerrar el notch | Deslizar dos dedos hacia arriba |
| Cambiar de pestaña | Deslizar tres dedos a la izquierda o la derecha (configurable en Ajustes › Disposición) |
| Pasos pequeños de volumen / brillo | <kbd>⇧⌥</kbd> + teclas de volumen o brillo |
| Retroiluminación del teclado | Mantener <kbd>⌃</kbd> + teclas de brillo (configurable) |
| Estante: Vista rápida (pulsar para fijar, mantener para echar un vistazo) | <kbd>Espacio</kbd> |
| Estante: mover o ampliar la selección | <kbd>←</kbd> <kbd>→</kbd> · <kbd>⇧</kbd> + flechas · escribir un nombre |
| Estante: seleccionar todo · copiar | <kbd>⌘A</kbd> · <kbd>⌘C</kbd> |
| Estante: abrir | <kbd>⌘O</kbd> · <kbd>⌘↓</kbd> · doble clic |
| Estante: quitar | <kbd>⌫</kbd> |

## Compilar desde el código fuente

Requiere **macOS 26+** y **Xcode 26+** (compilado y probado en macOS 27 con un MacBook Pro M1 Pro).

```bash
scripts/build.sh             # compilación Release → /Applications/DyNotch.app, y después la abre
scripts/make-dmg.sh          # compilación Release → build/DyNotch-<versión>.dmg, lista para publicar
open DyNotch.xcodeproj       # o ⌘R con el esquema DyNotch en Xcode
```

O compila y ejecuta los tests desde la terminal:

```bash
xcodebuild -project DyNotch.xcodeproj -scheme DyNotch -destination 'platform=macOS' build
xcodebuild -project DyNotch.xcodeproj -scheme DyNotch test
```

DyNotch no se puede distribuir en la Mac App Store: usa frameworks privados y un event tap de teclado.

### Conserva los permisos entre compilaciones

Por defecto la app se firma ad hoc, así que los permisos de Accesibilidad y Acceso total al disco dejan de aplicarse cada vez que se vuelve a compilar. `scripts/build.sh` borra por ti las entradas caducadas; después de compilar desde Xcode, Ajustes › Permisos las borra antes de que vuelvas a arrastrar DyNotch. Para evitarlo del todo:

1. Xcode › Settings › Accounts › añade tu Apple ID (basta con una cuenta gratuita).
2. Crea `Config/Signing.local.xcconfig`:

   ```
   DEVELOPMENT_TEAM = TU_TEAM_ID
   CODE_SIGN_IDENTITY = Apple Development
   ```

### Control remoto de depuración

En las compilaciones Debug puedes manejar el notch desde la terminal: `swift scripts/notch.swift open timers`, `… swipe` / `… swipe back`, `… hud volume`, `… bt` (`bt max`, `bt late`, `bt off`, `bt mouse`), `… meeting`, `… tour hud` (la visita de bienvenida en un paso concreto).

## Arquitectura

- **Ventana del notch** — un `NSPanel` sin bordes que no activa la app, por encima de la barra de menús en todos los espacios. Un monitor global del ratón decide cuándo los clics la atraviesan, para que la barra de menús de debajo siga funcionando; el notch físico se mide a partir de `NSScreen.safeAreaInsets` y `auxiliaryTopLeft/RightArea`.
- **Gestos entre pestañas** — los gestos con dos dedos salen de los eventos de desplazamiento sobre el notch abierto. Los de tres dedos se leen con el framework privado `MultitouchSupport`, solo mientras el notch está abierto y sin necesidad de permisos.
- **Teclas del Estante** — al hacer clic en el Estante, su panel pasa a recibir el teclado sin activar DyNotch (como hace Spotlight), así que la app que tienes delante sigue delante mientras <kbd>Espacio</kbd>, <kbd>⌘C</kbd> y las flechas llegan al Estante.
- **Indicador (HUD)** — un `CGEventTap` consume las teclas multimedia para que macOS ni cambie el nivel ni muestre su indicador. El volumen va por CoreAudio, el brillo de la pantalla por el framework privado `DisplayServices` (pantallas integradas y de Apple) y la retroiluminación del teclado por `KeyboardBrightnessClient`, del también privado `CoreBrightness`.
- **DDC/CI** — los demás monitores reciben el brillo por DDC/CI, a través de las llamadas privadas de `IOAVService` que Apple silicon tiene para cada pantalla externa. Igual que MonitorControl, DyNotch busca el servicio de cada pantalla en el I/O Registry justo después de su framebuffer y lo asocia a la pantalla mediante CoreDisplay. Los monitores conectados al puerto HDMI de los Mac con un conversor MCDP29xx responden en otra dirección, como descubrió m1ddc. Cada monitor tiene su propia cola, que solo envía el nivel más reciente, así que mantener pulsada una tecla o arrastrar nunca acumula niveles antiguos.
- **En reproducción** — desde macOS 15.4 solo los procesos con el entitlement adecuado pueden leer MediaRemote, así que DyNotch incluye [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (copiado en `Vendor/` en el commit `2971825`), que se ejecuta con el `/usr/bin/perl` del sistema y emite un flujo JSON.
- **Forma de onda** — un process tap privado de Core Audio (`CATapDescription`) escucha la mezcla del sistema mientras las barras están en pantalla; una FFT de 1024 puntos la reduce a seis bandas, retrasadas según la latencia del dispositivo de salida para que coincidan con lo que oyes (AirPods incluidos).
- **Concentración** — se lee de `~/Library/DoNotDisturb/DB`.
- **Guía de permisos** — un panel que no activa la app, encuentra la ventana de Ajustes del Sistema con `CGWindowList` y se queda debajo de ella. Su icono arrastra la URL del propio bundle de la app, que las listas de privacidad aceptan al soltarla; antes, un permiso ad hoc caducado se borra con `tccutil reset`.
- **AirPods** — el modelo sale del getter privado `productID` de IOBluetooth (así se reconocen los AirPods aunque les cambies el nombre) y la batería, de sus getters privados `batteryPercent…`, con `system_profiler` como alternativa.

## Licencia

DyNotch se publica bajo la [licencia MIT](LICENSE). Incluye [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), de Jonas van den Berg, bajo la licencia BSD-3-Clause; consulta [`Vendor/mediaremote-adapter/LICENSE`](Vendor/mediaremote-adapter/LICENSE).

---

<div align="center">Hecho por <a href="https://github.com/juancarloslopez3">Juan Carlos López</a></div>
