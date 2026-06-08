-- ================================================================
-- FOCUS STORE · SISTEMA DE SOPORTE TÉCNICO
-- Migration v1.0 — Ejecutar en Supabase SQL Editor
-- ================================================================

-- ── EXTENSIONES ─────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── FUNCIÓN: updated_at automático ──────────────────────────────
CREATE OR REPLACE FUNCTION sp_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- TABLA: sp_profiles (staff interno)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_profiles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name   TEXT NOT NULL,
  username    TEXT UNIQUE NOT NULL,
  role        TEXT NOT NULL DEFAULT 'recepcion' CHECK (role IN (
                'admin','supervisor','recepcion','tecnico','auditor'
              )),
  is_active   BOOLEAN DEFAULT true,
  color       TEXT DEFAULT '#3d6aff',
  avatar      TEXT DEFAULT 'U',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER trg_sp_profiles_upd
  BEFORE UPDATE ON sp_profiles
  FOR EACH ROW EXECUTE FUNCTION sp_set_updated_at();

-- ================================================================
-- TABLA: sp_customers (datos sensibles — solo recepción/admin)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_customers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name       TEXT NOT NULL,
  phone           TEXT,
  email           TEXT,
  identity_number TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  created_by      UUID REFERENCES sp_profiles(id)
);

CREATE INDEX IF NOT EXISTS idx_spc_email ON sp_customers(lower(email));
CREATE INDEX IF NOT EXISTS idx_spc_phone ON sp_customers(phone);
CREATE INDEX IF NOT EXISTS idx_spc_name  ON sp_customers(lower(full_name));

CREATE TRIGGER trg_sp_customers_upd
  BEFORE UPDATE ON sp_customers
  FOR EACH ROW EXECUTE FUNCTION sp_set_updated_at();

