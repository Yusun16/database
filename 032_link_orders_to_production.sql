-- Link sales orders with production orders.
-- Run after:
--   001_init_schema.sql

USE panaderia_db;

ALTER TABLE production_orders
  ADD COLUMN source_order_id BIGINT UNSIGNED NULL AFTER id,
  ADD KEY idx_production_orders_source_order (source_order_id),
  ADD CONSTRAINT fk_production_orders_source_order
    FOREIGN KEY (source_order_id) REFERENCES orders (id)
    ON DELETE SET NULL ON UPDATE CASCADE;
