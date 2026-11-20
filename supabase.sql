-- ============================================================
-- Sol-Emp · App Contaduría · Base de datos para Supabase
-- Pega todo este archivo en Supabase → SQL Editor → New query → Run.
-- Antes de correrlo, cambia el correo de la última línea por el
-- correo del administrador (el contador).
-- ============================================================

-- Administradores del despacho (ven y editan todo)
create table if not exists admins (
  email text primary key
);

-- Clientes (personas morales y personas físicas)
create table if not exists clientes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  rfc text not null,
  tipo text not null check (tipo in ('PM','PF')),
  regimenes text[] not null default '{}',          -- 601 general de ley, 624 autotransporte, 626 RESICO, 612 PF
  coef numeric default 0,                          -- coeficiente de utilidad (general de ley)
  coef_aut numeric default 0,                      -- coeficiente de autotransporte
  email_cliente text,                              -- correo con el que entra el cliente
  creado timestamptz default now()
);

-- Un registro por cliente y mes: controla quién puede capturar
create table if not exists periodos (
  cliente_id uuid not null references clientes(id) on delete cascade,
  anio int not null,
  mes int not null check (mes between 1 and 12),
  estado text not null default 'bloqueado' check (estado in ('bloqueado','abierto','precierre','declarado')),
  resumen jsonb,                                   -- montos congelados al declarar
  ajustes jsonb default '{}'::jsonb,               -- celdas amarillas: PTU, pérdidas, compensaciones, saldos
  actualizado timestamptz default now(),
  primary key (cliente_id, anio, mes)
);

-- Ingresos y gastos (la hoja de precierre)
create table if not exists movimientos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  anio int not null,
  mes int not null check (mes between 1 and 12),
  fecha date not null,
  tipo text not null check (tipo in ('ingreso','gasto')),
  estatus text check (estatus in ('C','I','MA')),  -- C contado, I no pagado, MA cobro de meses anteriores
  regimen text,
  concepto text,
  rfc text,
  subtotal numeric default 0,
  iva numeric default 0,
  iva_ret numeric default 0,
  isr_ret numeric default 0,
  deducible boolean default true,
  uuid_cfdi text,
  capturado_por text not null default 'admin' check (capturado_por in ('admin','cliente')),
  creado timestamptz default now(),
  constraint fecha_del_mes check (extract(year from fecha) = anio and extract(month from fecha) = mes)
);
create unique index if not exists movimientos_cfdi_unico on movimientos (cliente_id, uuid_cfdi) where uuid_cfdi is not null;
create index if not exists movimientos_cliente_mes on movimientos (cliente_id, anio, mes);

-- ---------- Funciones de seguridad ----------
create or replace function es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

create or replace function es_mi_cliente(cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from clientes
                 where id = cid and lower(email_cliente) = lower(auth.jwt() ->> 'email'));
$$;

create or replace function captura_abierta(cid uuid, a int, m int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from periodos
                 where cliente_id = cid and anio = a and mes = m and estado = 'abierto');
$$;

-- ---------- Reglas: cada quien ve solo lo suyo ----------
alter table admins      enable row level security;
alter table clientes    enable row level security;
alter table periodos    enable row level security;
alter table movimientos enable row level security;

drop policy if exists "admin se ve" on admins;
create policy "admin se ve" on admins for select
  using (lower(email) = lower(auth.jwt() ->> 'email'));

drop policy if exists "admin clientes" on clientes;
create policy "admin clientes" on clientes for all using (es_admin()) with check (es_admin());
drop policy if exists "cliente ve su ficha" on clientes;
create policy "cliente ve su ficha" on clientes for select using (es_mi_cliente(id));

drop policy if exists "admin periodos" on periodos;
create policy "admin periodos" on periodos for all using (es_admin()) with check (es_admin());
drop policy if exists "cliente ve sus meses" on periodos;
create policy "cliente ve sus meses" on periodos for select using (es_mi_cliente(cliente_id));

drop policy if exists "admin movimientos" on movimientos;
create policy "admin movimientos" on movimientos for all using (es_admin()) with check (es_admin());
drop policy if exists "cliente ve sus movimientos" on movimientos;
create policy "cliente ve sus movimientos" on movimientos for select using (es_mi_cliente(cliente_id));
-- El cliente solo captura cuando el administrador autorizó el mes (estado 'abierto').
-- En precierre o declarado ya no puede agregar, cambiar ni borrar nada.
drop policy if exists "cliente captura" on movimientos;
create policy "cliente captura" on movimientos for insert
  with check (es_mi_cliente(cliente_id) and capturado_por = 'cliente' and captura_abierta(cliente_id, anio, mes));
drop policy if exists "cliente corrige lo suyo" on movimientos;
create policy "cliente corrige lo suyo" on movimientos for update
  using (es_mi_cliente(cliente_id) and capturado_por = 'cliente' and captura_abierta(cliente_id, anio, mes))
  with check (es_mi_cliente(cliente_id) and capturado_por = 'cliente' and captura_abierta(cliente_id, anio, mes));
drop policy if exists "cliente borra lo suyo" on movimientos;
create policy "cliente borra lo suyo" on movimientos for delete
  using (es_mi_cliente(cliente_id) and capturado_por = 'cliente' and captura_abierta(cliente_id, anio, mes));

-- ---------- Administrador ----------
-- Cambia este correo por el del contador. Para agregar más administradores, repite la línea.
insert into admins (email) values ('CORREO_DEL_CONTADOR@ejemplo.com') on conflict do nothing;

-- ===== Actualización (nov 2026): situación, actividad, notas y nombre del administrador =====
alter table clientes add column if not exists activo boolean not null default true;
alter table clientes add column if not exists actividad text;
alter table movimientos add column if not exists nota text;
alter table admins add column if not exists nombre text;

-- ===== Actualización (20 nov 2026): 5 regímenes, tablas y tarifas, tasas de IVA y cobros a crédito =====
alter table clientes add column if not exists fiscal jsonb;
alter table movimientos add column if not exists tasa_iva text;
alter table movimientos add column if not exists ref_id uuid;
create table if not exists config (clave text primary key, valor jsonb not null, actualizado timestamptz default now());
alter table config enable row level security;
drop policy if exists "config leer" on config;
create policy "config leer" on config for select using (auth.role() = 'authenticated');
drop policy if exists "config admin" on config;
create policy "config admin" on config for all using (es_admin()) with check (es_admin());
-- El cliente solo puede capturar hasta el último día del mes (hora de México)
create or replace function captura_abierta(cid uuid, a int, m int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from periodos where cliente_id = cid and anio = a and mes = m and estado = 'abierto')
     and (now() at time zone 'America/Mexico_City')::date <= (make_date(a, m, 1) + interval '1 month' - interval '1 day')::date;
$$;
