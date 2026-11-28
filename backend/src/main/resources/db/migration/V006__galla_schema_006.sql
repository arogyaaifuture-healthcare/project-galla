CREATE TABLE outlet_notification_settings (
  outlet_id uuid PRIMARY KEY REFERENCES outlets(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  customer_channel_priority text[] NOT NULL DEFAULT '{WHATSAPP,SMS,EMAIL}',  -- first usable channel wins
  notify_on_placed boolean NOT NULL DEFAULT true,
  notify_on_picked_up boolean NOT NULL DEFAULT true,
  notify_on_arriving boolean NOT NULL DEFAULT true,
  notify_on_delivered boolean NOT NULL DEFAULT true,
  arriving_radius_m int NOT NULL DEFAULT 150 CHECK (arriving_radius_m BETWEEN 50 AND 1000),
  avg_speed_kmph int NOT NULL DEFAULT 20 CHECK (avg_speed_kmph BETWEEN 5 AND 80)
);
