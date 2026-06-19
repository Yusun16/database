-- Current recipe versions, ordered ingredients and next-day production plans.
-- Run after:
--   037_purchase_order_invoice_number.sql

USE panaderia_db;

SET @recipes_family_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipes'
    AND COLUMN_NAME = 'recipe_family_id'
);

SET @recipes_family_sql = IF(
  @recipes_family_exists = 0,
  'ALTER TABLE recipes ADD COLUMN recipe_family_id BIGINT UNSIGNED NULL AFTER id',
  'SELECT 1'
);

PREPARE recipes_family_stmt FROM @recipes_family_sql;
EXECUTE recipes_family_stmt;
DEALLOCATE PREPARE recipes_family_stmt;

SET @recipes_current_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipes'
    AND COLUMN_NAME = 'is_current'
);

SET @recipes_current_sql = IF(
  @recipes_current_exists = 0,
  'ALTER TABLE recipes ADD COLUMN is_current TINYINT(1) NOT NULL DEFAULT 1 AFTER is_active',
  'SELECT 1'
);

PREPARE recipes_current_stmt FROM @recipes_current_sql;
EXECUTE recipes_current_stmt;
DEALLOCATE PREPARE recipes_current_stmt;

DROP TEMPORARY TABLE IF EXISTS tmp_recipe_version_families;
CREATE TEMPORARY TABLE tmp_recipe_version_families AS
SELECT
  r.id,
  MIN(r.id) OVER (
    PARTITION BY COALESCE(
      CONCAT('PRODUCT:', r.product_id),
      CONCAT('NAME:', LOWER(TRIM(SUBSTRING_INDEX(COALESCE(r.notes, CONCAT('Receta #', r.id)), ' - ', 1))))
    )
  ) AS family_id,
  ROW_NUMBER() OVER (
    PARTITION BY COALESCE(
      CONCAT('PRODUCT:', r.product_id),
      CONCAT('NAME:', LOWER(TRIM(SUBSTRING_INDEX(COALESCE(r.notes, CONCAT('Receta #', r.id)), ' - ', 1))))
    )
    ORDER BY r.version_no DESC, r.created_at DESC, r.id DESC
  ) AS current_rank
FROM recipes r;

UPDATE recipes r
INNER JOIN tmp_recipe_version_families grouped ON grouped.id = r.id
SET r.recipe_family_id = grouped.family_id,
    r.is_current = IF(grouped.current_rank = 1, 1, 0),
    r.is_active = IF(grouped.current_rank = 1, 1, r.is_active)
WHERE r.id > 0;

DROP TEMPORARY TABLE IF EXISTS tmp_recipe_version_families;

SET @recipes_family_index_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipes'
    AND INDEX_NAME = 'idx_recipes_family_current'
);

SET @recipes_family_index_sql = IF(
  @recipes_family_index_exists = 0,
  'ALTER TABLE recipes ADD KEY idx_recipes_family_current (recipe_family_id, is_current, version_no)',
  'SELECT 1'
);

PREPARE recipes_family_index_stmt FROM @recipes_family_index_sql;
EXECUTE recipes_family_index_stmt;
DEALLOCATE PREPARE recipes_family_index_stmt;

SET @recipe_items_sort_order_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipe_items'
    AND COLUMN_NAME = 'sort_order'
);

SET @recipe_items_sort_order_sql = IF(
  @recipe_items_sort_order_exists = 0,
  'ALTER TABLE recipe_items ADD COLUMN sort_order INT UNSIGNED NOT NULL DEFAULT 1 AFTER wastage_percent',
  'SELECT 1'
);

PREPARE recipe_items_sort_order_stmt FROM @recipe_items_sort_order_sql;
EXECUTE recipe_items_sort_order_stmt;
DEALLOCATE PREPARE recipe_items_sort_order_stmt;

SET @recipe_items_backfill_order_sql = IF(
  @recipe_items_sort_order_exists = 0,
  'UPDATE recipe_items ri
   INNER JOIN (
     SELECT
       recipe_id,
       raw_material_id,
       ROW_NUMBER() OVER (PARTITION BY recipe_id ORDER BY raw_material_id) AS row_no
     FROM recipe_items
   ) ordered
     ON ordered.recipe_id = ri.recipe_id
    AND ordered.raw_material_id = ri.raw_material_id
   SET ri.sort_order = ordered.row_no
   WHERE ri.recipe_id > 0',
  'SELECT 1'
);

PREPARE recipe_items_backfill_order_stmt FROM @recipe_items_backfill_order_sql;
EXECUTE recipe_items_backfill_order_stmt;
DEALLOCATE PREPARE recipe_items_backfill_order_stmt;

SET @recipe_output_items_sort_order_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipe_output_items'
    AND COLUMN_NAME = 'sort_order'
);

SET @recipe_output_items_sort_order_sql = IF(
  @recipe_output_items_sort_order_exists = 0,
  'ALTER TABLE recipe_output_items ADD COLUMN sort_order INT UNSIGNED NOT NULL DEFAULT 1 AFTER wastage_percent',
  'SELECT 1'
);

