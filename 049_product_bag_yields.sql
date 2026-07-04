-- Product yield per flour bag.
-- Run after:
--   048_custom_employee_job_titles.sql

USE panaderia_db;

SET @products_units_per_bag_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'products'
    AND COLUMN_NAME = 'units_per_bag'
);

SET @products_units_per_bag_sql = IF(
  @products_units_per_bag_exists = 0,
  'ALTER TABLE products
     ADD COLUMN units_per_bag DECIMAL(14,3) NULL AFTER min_stock',
  'SELECT 1'
);

PREPARE products_units_per_bag_stmt FROM @products_units_per_bag_sql;
EXECUTE products_units_per_bag_stmt;
DEALLOCATE PREPARE products_units_per_bag_stmt;

SET @products_units_per_bag_check_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'products'
    AND CONSTRAINT_NAME = 'chk_products_units_per_bag'
);

SET @products_units_per_bag_check_sql = IF(
  @products_units_per_bag_check_exists = 0,
  'ALTER TABLE products
     ADD CONSTRAINT chk_products_units_per_bag
     CHECK (units_per_bag IS NULL OR units_per_bag > 0)',
  'SELECT 1'
);

PREPARE products_units_per_bag_check_stmt FROM @products_units_per_bag_check_sql;
EXECUTE products_units_per_bag_check_stmt;
DEALLOCATE PREPARE products_units_per_bag_check_stmt;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_product_create $$
CREATE PROCEDURE sp_product_create(
  IN p_sku VARCHAR(60),
  IN p_name VARCHAR(150),
  IN p_description VARCHAR(255),
  IN p_category_id BIGINT UNSIGNED,
  IN p_tax_rate_id BIGINT UNSIGNED,
  IN p_unit VARCHAR(20),
  IN p_base_price DECIMAL(12,2),
  IN p_min_stock DECIMAL(12,3),
  IN p_units_per_bag DECIMAL(14,3),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED;

  IF p_base_price < 0 OR p_min_stock < 0 THEN
    SET o_code = 0;
    SET o_message = 'base_price y min_stock deben ser >= 0';
    SET o_data_json = NULL;
  ELSEIF p_units_per_bag IS NOT NULL AND p_units_per_bag <= 0 THEN
    SET o_code = 0;
    SET o_message = 'unidades por bulto debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM product_categories WHERE id = p_category_id AND is_active = 1) THEN
    SET o_code = 0;
    SET o_message = 'categoria de producto no encontrada o inactiva';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM tax_rates WHERE id = p_tax_rate_id AND is_active = 1) THEN
    SET o_code = 0;
    SET o_message = 'tasa de impuesto no encontrada o inactiva';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM products WHERE sku = TRIM(p_sku)) THEN
    SET o_code = 0;
    SET o_message = 'el sku de producto ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO products (
      sku, name, description, category_id, tax_rate_id, unit,
      base_price, min_stock, units_per_bag, is_active
    ) VALUES (
      TRIM(p_sku), TRIM(p_name), p_description, p_category_id, p_tax_rate_id,
      p_unit, p_base_price, p_min_stock, p_units_per_bag, IFNULL(p_is_active, 1)
    );

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'product.create',
      'products',
      CAST(v_id AS CHAR),
      JSON_OBJECT('units_per_bag', p_units_per_bag)
    );

    SET o_code = 1;
    SET o_message = 'producto creado';
    SET o_data_json = JSON_OBJECT('product_id', v_id, 'sku', TRIM(p_sku));
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_product_update $$
CREATE PROCEDURE sp_product_update(
  IN p_product_id BIGINT UNSIGNED,
  IN p_name VARCHAR(150),
  IN p_description VARCHAR(255),
  IN p_category_id BIGINT UNSIGNED,
  IN p_tax_rate_id BIGINT UNSIGNED,
  IN p_unit VARCHAR(20),
  IN p_base_price DECIMAL(12,2),
  IN p_min_stock DECIMAL(12,3),
  IN p_units_per_bag DECIMAL(14,3),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_base_price < 0 OR p_min_stock < 0 THEN
    SET o_code = 0;
    SET o_message = 'base_price y min_stock deben ser >= 0';
    SET o_data_json = NULL;
  ELSEIF p_units_per_bag IS NOT NULL AND p_units_per_bag <= 0 THEN
    SET o_code = 0;
    SET o_message = 'unidades por bulto debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM product_categories WHERE id = p_category_id) THEN
    SET o_code = 0;
    SET o_message = 'categoria de producto no encontrada';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM tax_rates WHERE id = p_tax_rate_id) THEN
    SET o_code = 0;
    SET o_message = 'tasa de impuesto no encontrada';
    SET o_data_json = NULL;
  ELSE
    UPDATE products
    SET name = TRIM(p_name),
        description = p_description,
        category_id = p_category_id,
        tax_rate_id = p_tax_rate_id,
        unit = p_unit,
        base_price = p_base_price,
        min_stock = p_min_stock,
        units_per_bag = p_units_per_bag,
        is_active = IFNULL(p_is_active, is_active),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_product_id
      AND deleted_at IS NULL;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'producto no encontrado';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'product.update',
        'products',
        CAST(p_product_id AS CHAR),
        JSON_OBJECT('units_per_bag', p_units_per_bag)
      );

      SET o_code = 1;
      SET o_message = 'producto actualizado';
      SET o_data_json = JSON_OBJECT('product_id', p_product_id);
    END IF;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_product_yield_update $$
