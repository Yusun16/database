-- Pidomi Panaderia - Reporting views (Phase E)
-- MySQL 8+

USE panaderia_db;

DROP VIEW IF EXISTS vw_sales_daily;
CREATE VIEW vw_sales_daily AS
SELECT
  o.branch_id,
  o.order_date,
  COUNT(*) AS orders_count,
  ROUND(SUM(o.subtotal), 2) AS subtotal,
  ROUND(SUM(o.tax_total), 2) AS tax_total,
  ROUND(SUM(o.grand_total), 2) AS grand_total
FROM orders o
WHERE o.status IN ('dispatched', 'delivered')
GROUP BY o.branch_id, o.order_date;

DROP VIEW IF EXISTS vw_sales_by_customer_daily;
CREATE VIEW vw_sales_by_customer_daily AS
SELECT
  o.branch_id,
  o.customer_id,
  o.order_date,
  COUNT(*) AS orders_count,
  ROUND(SUM(o.grand_total), 2) AS total_sales
FROM orders o
WHERE o.status IN ('dispatched', 'delivered')
GROUP BY o.branch_id, o.customer_id, o.order_date;

DROP VIEW IF EXISTS vw_top_products_30d;
CREATE VIEW vw_top_products_30d AS
SELECT
  o.branch_id,
  oi.product_id,
  p.name AS product_name,
  ROUND(SUM(oi.quantity), 3) AS qty_sold,
  ROUND(SUM(oi.line_total), 2) AS total_sales
FROM order_items oi
INNER JOIN orders o ON o.id = oi.order_id
INNER JOIN products p ON p.id = oi.product_id
WHERE o.status IN ('dispatched', 'delivered')
  AND o.order_date >= (CURRENT_DATE - INTERVAL 30 DAY)
GROUP BY o.branch_id, oi.product_id, p.name;

DROP VIEW IF EXISTS vw_production_daily;
CREATE VIEW vw_production_daily AS
SELECT
  po.branch_id,
  po.planned_date,
  COUNT(DISTINCT po.id) AS production_orders_count,
  COUNT(poi.id) AS production_items_count,
  ROUND(SUM(poi.planned_qty), 3) AS planned_qty,
  ROUND(SUM(poi.produced_qty), 3) AS produced_qty
FROM production_orders po
LEFT JOIN production_order_items poi ON poi.production_order_id = po.id
WHERE po.status IN ('in_progress', 'completed')
GROUP BY po.branch_id, po.planned_date;

DROP VIEW IF EXISTS vw_purchase_daily;
CREATE VIEW vw_purchase_daily AS
SELECT
  po.branch_id,
  po.order_date,
  COUNT(*) AS purchase_orders_count,
  ROUND(SUM(po.subtotal), 2) AS subtotal,
  ROUND(SUM(po.tax_total), 2) AS tax_total,
  ROUND(SUM(po.grand_total), 2) AS grand_total
FROM purchase_orders po
WHERE po.status IN ('partially_received', 'received')
GROUP BY po.branch_id, po.order_date;

DROP VIEW IF EXISTS vw_inventory_current_raw;
CREATE VIEW vw_inventory_current_raw AS
SELECT
  srm.branch_id,
  srm.raw_material_id,
  rm.sku,
  rm.name,
  rm.unit,
  srm.quantity_on_hand,
  srm.min_stock,
  (srm.quantity_on_hand - srm.min_stock) AS stock_gap,
  CASE
    WHEN srm.quantity_on_hand < srm.min_stock THEN 1
    ELSE 0
  END AS is_below_min_stock,
  srm.updated_at
FROM stock_raw_materials srm
INNER JOIN raw_materials rm ON rm.id = srm.raw_material_id;

DROP VIEW IF EXISTS vw_inventory_current_products;
CREATE VIEW vw_inventory_current_products AS
SELECT
  sp.branch_id,
  sp.product_id,
  p.sku,
  p.name,
  p.unit,
  sp.quantity_on_hand,
  sp.min_stock,
  (sp.quantity_on_hand - sp.min_stock) AS stock_gap,
  CASE
    WHEN sp.quantity_on_hand < sp.min_stock THEN 1
    ELSE 0
  END AS is_below_min_stock,
  sp.updated_at
FROM stock_products sp
INNER JOIN products p ON p.id = sp.product_id;

DROP VIEW IF EXISTS vw_inventory_movements_daily;
CREATE VIEW vw_inventory_movements_daily AS
SELECT
  im.branch_id,
  DATE(im.moved_at) AS moved_date,
  im.item_type,
  im.movement_type,
  COUNT(*) AS movements_count,
  ROUND(SUM(im.quantity), 3) AS total_quantity
FROM inventory_movements im
GROUP BY im.branch_id, DATE(im.moved_at), im.item_type, im.movement_type;

DROP VIEW IF EXISTS vw_audit_recent;
CREATE VIEW vw_audit_recent AS
SELECT
  al.id,
  al.created_at,
  al.actor_user_id,
  u.username,
  al.action,
  al.entity_name,
  al.entity_id,
  al.ip_address
FROM audit_logs al
LEFT JOIN users u ON u.id = al.actor_user_id;
