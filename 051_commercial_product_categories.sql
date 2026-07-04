-- Commercial product categories for order capture.
-- Run after:
--   050_packaging_inventory.sql

USE panaderia_db;

INSERT INTO product_categories (name, description, is_active)
VALUES
  ('Pan de sal', 'Categoria comercial para panes de sal', 1),
  ('Pan de dulce', 'Categoria comercial para panes de dulce', 1),
  ('Pasteleria', 'Categoria comercial para productos de pasteleria', 1),
  ('Integral', 'Categoria comercial para productos integrales', 1),
  ('Tostados', 'Categoria comercial para productos tostados', 1)
ON DUPLICATE KEY UPDATE
  description = VALUES(description),
  is_active = 1;
