# Focus Store — Sistema de Soporte Técnico

## Proyecto
Billy Estrada, Focus Store (focusstore.net) y FocusLab, Tegucigalda, Honduras.
Sistema: **Soporte Técnico** — gestión de tickets de reparación de equipos.

## Repositorio
- **Repo:** `ventas806/soporte` → GitHub Pages → `soporte.focusstore.net`
- **Rama:** main (editar directo, sin branches)
- **Carpeta local:** `C:\Users\b_est\Downloads\soporte-repo\`

## Documentación oficial (Obsidian)
`C:\Users\b_est\Documents\MEMORIA\MEMORIA\Soporte\`

Si existe discrepancia entre memoria de Claude, conversación actual y código,
prevalece la documentación de Obsidian.

## Regla obligatoria antes de comenzar

1. Leer `ULTIMA_SESION.md` en Obsidian
2. Leer `CONTEXTO.md`
3. Leer `TAREAS.md`
4. Leer `HANDOFF.md`
5. Leer `PROGRESO.md` y `DECISIONES.md` si es necesario

## Regla obligatoria antes de finalizar

1. Actualizar `ULTIMA_SESION.md`
2. Actualizar `TAREAS.md`
3. Actualizar `PROGRESO.md`
4. Actualizar `HANDOFF.md`
5. Actualizar `DECISIONES.md` y `ERRORES.md` si aplica

## Infraestructura

- **Supabase:** `uzhjnedhmbvgfqqssuov` — tablas con prefijo `sp_`
- **WhatsApp:** UltraMsg instance178325 / token: zm383lcp9w2xv11q — parámetro `message` (NO `body`)
- **Email:** Gmail SMTP — ventas@focusstore.net / swtxegdmjlpsxpaf
- **Dominio:** soporte.focusstore.net → CNAME → ventas806.github.io

## Edge Functions (versiones actuales)

| Función | Versión |
|---|---|
| `check-ticket-alerts` | v17 |
| `send-ticket-email` | v14 |
| `send-whatsapp` | v1 |
| `notify-tech` | v3 |
| `notify-admin-quote` | v1 |

## Reglas críticas

- Crédito diagnóstico L.450 se **RESTA** del total (ya fue cobrado al ingresar)
- Técnico se notifica cuando **admin confirma el pago**, NO cuando cliente aprueba
- Email del cliente es **obligatorio** en formulario de ingreso
- Tablas siempre con prefijo `sp_`
- send-whatsapp: parámetro `message`, NO `body`
- **NUNCA** usar ramas ni worktrees — editar directo en main

## Flujo de estados

```
ingresado → en_diagnostico → esperando_aprobacion
→ [Opción A] cliente aprueba → pendiente_pago
→ [Opción B] admin aprueba directo → pendiente_pago
→ pendiente_pago → [admin define monto, envía instrucciones, confirma pago]
→ aprobado_reparacion → en_reparacion → en_pruebas → listo_entrega → entregado
Alternativos: cancelado, irreparable, abandonado
```

## Estilo de trabajo

- Cambios incrementales y testeables
- Avisar antes de ejecutar algo que pueda romper
- Español en todos los comentarios y documentación
