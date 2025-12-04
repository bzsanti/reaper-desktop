# Reaper - Catálogo de Features

> Documento de referencia para todas las características planificadas y existentes de Reaper.
> Este es un proyecto personal open source (MIT) enfocado en mantener el rendimiento óptimo del sistema.

## 📊 Features Core - Monitoreo Básico

### 1. Monitoreo de Procesos en Tiempo Real
**Estado:** ✅ Implementado  
**Descripción:** Vista en tabla de todos los procesos del sistema con actualización automática.  
**Métricas incluidas:**
- PID del proceso
- Nombre del proceso
- Uso de CPU (%)
- Uso de memoria (MB/GB)
- Estado del proceso
- Número de threads
- Tiempo de ejecución

### 2. Detección de Procesos Problemáticos
**Estado:** ⚠️ Parcialmente implementado  
**Descripción:** Identificación automática de procesos que presentan comportamientos anómalos.  
**Capacidades:**
- Detección de procesos zombie
- Identificación de procesos con alto consumo de CPU
- Procesos en estado uninterruptible sleep
- Procesos que no responden a señales

### 3. Métricas del Sistema
**Estado:** ✅ Implementado  
**Descripción:** Información general sobre el estado del sistema.  
**Incluye:**
- Load average (1, 5, 15 minutos)
- Número de cores de CPU
- Frecuencia del procesador
- Uso total de CPU
- Uso total de memoria

### 4. Gestión de Procesos
**Estado:** ✅ Implementado  
**Descripción:** Capacidad de interactuar con procesos desde la interfaz.  
**Acciones disponibles:**
- Terminar proceso (SIGTERM)
- Forzar terminación (SIGKILL)
- Suspender proceso
- Reanudar proceso
- Copiar información del proceso

## 🎯 Features Must-Have - Uso Personal Efectivo

### 5. Menu Bar con Mini-gráficos
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Presencia permanente en la barra de menú de macOS con visualización compacta.  
**Características:**
- Gráfico de CPU en tiempo real (últimos 60 segundos)
- Indicador de memoria disponible
- Acceso rápido a la ventana principal
- Menú desplegable con top 5 procesos por CPU
- Opciones de configuración rápida

### 6. Gráficos Históricos
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Almacenamiento y visualización de métricas históricas.  
**Capacidades:**
- Historial de últimas 24 horas mínimo
- Gráficos de línea para CPU, memoria, red, disco
- Zoom y pan interactivo
- Comparación de múltiples métricas
- Persistencia de datos entre reinicios

### 7. Notificaciones Configurables
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Sistema de alertas basado en umbrales personalizables.  
**Triggers disponibles:**
- CPU > X% por más de Y segundos
- Memoria disponible < X GB
- Proceso específico consumiendo > X recursos
- Detección de nuevo proceso zombie
- Temperatura del sistema > X grados
- Disco lleno > X%

### 8. Sensores de Hardware
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Lectura de sensores físicos del sistema.  
**Sensores:**
- Temperatura de CPU (por core)
- Temperatura de GPU
- Velocidad de ventiladores
- Voltajes principales
- Estado de la batería (MacBooks)
- Throttling térmico activo

### 9. Dark/Light Mode Automático
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Integración completa con el sistema de temas de macOS.  
**Incluye:**
- Seguimiento automático del tema del sistema
- Transiciones suaves entre temas
- Colores optimizados para cada modo
- Respeto de preferencias de accesibilidad

### 10. Export de Datos
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Capacidad de exportar información para análisis externo.  
**Formatos soportados:**
- CSV para hojas de cálculo
- JSON para procesamiento programático
- PDF para reportes
- Markdown para documentación
- Gráficos como PNG/SVG

### 11. Keyboard Shortcuts Completos
**Estado:** ⚠️ Parcialmente implementado  
**Prioridad:** Alta  
**Descripción:** Acceso rápido a todas las funciones vía teclado.  
**Shortcuts principales:**
- ⌘K - Terminar proceso seleccionado
- ⌘⇧K - Forzar terminación
- ⌘F - Buscar proceso
- ⌘R - Actualizar lista
- ⌘I - Información detallada
- ⌘S - Suspender/Reanudar
- ⌘E - Exportar datos
- ⌘, - Preferencias

### 12. Search/Filter Avanzado
**Estado:** ⚠️ Básico implementado  
**Prioridad:** Media  
**Descripción:** Sistema de búsqueda y filtrado sofisticado.  
**Capacidades:**
- Búsqueda por nombre, PID, usuario
- Filtros por estado del proceso
- Filtros por rango de recursos (CPU > 50%)
- Expresiones regulares
- Filtros guardados
- Búsqueda incremental en tiempo real

