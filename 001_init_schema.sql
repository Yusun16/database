-- Pidomi Panaderia - Initial MySQL 8 schema
-- Target: React + Node + MySQL migration
-- Notes:
-- 1) Use MySQL 8.0+
-- 2) Run in a controlled environment (dev/staging first)
-- 3) Password hashes are stored from app layer (Argon2id recommended)

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS panaderia_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE panaderia_db;

-- =========================
-- Security and access model
-- =========================

CREATE TABLE roles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(50) NOT NULL,
  name VARCHAR(100) NOT NULL,
  description VARCHAR(255) NULL,
  is_system_role TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_code (code)
) ENGINE=InnoDB;

CREATE TABLE permissions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(100) NOT NULL,
  name VARCHAR(150) NOT NULL,
  description VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permissions_code (code)
) ENGINE=InnoDB;

CREATE TABLE role_permissions (
  role_id BIGINT UNSIGNED NOT NULL,
  permission_id BIGINT UNSIGNED NOT NULL,
  granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_role_permissions_role
    FOREIGN KEY (role_id) REFERENCES roles (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_role_permissions_permission
    FOREIGN KEY (permission_id) REFERENCES permissions (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username VARCHAR(60) NOT NULL,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  password_algo VARCHAR(30) NOT NULL DEFAULT 'argon2id',
  full_name VARCHAR(150) NOT NULL,
  phone VARCHAR(30) NULL,
  status ENUM('active','inactive','blocked') NOT NULL DEFAULT 'active',
  must_change_password TINYINT(1) NOT NULL DEFAULT 0,
  last_login_at TIMESTAMP NULL,
  password_changed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_username (username),
  UNIQUE KEY uq_users_email (email),
  KEY idx_users_status (status)
) ENGINE=InnoDB;

CREATE TABLE user_roles (
  user_id BIGINT UNSIGNED NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, role_id),
  CONSTRAINT fk_user_roles_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_user_roles_role
    FOREIGN KEY (role_id) REFERENCES roles (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE user_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  refresh_token_hash CHAR(64) NOT NULL,
  user_agent VARCHAR(255) NULL,
  ip_address VARCHAR(45) NULL,
  expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_user_sessions_refresh_hash (refresh_token_hash),
  KEY idx_user_sessions_user (user_id),
  KEY idx_user_sessions_expires (expires_at),
  CONSTRAINT fk_user_sessions_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE login_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL,
  email_or_username VARCHAR(255) NOT NULL,
  ip_address VARCHAR(45) NULL,
  success TINYINT(1) NOT NULL,
  attempted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_login_attempts_principal_time (email_or_username, attempted_at),
  KEY idx_login_attempts_ip_time (ip_address, attempted_at),
  CONSTRAINT fk_login_attempts_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  actor_user_id BIGINT UNSIGNED NULL,
  action VARCHAR(100) NOT NULL,
  entity_name VARCHAR(100) NOT NULL,
  entity_id VARCHAR(100) NULL,
  ip_address VARCHAR(45) NULL,
  user_agent VARCHAR(255) NULL,
  metadata_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_audit_logs_actor_time (actor_user_id, created_at),
  KEY idx_audit_logs_entity (entity_name, entity_id),
  CONSTRAINT fk_audit_logs_actor
    FOREIGN KEY (actor_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- =================
-- Master data tables
-- =================

CREATE TABLE branches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(30) NOT NULL,
  name VARCHAR(120) NOT NULL,
  address VARCHAR(255) NULL,
  phone VARCHAR(30) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_branches_code (code)
) ENGINE=InnoDB;

CREATE TABLE tax_rates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(30) NOT NULL,
  name VARCHAR(100) NOT NULL,
  rate_percent DECIMAL(5,2) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_tax_rates_code (code),
  CONSTRAINT chk_tax_rates_rate_percent CHECK (rate_percent >= 0 AND rate_percent <= 100)
) ENGINE=InnoDB;

CREATE TABLE product_categories (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  description VARCHAR(255) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_product_categories_name (name)
) ENGINE=InnoDB;

CREATE TABLE products (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sku VARCHAR(60) NOT NULL,
  name VARCHAR(150) NOT NULL,
  description VARCHAR(255) NULL,
  category_id BIGINT UNSIGNED NOT NULL,
  tax_rate_id BIGINT UNSIGNED NOT NULL,
  unit ENUM('unit','kg','g','lb','l','ml','tray') NOT NULL DEFAULT 'unit',
  base_price DECIMAL(12,2) NOT NULL,
  min_stock DECIMAL(12,3) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_products_sku (sku),
  KEY idx_products_category (category_id),
  CONSTRAINT fk_products_category
    FOREIGN KEY (category_id) REFERENCES product_categories (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_products_tax_rate
    FOREIGN KEY (tax_rate_id) REFERENCES tax_rates (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_products_base_price CHECK (base_price >= 0),
  CONSTRAINT chk_products_min_stock CHECK (min_stock >= 0)
) ENGINE=InnoDB;

CREATE TABLE raw_material_categories (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  description VARCHAR(255) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_raw_material_categories_name (name)
) ENGINE=InnoDB;

CREATE TABLE suppliers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tax_id VARCHAR(30) NULL,
  name VARCHAR(150) NOT NULL,
  email VARCHAR(255) NULL,
  phone VARCHAR(30) NULL,
  address VARCHAR(255) NULL,
  contact_name VARCHAR(120) NULL,
  status ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_suppliers_tax_id (tax_id),
  KEY idx_suppliers_status (status)
) ENGINE=InnoDB;

CREATE TABLE raw_materials (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sku VARCHAR(60) NOT NULL,
  name VARCHAR(150) NOT NULL,
  description VARCHAR(255) NULL,
  category_id BIGINT UNSIGNED NOT NULL,
  supplier_id BIGINT UNSIGNED NULL,
  unit ENUM('kg','g','lb','l','ml','unit','box','bag') NOT NULL,
  purchase_package_name VARCHAR(60) NULL,
  purchase_package_quantity DECIMAL(14,3) NULL,
  unit_cost DECIMAL(12,4) NOT NULL,
  min_stock DECIMAL(12,3) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_raw_materials_sku (sku),
  KEY idx_raw_materials_category (category_id),
  KEY idx_raw_materials_supplier (supplier_id),
  CONSTRAINT fk_raw_materials_category
    FOREIGN KEY (category_id) REFERENCES raw_material_categories (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_raw_materials_supplier
    FOREIGN KEY (supplier_id) REFERENCES suppliers (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_raw_materials_purchase_package_quantity CHECK (purchase_package_quantity IS NULL OR purchase_package_quantity > 0),
  CONSTRAINT chk_raw_materials_unit_cost CHECK (unit_cost >= 0),
  CONSTRAINT chk_raw_materials_min_stock CHECK (min_stock >= 0)
) ENGINE=InnoDB;

CREATE TABLE recipes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_id BIGINT UNSIGNED NOT NULL,
  version_no INT UNSIGNED NOT NULL DEFAULT 1,
  output_quantity DECIMAL(12,3) NOT NULL DEFAULT 1,
  notes VARCHAR(255) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipes_product_version (product_id, version_no),
  CONSTRAINT fk_recipes_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_recipes_output_quantity CHECK (output_quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE recipe_items (
  recipe_id BIGINT UNSIGNED NOT NULL,
  raw_material_id BIGINT UNSIGNED NOT NULL,
  quantity DECIMAL(12,4) NOT NULL,
  wastage_percent DECIMAL(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (recipe_id, raw_material_id),
  CONSTRAINT fk_recipe_items_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_recipe_items_raw_material
    FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_recipe_items_quantity CHECK (quantity > 0),
  CONSTRAINT chk_recipe_items_wastage CHECK (wastage_percent >= 0 AND wastage_percent <= 100)
) ENGINE=InnoDB;

CREATE TABLE customers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tax_id VARCHAR(30) NULL,
  name VARCHAR(150) NOT NULL,
  email VARCHAR(255) NULL,
  phone VARCHAR(30) NULL,
  address VARCHAR(255) NULL,
  status ENUM('active','inactive') NOT NULL DEFAULT 'active',
  credit_limit DECIMAL(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_customers_tax_id (tax_id),
  KEY idx_customers_status (status),
  CONSTRAINT chk_customers_credit_limit CHECK (credit_limit >= 0)
) ENGINE=InnoDB;

CREATE TABLE delivery_routes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(30) NOT NULL,
  name VARCHAR(120) NOT NULL,
  description VARCHAR(255) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_delivery_routes_code (code)
) ENGINE=InnoDB;

CREATE TABLE route_drivers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  route_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  assigned_from DATE NOT NULL,
  assigned_to DATE NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_route_drivers_route (route_id),
  KEY idx_route_drivers_user (user_id),
  CONSTRAINT fk_route_drivers_route
    FOREIGN KEY (route_id) REFERENCES delivery_routes (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_route_drivers_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_route_drivers_dates CHECK (assigned_to IS NULL OR assigned_to >= assigned_from)
) ENGINE=InnoDB;

-- =================
-- Sales and ordering
-- =================

CREATE TABLE orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  branch_id BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  route_id BIGINT UNSIGNED NULL,
  order_date DATE NOT NULL,
  delivery_date DATE NULL,
  status ENUM('draft','confirmed','in_production','ready','dispatched','delivered','cancelled') NOT NULL DEFAULT 'draft',
  subtotal DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_orders_branch_date (branch_id, order_date),
  KEY idx_orders_customer (customer_id),
  KEY idx_orders_status (status),
  CONSTRAINT fk_orders_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_orders_route
    FOREIGN KEY (route_id) REFERENCES delivery_routes (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_orders_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_orders_amounts CHECK (
    subtotal >= 0 AND tax_total >= 0 AND grand_total >= 0
  )
) ENGINE=InnoDB;

CREATE TABLE order_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  quantity DECIMAL(12,3) NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  tax_percent DECIMAL(5,2) NOT NULL,
  line_subtotal DECIMAL(12,2) NOT NULL,
  line_tax DECIMAL(12,2) NOT NULL,
  line_total DECIMAL(12,2) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_order_items_order_product (order_id, product_id),
  KEY idx_order_items_product (product_id),
  CONSTRAINT fk_order_items_order
    FOREIGN KEY (order_id) REFERENCES orders (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_order_items_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_order_items_quantity CHECK (quantity > 0),
  CONSTRAINT chk_order_items_amounts CHECK (
    unit_price >= 0 AND tax_percent >= 0 AND tax_percent <= 100
    AND line_subtotal >= 0 AND line_tax >= 0 AND line_total >= 0
  )
) ENGINE=InnoDB;

-- =====================
-- Production operations
-- =====================

CREATE TABLE production_orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  branch_id BIGINT UNSIGNED NOT NULL,
  planned_date DATE NOT NULL,
  status ENUM('draft','planned','in_progress','completed','cancelled') NOT NULL DEFAULT 'draft',
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_orders_branch_date (branch_id, planned_date),
  KEY idx_production_orders_status (status),
  CONSTRAINT fk_production_orders_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_orders_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE production_order_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_order_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  recipe_id BIGINT UNSIGNED NULL,
  planned_qty DECIMAL(12,3) NOT NULL,
  produced_qty DECIMAL(12,3) NOT NULL DEFAULT 0,
  status ENUM('pending','in_progress','done','cancelled') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_prod_order_items_order (production_order_id),
  KEY idx_prod_order_items_product (product_id),
  CONSTRAINT fk_prod_order_items_order
    FOREIGN KEY (production_order_id) REFERENCES production_orders (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_prod_order_items_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_prod_order_items_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_prod_order_items_qty CHECK (
    planned_qty > 0 AND produced_qty >= 0
  )
) ENGINE=InnoDB;

-- =====================
-- Purchasing and stock
-- =====================

CREATE TABLE purchase_orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  branch_id BIGINT UNSIGNED NOT NULL,
  supplier_id BIGINT UNSIGNED NOT NULL,
  invoice_number VARCHAR(80) NULL,
  order_date DATE NOT NULL,
  expected_date DATE NULL,
  status ENUM('draft','sent','partially_received','received','cancelled') NOT NULL DEFAULT 'draft',
  subtotal DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_purchase_orders_branch_date (branch_id, order_date),
  KEY idx_purchase_orders_supplier (supplier_id),
  KEY idx_purchase_orders_status (status),
  CONSTRAINT fk_purchase_orders_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_purchase_orders_supplier
    FOREIGN KEY (supplier_id) REFERENCES suppliers (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_purchase_orders_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_purchase_orders_amounts CHECK (
    subtotal >= 0 AND tax_total >= 0 AND grand_total >= 0
  )
) ENGINE=InnoDB;

CREATE TABLE purchase_order_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  purchase_order_id BIGINT UNSIGNED NOT NULL,
  raw_material_id BIGINT UNSIGNED NOT NULL,
  quantity DECIMAL(12,3) NOT NULL,
  unit_cost DECIMAL(12,4) NOT NULL,
  tax_percent DECIMAL(5,2) NOT NULL DEFAULT 0,
  line_subtotal DECIMAL(12,2) NOT NULL,
  line_tax DECIMAL(12,2) NOT NULL,
  line_total DECIMAL(12,2) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_purchase_order_items_po (purchase_order_id),
  KEY idx_purchase_order_items_material (raw_material_id),
  CONSTRAINT fk_purchase_order_items_po
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_purchase_order_items_material
    FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_purchase_order_items_amounts CHECK (
    quantity > 0 AND unit_cost >= 0
    AND tax_percent >= 0 AND tax_percent <= 100
    AND line_subtotal >= 0 AND line_tax >= 0 AND line_total >= 0
  )
) ENGINE=InnoDB;

CREATE TABLE stock_raw_materials (
  branch_id BIGINT UNSIGNED NOT NULL,
  raw_material_id BIGINT UNSIGNED NOT NULL,
  quantity_on_hand DECIMAL(14,3) NOT NULL DEFAULT 0,
  min_stock DECIMAL(14,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (branch_id, raw_material_id),
  CONSTRAINT fk_stock_raw_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_stock_raw_material
    FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_stock_raw_values CHECK (quantity_on_hand >= 0 AND min_stock >= 0)
) ENGINE=InnoDB;

CREATE TABLE stock_products (
  branch_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  quantity_on_hand DECIMAL(14,3) NOT NULL DEFAULT 0,
  min_stock DECIMAL(14,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (branch_id, product_id),
  CONSTRAINT fk_stock_products_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_stock_products_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_stock_products_values CHECK (quantity_on_hand >= 0 AND min_stock >= 0)
) ENGINE=InnoDB;

CREATE TABLE inventory_movements (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  branch_id BIGINT UNSIGNED NOT NULL,
  item_type ENUM('raw_material','product') NOT NULL,
  raw_material_id BIGINT UNSIGNED NULL,
  product_id BIGINT UNSIGNED NULL,
  movement_type ENUM('purchase_in','production_in','production_out','sale_out','adjustment_in','adjustment_out','waste_out') NOT NULL,
  quantity DECIMAL(14,3) NOT NULL,
  unit_cost DECIMAL(12,4) NULL,
  reference_type VARCHAR(50) NULL,
  reference_id BIGINT UNSIGNED NULL,
  notes VARCHAR(255) NULL,
  moved_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  KEY idx_inventory_movements_branch_time (branch_id, moved_at),
  KEY idx_inventory_movements_item_raw (raw_material_id),
  KEY idx_inventory_movements_item_product (product_id),
  KEY idx_inventory_movements_type (movement_type),
  CONSTRAINT fk_inventory_movements_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_inventory_movements_raw
    FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_inventory_movements_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_inventory_movements_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_inventory_movements_quantity CHECK (quantity > 0),
  CONSTRAINT chk_inventory_movements_item_ref CHECK (
    (item_type = 'raw_material' AND raw_material_id IS NOT NULL AND product_id IS NULL)
    OR
    (item_type = 'product' AND product_id IS NOT NULL AND raw_material_id IS NULL)
  )
) ENGINE=InnoDB;

-- =====================
-- Messaging / utilities
-- =====================

CREATE TABLE system_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  channel ENUM('sms','email','internal') NOT NULL,
  recipient VARCHAR(255) NOT NULL,
  subject VARCHAR(150) NULL,
  body TEXT NOT NULL,
  status ENUM('pending','sent','failed') NOT NULL DEFAULT 'pending',
  error_message VARCHAR(255) NULL,
  sent_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  KEY idx_system_messages_status_created (status, created_at),
  CONSTRAINT fk_system_messages_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ============
-- Seed minima
-- ============

INSERT INTO roles (code, name, description, is_system_role)
VALUES
  ('SUPER_ADMIN', 'Super Administrador', 'Acceso total al sistema', 1),
  ('ADMIN', 'Administrador', 'Gestion operativa y administrativa', 1),
  ('PRODUCCION', 'Produccion', 'Gestion de produccion y recetas', 1),
  ('INVENTARIO', 'Inventario', 'Gestion de compras y movimientos', 1),
  ('VENTAS', 'Ventas', 'Gestion de clientes y pedidos', 1)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

INSERT INTO permissions (code, name, description)
VALUES
  ('users.manage', 'Gestionar usuarios', 'Crear, editar y desactivar usuarios'),
  ('roles.manage', 'Gestionar roles', 'Asignar roles y permisos'),
  ('products.manage', 'Gestionar productos', 'CRUD de productos y categorias'),
  ('materials.manage', 'Gestionar materias primas', 'CRUD de materias primas'),
  ('customers.manage', 'Gestionar clientes', 'Crear, editar y desactivar clientes'),
  ('routes.manage', 'Gestionar rutas', 'Crear, editar y asignar repartidores a rutas'),
  ('recipes.manage', 'Gestionar recetas', 'CRUD de recetas e ingredientes'),
  ('orders.manage', 'Gestionar pedidos', 'Crear y administrar pedidos'),
  ('production.manage', 'Gestionar produccion', 'Planificar y registrar produccion'),
  ('inventory.manage', 'Gestionar inventario', 'Movimientos y stock'),
  ('reports.view', 'Ver reportes', 'Visualizar reportes operativos y ventas')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code = 'SUPER_ADMIN';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN (
    'users.manage',
    'roles.manage',
    'products.manage',
    'materials.manage',
    'customers.manage',
    'routes.manage',
    'recipes.manage',
    'orders.manage',
    'production.manage',
    'inventory.manage',
    'reports.view'
  )
WHERE r.code = 'ADMIN';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('customers.manage', 'routes.manage', 'orders.manage', 'reports.view')
WHERE r.code = 'VENTAS';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('production.manage', 'recipes.manage', 'reports.view')
WHERE r.code = 'PRODUCCION';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('inventory.manage', 'materials.manage', 'products.manage', 'reports.view')
WHERE r.code = 'INVENTARIO';

-- ===============================
-- Recommended DB security baseline
-- ===============================
-- Create dedicated application user with least privilege (replace password).
-- CREATE USER IF NOT EXISTS 'panaderia_app'@'%' IDENTIFIED BY 'REPLACE_WITH_STRONG_PASSWORD';
-- GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON panaderia_db.* TO 'panaderia_app'@'%';
-- FLUSH PRIVILEGES;