CREATE PROCEDURE sp_product_yield_update(
  IN p_product_id BIGINT UNSIGNED,
  IN p_units_per_bag DECIMAL(14,3),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_units_per_bag IS NULL OR p_units_per_bag <= 0 THEN
    SET o_code = 0;
    SET o_message = 'unidades por bulto debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSE
    UPDATE products
    SET units_per_bag = p_units_per_bag,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_product_id
      AND deleted_at IS NULL;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'producto no encontrado';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'product.yield.update',
        'products',
        CAST(p_product_id AS CHAR),
        JSON_OBJECT('units_per_bag', p_units_per_bag)
      );

      SET o_code = 1;
      SET o_message = 'rendimiento por bulto actualizado';
      SET o_data_json = JSON_OBJECT('product_id', p_product_id, 'units_per_bag', p_units_per_bag);
    END IF;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_product_list $$
CREATE PROCEDURE sp_product_list(
  IN p_only_active TINYINT,
  IN p_category_id BIGINT UNSIGNED,
  IN p_search VARCHAR(120),
  IN p_page INT,
  IN p_page_size INT,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_total BIGINT DEFAULT 0;
  DECLARE v_items_json LONGTEXT;
  DECLARE v_page INT DEFAULT 1;
  DECLARE v_page_size INT DEFAULT 20;
  DECLARE v_offset INT DEFAULT 0;

  SET v_page = IFNULL(NULLIF(p_page, 0), 1);
  IF v_page < 1 THEN
    SET v_page = 1;
  END IF;

  SET v_page_size = IFNULL(NULLIF(p_page_size, 0), 20);
  IF v_page_size < 1 THEN
    SET v_page_size = 20;
  ELSEIF v_page_size > 200 THEN
    SET v_page_size = 200;
  END IF;

  SET v_offset = (v_page - 1) * v_page_size;

  SELECT COUNT(*)
    INTO v_total
  FROM products p
  WHERE p.deleted_at IS NULL
    AND (IFNULL(p_only_active, 0) = 0 OR p.is_active = 1)
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
    AND (
      p_search IS NULL OR p_search = ''
      OR p.sku LIKE CONCAT('%', p_search, '%')
      OR p.name LIKE CONCAT('%', p_search, '%')
    );

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', x.id,
             'sku', x.sku,
             'name', x.name,
             'description', x.description,
             'category_id', x.category_id,
             'tax_rate_id', x.tax_rate_id,
             'unit', x.unit,
             'base_price', x.base_price,
             'min_stock', x.min_stock,
             'units_per_bag', x.units_per_bag,
             'is_active', x.is_active
           ) ORDER BY x.id SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT
      p.id,
      p.sku,
      p.name,
      p.description,
      p.category_id,
      p.tax_rate_id,
      p.unit,
      p.base_price,
      p.min_stock,
      p.units_per_bag,
      p.is_active
    FROM products p
    WHERE p.deleted_at IS NULL
      AND (IFNULL(p_only_active, 0) = 0 OR p.is_active = 1)
      AND (p_category_id IS NULL OR p.category_id = p_category_id)
      AND (
        p_search IS NULL OR p_search = ''
        OR p.sku LIKE CONCAT('%', p_search, '%')
        OR p.name LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY p.id DESC
    LIMIT v_offset, v_page_size
  ) x;

  SET o_code = 1;
  SET o_message = 'productos listados';
  SET o_data_json = CONCAT(
    '{',
    '"page":', v_page, ',',
    '"page_size":', v_page_size, ',',
    '"total":', v_total, ',',
    '"items":', IFNULL(v_items_json, '[]'),
    '}'
  );
END $$

DELIMITER ;
