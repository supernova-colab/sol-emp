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

-- 20 nov (2): nombre del dueño para agrupar sus empresas
alter table clientes add column if not exists titular text;

-- ============================================================
-- 24 nov: Perfil (foto y nombre) y accesos que activa el despacho
-- Pega desde aquí hasta el final en el SQL Editor y dale Run.
-- ============================================================
create table if not exists perfiles (
  email text primary key,
  nombre text,
  foto text,
  actualizado timestamptz default now()
);
alter table perfiles enable row level security;
drop policy if exists "perfil propio o admin" on perfiles;
create policy "perfil propio o admin" on perfiles for all
  using (lower(email) = lower(auth.jwt() ->> 'email') or es_admin())
  with check (lower(email) = lower(auth.jwt() ->> 'email') or es_admin());

create table if not exists accesos (
  email text primary key,
  rol text not null default 'cliente' check (rol in ('cliente','admin')),
  activo boolean not null default true,
  actualizado timestamptz default now()
);
alter table accesos enable row level security;
drop policy if exists "acceso propio" on accesos;
create policy "acceso propio" on accesos for select using (email = lower(auth.jwt() ->> 'email') or es_admin());

-- Quien ya tiene empresas o es administrador sigue entrando igual
insert into accesos (email, rol, activo)
  select distinct lower(trim(email_cliente)), 'cliente', true from clientes
  where email_cliente is not null and trim(email_cliente) <> ''
on conflict (email) do nothing;
insert into accesos (email, rol, activo) select lower(email), 'admin', true from admins on conflict (email) do nothing;

drop policy if exists "admins ven admins" on admins;
create policy "admins ven admins" on admins for select using (es_admin());

-- El cliente solo ve sus empresas si el despacho activó su acceso
create or replace function es_mi_cliente(cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from clientes where id = cid and lower(email_cliente) = lower(auth.jwt() ->> 'email'))
     and exists (select 1 from accesos where email = lower(auth.jwt() ->> 'email') and activo and rol = 'cliente');
$$;

-- Lista de cuentas creadas (solo la ve el administrador)
create or replace function lista_cuentas() returns table (email text, creada timestamptz, ultimo_acceso timestamptz, confirmada boolean)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not es_admin() then return; end if;
  return query select lower(u.email)::text, u.created_at, u.last_sign_in_at, (u.email_confirmed_at is not null)
    from auth.users u order by u.created_at desc;
end; $$;
revoke all on function lista_cuentas() from public, anon;
grant execute on function lista_cuentas() to authenticated;

-- Activar como cliente, como administrador, o quitar acceso
create or replace function poner_acceso(e text, r text) returns void
language plpgsql security definer set search_path = public as $$
declare yo text := lower(auth.jwt() ->> 'email'); em text := lower(trim(e));
begin
  if not es_admin() then raise exception 'Solo el administrador puede dar accesos'; end if;
  if r not in ('cliente','admin','ninguno') then raise exception 'Tipo de acceso no válido'; end if;
  if em = yo and r <> 'admin' then raise exception 'No puedes quitarte tu propio acceso de administrador'; end if;
  if r = 'admin' then insert into admins (email) values (em) on conflict (email) do nothing;
  else delete from admins where lower(email) = em; end if;
  if not exists (select 1 from admins) then raise exception 'Debe quedar al menos un administrador'; end if;
  insert into accesos (email, rol, activo, actualizado)
    values (em, case when r = 'admin' then 'admin' else 'cliente' end, r <> 'ninguno', now())
  on conflict (email) do update set rol = excluded.rol, activo = excluded.activo, actualizado = now();
end; $$;
revoke all on function poner_acceso(text, text) from public, anon;
grant execute on function poner_acceso(text, text) to authenticated;

-- ============================================================
-- 25 nov: Seguridad. Las reglas aplican solo a usuarios con sesión
-- y las funciones internas ya no se pueden llamar sin iniciar sesión.
-- Pega desde aquí hasta el final en el SQL Editor y dale Run.
-- ============================================================
alter policy "acceso propio" on accesos to authenticated;
alter policy "admins ven admins" on admins to authenticated;
alter policy "admin se ve" on admins to authenticated;
alter policy "cliente ve su ficha" on clientes to authenticated;
alter policy "admin clientes" on clientes to authenticated;
alter policy "config leer" on config to authenticated;
alter policy "config admin" on config to authenticated;
alter policy "cliente corrige lo suyo" on movimientos to authenticated;
alter policy "cliente borra lo suyo" on movimientos to authenticated;
alter policy "cliente captura" on movimientos to authenticated;
alter policy "cliente ve sus movimientos" on movimientos to authenticated;
alter policy "admin movimientos" on movimientos to authenticated;
alter policy "perfil propio o admin" on perfiles to authenticated;
alter policy "admin periodos" on periodos to authenticated;
alter policy "cliente ve sus meses" on periodos to authenticated;
revoke execute on function es_admin() from public, anon;
revoke execute on function es_mi_cliente(uuid) from public, anon;
revoke execute on function captura_abierta(uuid, integer, integer) from public, anon;
grant execute on function es_admin() to authenticated;
grant execute on function es_mi_cliente(uuid) to authenticated;
grant execute on function captura_abierta(uuid, integer, integer) to authenticated;
-- 25 nov: eliminar una cuenta desde Usuarios y accesos (solo administradores)
create or replace function eliminar_cuenta(e text) returns void
language plpgsql security definer set search_path = public, auth as $$
declare yo text := lower(auth.jwt() ->> 'email'); em text := lower(trim(e));
begin
  if not es_admin() then raise exception 'Solo el administrador puede eliminar cuentas'; end if;
  if em = yo then raise exception 'No puedes eliminar tu propia cuenta'; end if;
  delete from admins where lower(email) = em;
  if not exists (select 1 from admins) then raise exception 'Debe quedar al menos un administrador'; end if;
  delete from accesos where email = em;
  delete from perfiles where lower(email) = em;
  delete from auth.users where lower(email) = em;
end; $$;
revoke all on function eliminar_cuenta(text) from public, anon;
grant execute on function eliminar_cuenta(text) to authenticated;