-- ================================================================
-- TABLA: sp_equipment (equipo físico)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_equipment (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id        UUID REFERENCES sp_customers(id) ON DELETE RESTRICT,
  category           TEXT NOT NULL,
  subcategory        TEXT,
  brand              TEXT NOT NULL,
  model              TEXT NOT NULL,
  serial_number      TEXT,
  color              TEXT,
  physical_condition TEXT DEFAULT 'bueno' CHECK (
                       physical_condition IN ('bueno','regular','dañado')
                     ),
  accessories        TEXT[],
  accessories_notes  TEXT,
  created_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spe_serial   ON sp_equipment(serial_number);
CREATE INDEX IF NOT EXISTS idx_spe_customer ON sp_equipment(customer_id);
CREATE INDEX IF NOT EXISTS idx_spe_brand    ON sp_equipment(lower(brand), lower(model));

-- ================================================================
-- FUNCIÓN: generar número de ticket (TKT-2026-0001)
-- ================================================================
CREATE OR REPLACE FUNCTION sp_generate_ticket_number()
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  y   TEXT := TO_CHAR(NOW(), 'YYYY');
  seq INTEGER;
BEGIN
  SELECT COALESCE(MAX(
    CAST(SPLIT_PART(ticket_number, '-', 3) AS INTEGER)
  ), 0) + 1
  INTO seq
  FROM sp_tickets
  WHERE ticket_number LIKE 'TKT-' || y || '-%';
  RETURN 'TKT-' || y || '-' || LPAD(seq::TEXT, 4, '0');
END;
$$;

-- ================================================================
-- TABLA: sp_tickets (núcleo del sistema)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_tickets (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number          TEXT UNIQUE NOT NULL DEFAULT sp_generate_ticket_number(),
  customer_id            UUID REFERENCES sp_customers(id) ON DELETE RESTRICT,
  equipment_id           UUID REFERENCES sp_equipment(id) ON DELETE RESTRICT,

  -- Origen del ticket
  ticket_origin          TEXT NOT NULL DEFAULT 'cliente_remoto' CHECK (ticket_origin IN (
                           'cliente_presencial','staff_presencial',
                           'staff_telefono','cliente_remoto'
                         )),
  equipment_on_arrival   BOOLEAN DEFAULT false,

  -- Falla reportada
  reported_fault         TEXT NOT NULL,
  client_notes           TEXT,

  -- Estado
  status                 TEXT NOT NULL DEFAULT 'solicitud_recibida' CHECK (status IN (
                           'solicitud_recibida','equipo_en_camino','equipo_recibido',
                           'en_diagnostico','esperando_aprobacion','aprobado_reparacion',
                           'esperando_repuesto','en_reparacion','en_pruebas',
                           'listo_para_entrega','entregado','cerrado',
                           'cancelado','irreparable','abandonado'
                         )),

  -- Asignación
  assigned_to            UUID REFERENCES sp_profiles(id),
  received_by            UUID REFERENCES sp_profiles(id),
  created_by             UUID REFERENCES sp_profiles(id),

  -- Token de acceso para el cliente (sin cuenta)
  access_token           TEXT UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  token_expires_at       TIMESTAMPTZ DEFAULT NOW() + INTERVAL '120 days',

  -- Envío remoto
  shipping_method        TEXT CHECK (shipping_method IN ('presencial','courier','otro')),
  tracking_number        TEXT,
  courier_name           TEXT,
  estimated_arrival      DATE,
  shipping_notes         TEXT,

  -- Fechas clave del proceso
  received_at            TIMESTAMPTZ,
  diagnosis_started_at   TIMESTAMPTZ,
  estimated_ready_at     TIMESTAMPTZ,
  ready_notified_at      TIMESTAMPTZ,
  delivered_at           TIMESTAMPTZ,
  closed_at              TIMESTAMPTZ,

  -- Política de abandono
  free_pickup_deadline   DATE,
  storage_fee_active     BOOLEAN DEFAULT false,
  second_notice_sent_at  TIMESTAMPTZ,
  abandon_notice_sent_at TIMESTAMPTZ,
  client_extension_requested BOOLEAN DEFAULT false,
  client_extension_notes TEXT,
  client_extension_approved BOOLEAN,
  extended_deadline      DATE,

  -- Términos y condiciones aceptados
  terms_accepted         BOOLEAN DEFAULT false,
  terms_accepted_at      TIMESTAMPTZ,
  terms_ip_address       TEXT,

  -- Financiero
  diagnosis_fee          NUMERIC(10,2) DEFAULT 0,
  diagnosis_credited     BOOLEAN DEFAULT false,

  -- Garantía
  warranty_days          INTEGER DEFAULT 30,
  warranty_expires_at    TIMESTAMPTZ,

  created_at             TIMESTAMPTZ DEFAULT NOW(),
  updated_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spt_status   ON sp_tickets(status);
CREATE INDEX IF NOT EXISTS idx_spt_customer ON sp_tickets(customer_id);
CREATE INDEX IF NOT EXISTS idx_spt_assigned ON sp_tickets(assigned_to);
CREATE INDEX IF NOT EXISTS idx_spt_token    ON sp_tickets(access_token);
CREATE INDEX IF NOT EXISTS idx_spt_number   ON sp_tickets(ticket_number);
CREATE INDEX IF NOT EXISTS idx_spt_created  ON sp_tickets(created_at DESC);

CREATE TRIGGER trg_sp_tickets_upd
  BEFORE UPDATE ON sp_tickets
  FOR EACH ROW EXECUTE FUNCTION sp_set_updated_at();

-- Auto: equipo en tienda → status directo a equipo_recibido
CREATE OR REPLACE FUNCTION sp_ticket_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.equipment_on_arrival = true AND NEW.received_at IS NULL THEN
    NEW.received_at := NOW();
    NEW.status      := 'equipo_recibido';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sp_ticket_insert
  BEFORE INSERT ON sp_tickets
  FOR EACH ROW EXECUTE FUNCTION sp_ticket_on_insert();

-- Auto: acciones al cambiar estado
CREATE OR REPLACE FUNCTION sp_ticket_on_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    -- Registrar en historial automáticamente
    INSERT INTO sp_ticket_status_history(ticket_id, from_status, to_status, actor_type)
    VALUES (NEW.id, OLD.status, NEW.status, 'system');

    -- Listo para entrega → calcular deadline de retiro gratuito
    IF NEW.status = 'listo_para_entrega' THEN
      NEW.ready_notified_at    := NOW();
      NEW.free_pickup_deadline := (NOW() + INTERVAL '15 days')::DATE;
    END IF;

    -- Entregado → registrar fecha y garantía
    IF NEW.status = 'entregado' AND NEW.delivered_at IS NULL THEN
      NEW.delivered_at        := NOW();
      NEW.warranty_expires_at := NOW() + (NEW.warranty_days || ' days')::INTERVAL;
    END IF;

    -- Cerrado
    IF NEW.status = 'cerrado' AND NEW.closed_at IS NULL THEN
      NEW.closed_at := NOW();
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sp_ticket_status
  BEFORE UPDATE ON sp_tickets
  FOR EACH ROW EXECUTE FUNCTION sp_ticket_on_status_change();

-- ================================================================
-- TABLA: sp_ticket_status_history
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_ticket_status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id   UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status   TEXT NOT NULL,
  changed_by  UUID REFERENCES sp_profiles(id),
  actor_type  TEXT DEFAULT 'staff' CHECK (actor_type IN ('staff','client','system')),
  comment     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spsh_ticket ON sp_ticket_status_history(ticket_id);

-- ================================================================
-- TABLA: sp_ticket_messages (conversación visible al cliente)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_ticket_messages (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id            UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  author_type          TEXT NOT NULL CHECK (author_type IN ('client','staff','system')),
  author_id            UUID REFERENCES sp_profiles(id),
  message              TEXT NOT NULL,
  is_visible_to_client BOOLEAN DEFAULT true,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spm_ticket ON sp_ticket_messages(ticket_id);

-- ================================================================
-- TABLA: sp_ticket_internal_notes (notas privadas del staff)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_ticket_internal_notes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id  UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  note_type  TEXT NOT NULL CHECK (note_type IN ('recepcion','tecnico','admin')),
  author_id  UUID REFERENCES sp_profiles(id),
  content    TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spin_ticket ON sp_ticket_internal_notes(ticket_id);

-- ================================================================
-- TABLA: sp_repair_diagnostics
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_repair_diagnostics (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id            UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  technician_id        UUID REFERENCES sp_profiles(id),
  diagnosis            TEXT NOT NULL,
  recommended_action   TEXT,
  is_repairable        BOOLEAN,
  diagnosis_time_hours NUMERIC(5,2),
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  updated_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER trg_sp_diag_upd
  BEFORE UPDATE ON sp_repair_diagnostics
  FOR EACH ROW EXECUTE FUNCTION sp_set_updated_at();

-- ================================================================
-- TABLA: sp_repair_quotes (cotizaciones)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_repair_quotes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id           UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  created_by          UUID REFERENCES sp_profiles(id),
  subtotal            NUMERIC(10,2) NOT NULL DEFAULT 0,
  tax_rate            NUMERIC(5,4) DEFAULT 0.15,
  tax_amount          NUMERIC(10,2) DEFAULT 0,
  total               NUMERIC(10,2) NOT NULL DEFAULT 0,
  diagnosis_fee       NUMERIC(10,2) DEFAULT 0,
  diagnosis_credited  BOOLEAN DEFAULT false,
  notes               TEXT,
  status              TEXT DEFAULT 'pendiente' CHECK (status IN (
                        'pendiente','enviada','aprobada','rechazada','vencida'
                      )),
  expires_at          TIMESTAMPTZ,
  approved_at         TIMESTAMPTZ,
  approved_by_client  BOOLEAN,
  approval_token      TEXT UNIQUE DEFAULT encode(gen_random_bytes(24), 'hex'),
  rejection_reason    TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER trg_sp_quotes_upd
  BEFORE UPDATE ON sp_repair_quotes
  FOR EACH ROW EXECUTE FUNCTION sp_set_updated_at();

-- ================================================================
-- TABLA: sp_quote_items
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_quote_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id    UUID REFERENCES sp_repair_quotes(id) ON DELETE CASCADE,
  item_type   TEXT CHECK (item_type IN ('mano_obra','repuesto','servicio','diagnostico')),
  description TEXT NOT NULL,
  quantity    NUMERIC(8,2) DEFAULT 1,
  unit_price  NUMERIC(10,2) NOT NULL,
  total_price NUMERIC(10,2) NOT NULL,
  sort_order  INTEGER DEFAULT 0
);

-- ================================================================
-- TABLA: sp_storage_charges (cobro por almacenamiento)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_storage_charges (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id      UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  fee_start_date DATE NOT NULL,
  daily_rate     NUMERIC(10,2) NOT NULL,
  days_charged   INTEGER DEFAULT 0,
  total_charged  NUMERIC(10,2) DEFAULT 0,
  is_paid        BOOLEAN DEFAULT false,
  paid_at        TIMESTAMPTZ,
  notes          TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TRIGGER trg_sp_storage_upd
  BEFORE UPDATE ON sp_storage_charges
  FOR EACH ROW EXECUTE FUNCTION sp_set_updated_at();

-- ================================================================
-- TABLA: sp_ticket_files (fotos y documentos — fase 2)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_ticket_files (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id            UUID REFERENCES sp_tickets(id) ON DELETE CASCADE,
  file_type            TEXT NOT NULL CHECK (file_type IN (
                         'foto_recepcion','foto_tecnica','foto_entrega',
                         'documento','firma','otro'
                       )),
  storage_path         TEXT NOT NULL,
  file_name            TEXT,
  file_size            INTEGER,
  uploaded_by          UUID REFERENCES sp_profiles(id),
  is_visible_to_client BOOLEAN DEFAULT false,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- TABLA: sp_notifications (log de emails)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_notifications (
  id                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  ticket_id         UUID REFERENCES sp_tickets(id),
  notification_type TEXT NOT NULL,
  recipient_email   TEXT NOT NULL,
  recipient_type    TEXT CHECK (recipient_type IN ('client','staff')),
  subject           TEXT,
  status            TEXT DEFAULT 'pendiente' CHECK (status IN (
                      'pendiente','enviado','error','omitido'
                    )),
  resend_message_id TEXT,
  sent_at           TIMESTAMPTZ,
  error_message     TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- TABLA: sp_settings (configuración global)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  description TEXT,
  updated_by  UUID REFERENCES sp_profiles(id),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO sp_settings (key, value, description) VALUES
  ('tax_enabled',        'true',         'Activar ISV en cotizaciones'),
  ('tax_rate',           '0.15',         'Tasa de ISV'),
  ('tax_name',           'ISV',          'Nombre del impuesto'),
  ('currency_symbol',    'L',            'Símbolo de moneda'),
  ('currency_code',      'HNL',          'Código de moneda'),
  ('diagnosis_fee',      '500',          'Cobro base por diagnóstico (L)'),
  ('quote_validity_days','15',           'Días hábiles de validez de cotización'),
  ('free_storage_days',  '15',           'Días calendario de almacenamiento gratuito'),
  ('second_notice_days', '30',           'Día del segundo aviso'),
  ('abandon_days',       '90',           'Días para declarar abandono'),
  ('business_name',      'Focus Store',  'Nombre del negocio'),
  ('business_phone',     '',             'Teléfono de contacto'),
  ('business_email',     '',             'Email de soporte'),
  ('business_address',   'Plaza Premier, 2do nivel · Col. Humuya · Tegucigalpa', 'Dirección'),
  ('warranty_days',      '30',           'Días de garantía por defecto'),
  ('terms_text',         'Al entregar su equipo acepta nuestra política de servicio. El diagnóstico tiene un costo que se acredita si aprueba la reparación. El cliente tiene 15 días calendario para retirar el equipo una vez notificado. Después se aplicará un costo de almacenamiento.', 'Texto de términos y condiciones')
ON CONFLICT (key) DO NOTHING;

-- ================================================================
-- TABLA: sp_storage_fee_rates (tarifas por tipo de equipo)
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_storage_fee_rates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category    TEXT NOT NULL UNIQUE,
  daily_rate  NUMERIC(10,2) NOT NULL,
  description TEXT,
  is_active   BOOLEAN DEFAULT true
);

INSERT INTO sp_storage_fee_rates (category, daily_rate, description) VALUES
  ('camara',      25, 'Cámaras DSLR, mirrorless, acción'),
  ('lente',       25, 'Lentes fotográficos y de video'),
  ('audio',       25, 'Micrófonos, grabadoras, auriculares'),
  ('flash',       25, 'Flashes portátiles y speedlites'),
  ('gimbal',      25, 'Gimbals y estabilizadores pequeños'),
  ('drone',       50, 'Drones y accesorios grandes'),
  ('luz',         50, 'Paneles LED, luces de estudio'),
  ('tripode',     50, 'Trípodes y monopies'),
  ('monitor',     50, 'Monitores y pantallas'),
  ('computadora', 50, 'Laptops y computadoras'),
  ('otro',        50, 'Equipos grandes o sin categoría')
ON CONFLICT (category) DO NOTHING;

-- ================================================================
-- TABLA: sp_service_categories
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_service_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT UNIQUE NOT NULL,
  parent_id   UUID REFERENCES sp_service_categories(id),
  icon        TEXT,
  is_active   BOOLEAN DEFAULT true,
  sort_order  INTEGER DEFAULT 0
);

INSERT INTO sp_service_categories (name, slug, icon, sort_order) VALUES
  ('Cámaras',        'camara',      '📷', 1),
  ('Lentes',         'lente',       '🔭', 2),
  ('Flashes',        'flash',       '⚡', 3),
  ('Luces LED',      'luz',         '💡', 4),
  ('Audio',          'audio',       '🎙️', 5),
  ('Gimbals',        'gimbal',      '🎬', 6),
  ('Drones',         'drone',       '🚁', 7),
  ('Computadoras',   'computadora', '💻', 8),
  ('Monitores',      'monitor',     '🖥️', 9),
  ('Trípodes',       'tripode',     '📸', 10),
  ('Otro equipo',    'otro',        '🔧', 11)
ON CONFLICT (slug) DO NOTHING;

-- ================================================================
-- TABLA: sp_audit_logs
-- ================================================================
CREATE TABLE IF NOT EXISTS sp_audit_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name  TEXT NOT NULL,
  record_id   UUID,
  action      TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE','VIEW')),
  actor_id    UUID REFERENCES sp_profiles(id),
  actor_type  TEXT CHECK (actor_type IN ('staff','client','system')),
  ip_address  TEXT,
  old_data    JSONB,
  new_data    JSONB,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spal_record  ON sp_audit_logs(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_spal_actor   ON sp_audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_spal_created ON sp_audit_logs(created_at DESC);

-- ================================================================
-- VISTA: técnico (SIN datos del cliente)
-- ================================================================
CREATE OR REPLACE VIEW sp_ticket_tecnico_view AS
  SELECT
    t.id, t.ticket_number, t.status,
    t.reported_fault, t.client_notes,
    t.estimated_ready_at, t.diagnosis_started_at,
    t.assigned_to, t.created_at, t.updated_at,
    e.category, e.subcategory, e.brand, e.model,
    e.serial_number, e.physical_condition,
    e.accessories, e.accessories_notes
  FROM sp_tickets t
  JOIN sp_equipment e ON e.id = t.equipment_id;

-- ================================================================
-- RLS — Row Level Security
-- ================================================================

-- Helper: verificar rol del staff
CREATE OR REPLACE FUNCTION sp_has_role(allowed_roles TEXT[])
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM sp_profiles
    WHERE username = current_setting('request.jwt.claims', true)::json->>'username'
    AND role = ANY(allowed_roles)
    AND is_active = true
  );
$$;

-- sp_profiles
ALTER TABLE sp_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_profiles_all_staff" ON sp_profiles FOR ALL TO anon USING (true);

-- sp_customers — técnico NO puede ver
ALTER TABLE sp_customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_customers_anon_insert" ON sp_customers FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "sp_customers_read_all"    ON sp_customers FOR SELECT TO anon USING (true);
CREATE POLICY "sp_customers_update_all"  ON sp_customers FOR UPDATE TO anon USING (true);

-- sp_equipment
ALTER TABLE sp_equipment ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_equipment_all" ON sp_equipment FOR ALL TO anon USING (true);

-- sp_tickets
ALTER TABLE sp_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_tickets_all" ON sp_tickets FOR ALL TO anon USING (true);

-- sp_ticket_status_history
ALTER TABLE sp_ticket_status_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_status_history_all" ON sp_ticket_status_history FOR ALL TO anon USING (true);

-- sp_ticket_messages
ALTER TABLE sp_ticket_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_messages_all" ON sp_ticket_messages FOR ALL TO anon USING (true);

-- sp_ticket_internal_notes
ALTER TABLE sp_ticket_internal_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_internal_notes_all" ON sp_ticket_internal_notes FOR ALL TO anon USING (true);

-- sp_repair_diagnostics
ALTER TABLE sp_repair_diagnostics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_diagnostics_all" ON sp_repair_diagnostics FOR ALL TO anon USING (true);

-- sp_repair_quotes
ALTER TABLE sp_repair_quotes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_quotes_all" ON sp_repair_quotes FOR ALL TO anon USING (true);

-- sp_quote_items
ALTER TABLE sp_quote_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_quote_items_all" ON sp_quote_items FOR ALL TO anon USING (true);

-- sp_storage_charges
ALTER TABLE sp_storage_charges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_storage_charges_all" ON sp_storage_charges FOR ALL TO anon USING (true);

-- sp_ticket_files
ALTER TABLE sp_ticket_files ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_files_all" ON sp_ticket_files FOR ALL TO anon USING (true);

-- sp_notifications
ALTER TABLE sp_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_notifications_all" ON sp_notifications FOR ALL TO anon USING (true);

-- sp_settings
ALTER TABLE sp_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_settings_read" ON sp_settings FOR SELECT TO anon USING (true);
CREATE POLICY "sp_settings_write" ON sp_settings FOR ALL TO anon USING (true);

-- sp_storage_fee_rates
ALTER TABLE sp_storage_fee_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_fee_rates_read" ON sp_storage_fee_rates FOR SELECT TO anon USING (true);

-- sp_service_categories
ALTER TABLE sp_service_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_categories_read" ON sp_service_categories FOR SELECT TO anon USING (true);

-- sp_audit_logs
ALTER TABLE sp_audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sp_audit_all" ON sp_audit_logs FOR ALL TO anon USING (true);

-- ================================================================
-- DATOS INICIALES: perfil admin
-- ================================================================
INSERT INTO sp_profiles (full_name, username, role, color, avatar)
VALUES ('Billy Estrada', 'Billy.Estrada', 'admin', '#3d6aff', 'B')
ON CONFLICT (username) DO NOTHING;