### 13. Grupos de Procesos por Aplicación
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Agrupación inteligente de procesos relacionados.  
**Características:**
- Agrupar helper processes con su app principal
- Vista colapsable por aplicación
- Métricas agregadas por grupo
- Acciones en grupo (terminar toda la app)
- Identificación automática de relaciones padre-hijo

### 14. Performance Garantizado < 2% CPU
**Estado:** ⚠️ En optimización  
**Prioridad:** Crítica  
**Descripción:** Optimización extrema para mínimo impacto en el sistema.  
**Estrategias:**
- Polling adaptativo (más lento cuando idle)
- Caching inteligente de datos
- Lazy loading de información detallada
- Uso eficiente de APIs del sistema
- Procesamiento diferido de tareas no críticas

## 🚀 Diferenciadores Únicos - Capacidades Avanzadas

### 15. Análisis de Procesos Unkillable
**Estado:** 🟡 En desarrollo  
**Prioridad:** Crítica (Diferenciador clave)  
**Descripción:** Diagnóstico profundo de por qué un proceso no puede ser terminado.  
**Análisis incluye:**
- Stack trace del kernel
- Estado exacto del proceso (D state, etc.)
- File handles bloqueados
- Operaciones I/O pendientes
- Locks del sistema
- Sugerencias de resolución

### 16. Detección de Deadlocks
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Identificación automática de situaciones de deadlock.  
**Capacidades:**
- Análisis de dependencias entre procesos
- Detección de espera circular
- Visualización del grafo de bloqueo
- Sugerencias para resolver el deadlock
- Historial de deadlocks detectados

### 17. Kernel Panic Predictor
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Predicción de posibles kernel panics basada en patrones.  
**Análisis:**
- Patrones de memoria anómalos
- Crecimiento descontrolado de kernel_task
- Errores de hardware detectados
- Correlación con panics históricos
- Score de riesgo en tiempo real

### 18. Process Dependency Graph
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Visualización interactiva de relaciones entre procesos.  
**Características:**
- Grafo dirigido de procesos padre-hijo
- Visualización de IPC entre procesos
- Dependencias de recursos compartidos
- Navegación interactiva
- Filtros por tipo de relación

### 19. dtrace Integration
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Integración con dtrace para análisis profundo.  
**Capacidades:**
- Scripts dtrace predefinidos
- Editor de scripts personalizado
- Visualización de resultados en UI
- Perfiles de rendimiento detallados
- Exportación a formato Instruments

### 20. I/O Bottleneck Analyzer
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Identificación de cuellos de botella de I/O.  
**Análisis:**
- IOPS por proceso
- Latencia de disco por operación
- Queue depth del sistema
- Identificación de procesos bloqueando I/O
- Recomendaciones de optimización
- Heatmap de actividad de disco

### 21. Memory Leak Detector
**Estado:** 🔴 Pendiente  
**Prioridad:** Alta  
**Descripción:** Detección automática de fugas de memoria.  
**Características:**
- Tracking de crecimiento anormal de memoria
- Análisis de heap allocations
- Detección de patrones de leak
- Alertas tempranas
- Gráficos de tendencia de memoria
- Sugerencias de procesos a reiniciar

### 22. Network Latency per App
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Monitoreo de red por aplicación.  
**Métricas:**
- Latencia promedio por app
- Bandwidth consumido
- Conexiones activas
- DNS queries y tiempos de resolución
- Packet loss por conexión
- Geolocalización de conexiones

### 23. Automation Engine
**Estado:** 🔴 Pendiente  
**Prioridad:** Media  
**Descripción:** Motor de reglas para automatización.  
**Capacidades:**
- Reglas if-then configurables
- Acciones automáticas (kill, notify, log)
- Scheduling de acciones
- Scripts personalizados en Swift/Shell
- Integración con Shortcuts de macOS
- API para herramientas externas

### 24. CLI Companion
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Herramienta de línea de comandos complementaria.  
**Comandos:**
- `reaper ps` - Lista de procesos
- `reaper kill <pid>` - Terminar proceso
- `reaper monitor <metric>` - Monitoreo en terminal
- `reaper export` - Exportar datos
- `reaper analyze <pid>` - Análisis profundo
- Output en JSON para scripting

## 💎 Nice-to-Have - Mejoras de UX

### 25. Onboarding Tutorial Interactivo
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Guía interactiva para nuevos usuarios.  
**Incluye:**
- Tour de características principales
- Tips contextuales
- Configuración inicial guiada
- Mejores prácticas
- Modo de práctica seguro