PREPARE recipe_output_items_sort_order_stmt FROM @recipe_output_items_sort_order_sql;
EXECUTE recipe_output_items_sort_order_stmt;
DEALLOCATE PREPARE recipe_output_items_sort_order_stmt;

SET @recipe_output_items_backfill_order_sql = IF(
  @recipe_output_items_sort_order_exists = 0,
  'UPDATE recipe_output_items roi
   INNER JOIN (
     SELECT
       id,
       ROW_NUMBER() OVER (PARTITION BY recipe_output_id ORDER BY id) AS row_no
     FROM recipe_output_items
   ) ordered ON ordered.id = roi.id
   SET roi.sort_order = ordered.row_no
   WHERE roi.id > 0',
  'SELECT 1'
);

PREPARE recipe_output_items_backfill_order_stmt FROM @recipe_output_items_backfill_order_sql;
EXECUTE recipe_output_items_backfill_order_stmt;
DEALLOCATE PREPARE recipe_output_items_backfill_order_stmt;

CREATE TABLE IF NOT EXISTS production_plans (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  branch_id BIGINT UNSIGNED NOT NULL,
  planned_date DATE NOT NULL,
  baker_employee_id BIGINT UNSIGNED NOT NULL,
  status ENUM('assigned','viewed','completed','cancelled') NOT NULL DEFAULT 'assigned',
  notes VARCHAR(255) NULL,
  viewed_at TIMESTAMP NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_plans_date_baker (planned_date, baker_employee_id),
  KEY idx_production_plans_branch (branch_id),
  KEY idx_production_plans_status (status),
  CONSTRAINT fk_production_plans_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_plans_baker
    FOREIGN KEY (baker_employee_id) REFERENCES employees (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_plans_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS production_plan_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_plan_id BIGINT UNSIGNED NOT NULL,
  recipe_id BIGINT UNSIGNED NOT NULL,
  arrobas DECIMAL(14,3) NOT NULL,
  sort_order INT UNSIGNED NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_plan_items_plan (production_plan_id, sort_order),
  KEY idx_production_plan_items_recipe (recipe_id),
  CONSTRAINT fk_production_plan_items_plan
    FOREIGN KEY (production_plan_id) REFERENCES production_plans (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_production_plan_items_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_production_plan_items_arrobas CHECK (arrobas > 0)
) ENGINE=InnoDB;

SET @production_plan_items_batch_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_plan_items'
    AND COLUMN_NAME = 'production_batch_id'
);

SET @production_plan_items_batch_sql = IF(
  @production_plan_items_batch_exists = 0,
  'ALTER TABLE production_plan_items
     ADD COLUMN production_batch_id BIGINT UNSIGNED NULL AFTER recipe_id,
     ADD KEY idx_production_plan_items_batch (production_batch_id),
     ADD CONSTRAINT fk_production_plan_items_batch
       FOREIGN KEY (production_batch_id) REFERENCES production_batches (id)
       ON DELETE RESTRICT ON UPDATE CASCADE',
  'SELECT 1'
);

PREPARE production_plan_items_batch_stmt FROM @production_plan_items_batch_sql;
EXECUTE production_plan_items_batch_stmt;
DEALLOCATE PREPARE production_plan_items_batch_stmt;

SET @production_plan_items_started_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_plan_items'
    AND COLUMN_NAME = 'started_at'
);

SET @production_plan_items_started_sql = IF(
  @production_plan_items_started_exists = 0,
  'ALTER TABLE production_plan_items
     ADD COLUMN started_at TIMESTAMP NULL AFTER sort_order,
     ADD COLUMN finished_at TIMESTAMP NULL AFTER started_at',
  'SELECT 1'
);

PREPARE production_plan_items_started_stmt FROM @production_plan_items_started_sql;
EXECUTE production_plan_items_started_stmt;
DEALLOCATE PREPARE production_plan_items_started_stmt;

CREATE TABLE IF NOT EXISTS production_plan_outputs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_plan_item_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  expected_quantity DECIMAL(14,3) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_production_plan_output_product (production_plan_item_id, product_id),
  KEY idx_production_plan_outputs_product (product_id),
  CONSTRAINT fk_production_plan_outputs_item
    FOREIGN KEY (production_plan_item_id) REFERENCES production_plan_items (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_production_plan_outputs_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_production_plan_outputs_qty CHECK (expected_quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS user_notifications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  notification_type VARCHAR(60) NOT NULL,
  title VARCHAR(150) NOT NULL,
  message VARCHAR(255) NOT NULL,
  reference_type VARCHAR(60) NULL,
  reference_id BIGINT UNSIGNED NULL,
  viewed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_user_notifications_user_viewed (user_id, viewed_at, created_at),
  KEY idx_user_notifications_reference (reference_type, reference_id),
  CONSTRAINT fk_user_notifications_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
