# App Contaduría · Sol-EMP

App web del despacho **Sol-EMP Soluciones Empresariales**: precierres mensuales de IVA e ISR antes del día 17, con panel de administrador y panel de cliente.

## Qué hace
- **Dos apartados:** Persona moral (régimen general de ley, autotransporte y RESICO; uno, dos o los tres) y Persona física (régimen general).
- **Hoja de precierre** como en Excel: ingresos con estatus C (contado), I (no pagado) y MA (cobro de meses anteriores), facturas elaboradas y cobradas, y gastos pagados facturados con retenciones.
- **Cálculo:** ISR acumulado con coeficiente de utilidad (PM general y autotransporte), sobre flujo (RESICO PM) o con tarifa 2026 (PF); IVA cobrado menos acreditable, con saldo a favor que pasa solo al mes siguiente. Celdas amarillas para PTU, pérdidas y compensaciones.
- **Permisos por mes:** captura cerrada → captura abierta (el cliente puede capturar) → precierre (el cliente ya no puede meter nada) → declarado (montos congelados).
- **Historial** de los 12 meses y descarga en Excel.

## Conectar la base de datos (Supabase)
1. Crea un proyecto en supabase.com.
2. En **SQL Editor**, pega `supabase.sql`, cambia el correo del administrador en la última línea y presiona **Run**.
3. En **Settings → API** copia la **Project URL** y la llave **anon public**.
4. Pégalas en `index.html` en `SB_URL` y `SB_KEY` (cerca del inicio del script).
5. En **Authentication → URL Configuration**, pon como Site URL: `https://supernova-colab.github.io/sol-emp/`.

Sin esos datos la app trabaja en modo demostración (datos guardados en el dispositivo).

Hecha por Supernova.