### 26. Themes Personalizables
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Sistema de temas más allá de dark/light.  
**Opciones:**
- Temas predefinidos (Pro, Minimal, Colorful)
- Editor de colores personalizado
- Importar/exportar temas
- Temas por horario
- Soporte para daltonismo

### 27. Efectos de Sonido Sutiles
**Estado:** 🔴 Pendiente  
**Prioridad:** Muy baja  
**Descripción:** Feedback auditivo opcional.  
**Sonidos para:**
- Proceso terminado exitosamente
- Error al terminar proceso
- Alerta crítica
- Actualización completada
- Configurables y desactivables

### 28. Animaciones Fluidas
**Estado:** ⚠️ Básicas implementadas  
**Prioridad:** Baja  
**Descripción:** Animaciones con spring physics para mejor UX.  
**Áreas:**
- Transiciones entre vistas
- Actualización de gráficos
- Aparición/desaparición de elementos
- Feedback de acciones
- Respetando preferencias de accesibilidad

### 29. Badge Notifications en Dock
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Indicadores visuales en el icono del Dock.  
**Muestra:**
- Número de alertas activas
- Indicador de proceso crítico
- CPU % cuando > 80%
- Estado del sistema (color del badge)

### 30. Quick Look Plugin
**Estado:** 🔴 Pendiente  
**Prioridad:** Muy baja  
**Descripción:** Vista previa de archivos de proceso.  
**Soporta:**
- Logs de aplicación
- Archivos de configuración
- Memory dumps
- Stack traces exportados

### 31. Spotlight Integration
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Búsqueda de procesos desde Spotlight.  
**Comandos:**
- "reaper firefox" - Abrir Reaper mostrando Firefox
- "kill process X" - Acción directa
- Búsqueda en historial de procesos

### 32. Share Sheets
**Estado:** 🔴 Pendiente  
**Prioridad:** Baja  
**Descripción:** Compartir información fácilmente.  
**Compartir:**
- Screenshots de gráficos
- Reportes de sistema
- Logs de procesos
- Análisis de problemas
- Integración con Mail, Messages, etc.

## 📈 Métricas de Éxito del Proyecto

### Performance
- ✅ CPU < 2% en idle
- ✅ CPU < 5% monitoreando activamente  
- ✅ Memoria < 100MB footprint base
- ⚠️ Latencia de actualización < 100ms
- ✅ Startup time < 1 segundo

### Estabilidad
- Zero crashes en uso normal
- Manejo graceful de errores
- Recuperación automática de estados
- Sin memory leaks

### Usabilidad
- Todas las funciones accesibles en < 3 clicks
- Shortcuts para power users
- Documentación inline completa
- Configuración sin necesidad de reiniciar

## 🛠 Stack Tecnológico

### Backend (Rust)
- **sysinfo**: Información del sistema
- **mach2**: Interfaz con kernel de macOS
- **tokio**: Async runtime (futuro)
- **serde**: Serialización de datos

### Frontend (SwiftUI)
- **Combine**: Reactive programming
- **Charts**: Visualización de datos (futuro)
- **CoreData**: Persistencia (futuro)
- **UserNotifications**: Sistema de alertas

### Build & Distribution
- **cargo**: Build system de Rust
- **Swift Package Manager**: Dependencias Swift
- **GitHub Actions**: CI/CD
- **Licencia MIT**: Open source

## 🔒 Principios de Diseño

1. **Privacy First**: Sin telemetría, sin conexiones no solicitadas
2. **Performance**: Impacto mínimo en el sistema monitoreado
3. **Open Source**: Transparencia total del código
4. **macOS Native**: Integración perfecta con el sistema
5. **Power User Focused**: Herramientas avanzadas accesibles

## 📅 Priorización de Implementación

### Sprint 1 (Actual)
- Menu Bar con mini-gráficos
- Gráficos históricos 24h
- Notificaciones básicas
- Dark/Light mode automático

### Sprint 2
- Análisis de procesos unkillable (diferenciador clave)
- Memory leak detector básico
- I/O bottleneck analyzer
- Export CSV/JSON

### Sprint 3
- Grupos de procesos por app
- Automation engine básico
- Network monitoring per-app
- Sensores de hardware

### Sprint 4
- Process dependency graph
- Deadlock detection
- Performance < 2% garantizado
- CLI companion

### Futuro
- Resto de features nice-to-have
- Integración con herramientas de desarrollo
- Plugins y extensibilidad
- Marketplace de scripts de automatización

---

*Este documento es un living document y será actualizado conforme el proyecto evolucione.*
*Última actualización: Agosto 2024*