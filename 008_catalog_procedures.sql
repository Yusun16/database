-- Pidomi Panaderia - Catalog procedures (Phase B)
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Catalogs (Phase B)
 * File              :- 008_catalog_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   SP para maestros operativos: sedes, categorias, impuestos, productos,
 *   materias primas y proveedores.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : summary text
 *   o_data_json : json payload
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_branch_create $$
CREATE PROCEDURE sp_branch_create(
  IN p_code VARCHAR(30),
  IN p_name VARCHAR(120),
  IN p_address VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_branch_id BIGINT UNSIGNED;

  IF p_code IS NULL OR CHAR_LENGTH(TRIM(p_code)) < 2 THEN
    SET o_code = 0;
    SET o_message = 'el codigo de sede es obligatorio';
    SET o_data_json = NULL;
  ELSEIF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SET o_code = 0;
    SET o_message = 'el nombre de sede es obligatorio';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM branches WHERE code = TRIM(p_code)) THEN
    SET o_code = 0;
    SET o_message = 'el codigo de sede ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO branches (code, name, address, phone, is_active)
    VALUES (TRIM(p_code), TRIM(p_name), p_address, p_phone, 1);

    SET v_branch_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'branch.create', 'branches', CAST(v_branch_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'sede creada';
    SET o_data_json = JSON_OBJECT('branch_id', v_branch_id, 'code', TRIM(p_code));
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_branch_update $$
CREATE PROCEDURE sp_branch_update(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_name VARCHAR(120),
  IN p_address VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  UPDATE branches
  SET name = TRIM(p_name),
      address = p_address,
      phone = p_phone,
      is_active = IFNULL(p_is_active, is_active),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_branch_id;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    SET o_code = 0;
    SET o_message = 'sede no encontrada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'branch.update', 'branches', CAST(p_branch_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'sede actualizada';
    SET o_data_json = JSON_OBJECT('branch_id', p_branch_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_tax_rate_create $$
CREATE PROCEDURE sp_tax_rate_create(
  IN p_code VARCHAR(30),
  IN p_name VARCHAR(100),
  IN p_rate_percent DECIMAL(5,2),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_tax_id BIGINT UNSIGNED;

  IF p_rate_percent < 0 OR p_rate_percent > 100 THEN
    SET o_code = 0;
    SET o_message = 'rate_percent debe estar entre 0 y 100';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM tax_rates WHERE code = TRIM(p_code)) THEN
    SET o_code = 0;
    SET o_message = 'el codigo de impuesto ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO tax_rates (code, name, rate_percent, is_active)
    VALUES (TRIM(p_code), TRIM(p_name), p_rate_percent, IFNULL(p_is_active, 1));

    SET v_tax_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'tax_rate.create', 'tax_rates', CAST(v_tax_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'tasa de impuesto creada';
    SET o_data_json = JSON_OBJECT('tax_rate_id', v_tax_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_tax_rate_update $$
CREATE PROCEDURE sp_tax_rate_update(
  IN p_tax_rate_id BIGINT UNSIGNED,
  IN p_name VARCHAR(100),
  IN p_rate_percent DECIMAL(5,2),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_rate_percent < 0 OR p_rate_percent > 100 THEN
    SET o_code = 0;
    SET o_message = 'rate_percent debe estar entre 0 y 100';
    SET o_data_json = NULL;
  ELSE
    UPDATE tax_rates
    SET name = TRIM(p_name),
        rate_percent = p_rate_percent,
        is_active = IFNULL(p_is_active, is_active),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_tax_rate_id;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'tasa de impuesto no encontrada';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (p_actor_user_id, 'tax_rate.update', 'tax_rates', CAST(p_tax_rate_id AS CHAR));

      SET o_code = 1;
      SET o_message = 'tasa de impuesto actualizada';
      SET o_data_json = JSON_OBJECT('tax_rate_id', p_tax_rate_id);
    END IF;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_product_category_create $$
CREATE PROCEDURE sp_product_category_create(
  IN p_name VARCHAR(120),
  IN p_description VARCHAR(255),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED;

  IF EXISTS (SELECT 1 FROM product_categories WHERE name = TRIM(p_name)) THEN
    SET o_code = 0;
    SET o_message = 'la categoria de producto ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO product_categories (name, description, is_active)
    VALUES (TRIM(p_name), p_description, IFNULL(p_is_active, 1));

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'product_category.create', 'product_categories', CAST(v_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'categoria de producto creada';
    SET o_data_json = JSON_OBJECT('category_id', v_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_product_category_update $$
CREATE PROCEDURE sp_product_category_update(
  IN p_category_id BIGINT UNSIGNED,
  IN p_name VARCHAR(120),
  IN p_description VARCHAR(255),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  UPDATE product_categories
  SET name = TRIM(p_name),
      description = p_description,
      is_active = IFNULL(p_is_active, is_active),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_category_id;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    SET o_code = 0;
    SET o_message = 'categoria de producto no encontrada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'product_category.update', 'product_categories', CAST(p_category_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'categoria de producto actualizada';
    SET o_data_json = JSON_OBJECT('category_id', p_category_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_raw_material_category_create $$
CREATE PROCEDURE sp_raw_material_category_create(
  IN p_name VARCHAR(120),
  IN p_description VARCHAR(255),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED;

  IF EXISTS (SELECT 1 FROM raw_material_categories WHERE name = TRIM(p_name)) THEN
    SET o_code = 0;
    SET o_message = 'la categoria de materia prima ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO raw_material_categories (name, description, is_active)
    VALUES (TRIM(p_name), p_description, IFNULL(p_is_active, 1));

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'raw_material_category.create', 'raw_material_categories', CAST(v_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'categoria de materia prima creada';
    SET o_data_json = JSON_OBJECT('category_id', v_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_raw_material_category_update $$
CREATE PROCEDURE sp_raw_material_category_update(
  IN p_category_id BIGINT UNSIGNED,
  IN p_name VARCHAR(120),
  IN p_description VARCHAR(255),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  UPDATE raw_material_categories
  SET name = TRIM(p_name),
      description = p_description,
      is_active = IFNULL(p_is_active, is_active),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_category_id;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    SET o_code = 0;
    SET o_message = 'categoria de materia prima no encontrada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'raw_material_category.update', 'raw_material_categories', CAST(p_category_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'categoria de materia prima actualizada';
    SET o_data_json = JSON_OBJECT('category_id', p_category_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_supplier_create $$
CREATE PROCEDURE sp_supplier_create(
  IN p_tax_id VARCHAR(30),
  IN p_name VARCHAR(150),
  IN p_email VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_address VARCHAR(255),
  IN p_contact_name VARCHAR(120),
  IN p_status VARCHAR(20),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED;

  IF p_status NOT IN ('active', 'inactive') THEN
    SET o_code = 0;
    SET o_message = 'estado de proveedor invalido';
    SET o_data_json = NULL;
  ELSEIF p_tax_id IS NOT NULL AND p_tax_id <> '' AND EXISTS (SELECT 1 FROM suppliers WHERE tax_id = TRIM(p_tax_id)) THEN
    SET o_code = 0;
    SET o_message = 'el tax_id del proveedor ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO suppliers (tax_id, name, email, phone, address, contact_name, status)
    VALUES (NULLIF(TRIM(p_tax_id), ''), TRIM(p_name), p_email, p_phone, p_address, p_contact_name, p_status);

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'supplier.create', 'suppliers', CAST(v_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'proveedor creado';
    SET o_data_json = JSON_OBJECT('supplier_id', v_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_supplier_update $$
CREATE PROCEDURE sp_supplier_update(
  IN p_supplier_id BIGINT UNSIGNED,
  IN p_tax_id VARCHAR(30),
  IN p_name VARCHAR(150),
  IN p_email VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_address VARCHAR(255),
  IN p_contact_name VARCHAR(120),
  IN p_status VARCHAR(20),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_status NOT IN ('active', 'inactive') THEN
    SET o_code = 0;
    SET o_message = 'estado de proveedor invalido';
    SET o_data_json = NULL;
  ELSEIF p_tax_id IS NOT NULL AND p_tax_id <> '' AND EXISTS (
    SELECT 1 FROM suppliers WHERE tax_id = TRIM(p_tax_id) AND id <> p_supplier_id
  ) THEN
    SET o_code = 0;
    SET o_message = 'el tax_id del proveedor ya existe';
    SET o_data_json = NULL;
  ELSE
    UPDATE suppliers
    SET tax_id = NULLIF(TRIM(p_tax_id), ''),
        name = TRIM(p_name),
        email = p_email,
        phone = p_phone,
        address = p_address,
        contact_name = p_contact_name,
        status = p_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_supplier_id;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'proveedor no encontrado';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (p_actor_user_id, 'supplier.update', 'suppliers', CAST(p_supplier_id AS CHAR));

      SET o_code = 1;
      SET o_message = 'proveedor actualizado';
      SET o_data_json = JSON_OBJECT('supplier_id', p_supplier_id);
    END IF;
  END IF;
END $$

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
      sku, name, description, category_id, tax_rate_id, unit, base_price, min_stock, is_active
    ) VALUES (
      TRIM(p_sku), TRIM(p_name), p_description, p_category_id, p_tax_rate_id,
      p_unit, p_base_price, p_min_stock, IFNULL(p_is_active, 1)
    );

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'product.create', 'products', CAST(v_id AS CHAR));

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
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (p_actor_user_id, 'product.update', 'products', CAST(p_product_id AS CHAR));

      SET o_code = 1;
      SET o_message = 'producto actualizado';
      SET o_data_json = JSON_OBJECT('product_id', p_product_id);
    END IF;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_product_set_status $$
CREATE PROCEDURE sp_product_set_status(
  IN p_product_id BIGINT UNSIGNED,
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  UPDATE products
  SET is_active = IFNULL(p_is_active, is_active),
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
      'product.set_status',
      'products',
      CAST(p_product_id AS CHAR),
      JSON_OBJECT('is_active', IFNULL(p_is_active, 1))
    );

    SET o_code = 1;
    SET o_message = 'estado de producto actualizado';
    SET o_data_json = JSON_OBJECT('product_id', p_product_id, 'is_active', IFNULL(p_is_active, 1));
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_raw_material_create $$
CREATE PROCEDURE sp_raw_material_create(
  IN p_sku VARCHAR(60),
  IN p_name VARCHAR(150),
  IN p_description VARCHAR(255),
  IN p_category_id BIGINT UNSIGNED,
  IN p_supplier_id BIGINT UNSIGNED,
  IN p_unit VARCHAR(20),
  IN p_unit_cost DECIMAL(12,4),
  IN p_min_stock DECIMAL(12,3),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED;

  IF p_unit_cost < 0 OR p_min_stock < 0 THEN
    SET o_code = 0;
    SET o_message = 'unit_cost y min_stock deben ser >= 0';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM raw_material_categories WHERE id = p_category_id AND is_active = 1) THEN
    SET o_code = 0;
    SET o_message = 'categoria de materia prima no encontrada o inactiva';
    SET o_data_json = NULL;
  ELSEIF p_supplier_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM suppliers WHERE id = p_supplier_id AND status = 'active') THEN
    SET o_code = 0;
    SET o_message = 'proveedor no encontrado o inactivo';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM raw_materials WHERE sku = TRIM(p_sku)) THEN
    SET o_code = 0;
    SET o_message = 'el sku de materia prima ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO raw_materials (
      sku, name, description, category_id, supplier_id, unit, unit_cost, min_stock, is_active
    ) VALUES (
      TRIM(p_sku), TRIM(p_name), p_description, p_category_id, p_supplier_id,
      p_unit, p_unit_cost, p_min_stock, IFNULL(p_is_active, 1)
    );

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'raw_material.create', 'raw_materials', CAST(v_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'materia prima creada';
    SET o_data_json = JSON_OBJECT('raw_material_id', v_id, 'sku', TRIM(p_sku));
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_raw_material_update $$
CREATE PROCEDURE sp_raw_material_update(
  IN p_raw_material_id BIGINT UNSIGNED,
  IN p_name VARCHAR(150),
  IN p_description VARCHAR(255),
  IN p_category_id BIGINT UNSIGNED,
  IN p_supplier_id BIGINT UNSIGNED,
  IN p_unit VARCHAR(20),
  IN p_unit_cost DECIMAL(12,4),
  IN p_min_stock DECIMAL(12,3),
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_unit_cost < 0 OR p_min_stock < 0 THEN
    SET o_code = 0;
    SET o_message = 'unit_cost y min_stock deben ser >= 0';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM raw_material_categories WHERE id = p_category_id) THEN
    SET o_code = 0;
    SET o_message = 'categoria de materia prima no encontrada';
    SET o_data_json = NULL;
  ELSEIF p_supplier_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM suppliers WHERE id = p_supplier_id) THEN
    SET o_code = 0;
    SET o_message = 'proveedor no encontrado';
    SET o_data_json = NULL;
  ELSE
    UPDATE raw_materials
    SET name = TRIM(p_name),
        description = p_description,
        category_id = p_category_id,
        supplier_id = p_supplier_id,
        unit = p_unit,
        unit_cost = p_unit_cost,
        min_stock = p_min_stock,
        is_active = IFNULL(p_is_active, is_active),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_raw_material_id
      AND deleted_at IS NULL;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'materia prima no encontrada';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (p_actor_user_id, 'raw_material.update', 'raw_materials', CAST(p_raw_material_id AS CHAR));

      SET o_code = 1;
      SET o_message = 'materia prima actualizada';
      SET o_data_json = JSON_OBJECT('raw_material_id', p_raw_material_id);
    END IF;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_raw_material_set_status $$
CREATE PROCEDURE sp_raw_material_set_status(
  IN p_raw_material_id BIGINT UNSIGNED,
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  UPDATE raw_materials
  SET is_active = IFNULL(p_is_active, is_active),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_raw_material_id
    AND deleted_at IS NULL;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    SET o_code = 0;
    SET o_message = 'materia prima no encontrada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'raw_material.set_status',
      'raw_materials',
      CAST(p_raw_material_id AS CHAR),
      JSON_OBJECT('is_active', IFNULL(p_is_active, 1))
    );

    SET o_code = 1;
    SET o_message = 'estado de materia prima actualizado';
    SET o_data_json = JSON_OBJECT('raw_material_id', p_raw_material_id, 'is_active', IFNULL(p_is_active, 1));
  END IF;
END $$

DELIMITER ;
