-- Pidomi Panaderia - Read procedures (GET/LIST)
-- MariaDB/MySQL compatible

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Read API (GET/LIST)
 * File              :- 027_read_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   Procedimientos de lectura para frontend/backend.
 *   No modifican estado de negocio.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 validation/not found | -1 sql exception
 *   o_message   : resumen de resultado
 *   o_data_json : payload JSON con items y metadatos
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_user_get_by_id $$
CREATE PROCEDURE sp_user_get_by_id(
  IN p_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_exists INT DEFAULT 0;

  SELECT COUNT(*)
    INTO v_exists
  FROM users u
  WHERE u.id = p_user_id
    AND u.deleted_at IS NULL;

  IF v_exists = 0 THEN
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
    SET o_data_json = NULL;
  ELSE
    SET o_code = 1;
    SET o_message = 'usuario obtenido';

    SELECT JSON_OBJECT(
      'id', u.id,
      'username', u.username,
      'email', u.email,
      'full_name', u.full_name,
      'phone', u.phone,
      'status', u.status,
      'must_change_password', u.must_change_password,
      'last_login_at', u.last_login_at,
      'roles', IFNULL(
        (
          SELECT CONCAT('[', GROUP_CONCAT(JSON_QUOTE(r.code) ORDER BY r.code SEPARATOR ','), ']')
          FROM user_roles ur
          INNER JOIN roles r ON r.id = ur.role_id
          WHERE ur.user_id = u.id
        ),
        '[]'
      )
    )
    INTO o_data_json
    FROM users u
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
    LIMIT 1;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_user_list $$
CREATE PROCEDURE sp_user_list(
  IN p_status VARCHAR(20),
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
  FROM users u
  WHERE u.deleted_at IS NULL
    AND (p_status IS NULL OR p_status = '' OR u.status = p_status)
    AND (
      p_search IS NULL OR p_search = ''
      OR u.username LIKE CONCAT('%', p_search, '%')
      OR u.email LIKE CONCAT('%', p_search, '%')
      OR u.full_name LIKE CONCAT('%', p_search, '%')
    );

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', x.id,
             'username', x.username,
             'email', x.email,
             'full_name', x.full_name,
             'status', x.status,
             'must_change_password', x.must_change_password,
             'last_login_at', x.last_login_at,
             'created_at', x.created_at
           ) ORDER BY x.id SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT u.id, u.username, u.email, u.full_name, u.status, u.must_change_password, u.last_login_at, u.created_at
    FROM users u
    WHERE u.deleted_at IS NULL
      AND (p_status IS NULL OR p_status = '' OR u.status = p_status)
      AND (
        p_search IS NULL OR p_search = ''
        OR u.username LIKE CONCAT('%', p_search, '%')
        OR u.email LIKE CONCAT('%', p_search, '%')
        OR u.full_name LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY u.id DESC
    LIMIT v_offset, v_page_size
  ) x;

  SET o_code = 1;
  SET o_message = 'usuarios listados';
  SET o_data_json = CONCAT(
    '{',
    '"page":', v_page, ',',
    '"page_size":', v_page_size, ',',
    '"total":', v_total, ',',
    '"items":', IFNULL(v_items_json, '[]'),
    '}'
  );
END $$

DROP PROCEDURE IF EXISTS sp_branch_list $$
CREATE PROCEDURE sp_branch_list(
  IN p_only_active TINYINT,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_items_json LONGTEXT;

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', b.id,
             'code', b.code,
             'name', b.name,
             'address', b.address,
             'phone', b.phone,
             'is_active', b.is_active
           ) ORDER BY b.name SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM branches b
  WHERE (IFNULL(p_only_active, 0) = 0 OR b.is_active = 1);

  SET o_code = 1;
  SET o_message = 'sedes listadas';
  SET o_data_json = CONCAT('{"items":', IFNULL(v_items_json, '[]'), '}');
END $$

DROP PROCEDURE IF EXISTS sp_customer_list $$
CREATE PROCEDURE sp_customer_list(
  IN p_status VARCHAR(20),
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
  FROM customers c
  WHERE c.deleted_at IS NULL
    AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
    AND (
      p_search IS NULL OR p_search = ''
      OR c.name LIKE CONCAT('%', p_search, '%')
      OR c.tax_id LIKE CONCAT('%', p_search, '%')
      OR c.email LIKE CONCAT('%', p_search, '%')
    );

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', x.id,
             'tax_id', x.tax_id,
             'name', x.name,
             'email', x.email,
             'phone', x.phone,
             'status', x.status,
             'credit_limit', x.credit_limit
           ) ORDER BY x.id SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT c.id, c.tax_id, c.name, c.email, c.phone, c.status, c.credit_limit
    FROM customers c
    WHERE c.deleted_at IS NULL
      AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
      AND (
        p_search IS NULL OR p_search = ''
        OR c.name LIKE CONCAT('%', p_search, '%')
        OR c.tax_id LIKE CONCAT('%', p_search, '%')
        OR c.email LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY c.id DESC
    LIMIT v_offset, v_page_size
  ) x;

  SET o_code = 1;
  SET o_message = 'clientes listados';
  SET o_data_json = CONCAT(
    '{',
    '"page":', v_page, ',',
    '"page_size":', v_page_size, ',',
    '"total":', v_total, ',',
    '"items":', IFNULL(v_items_json, '[]'),
    '}'
  );
END $$

DROP PROCEDURE IF EXISTS sp_route_list $$
CREATE PROCEDURE sp_route_list(
  IN p_only_active TINYINT,
  IN p_ref_date DATE,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_items_json LONGTEXT;
  DECLARE v_ref_date DATE;

  SET v_ref_date = IFNULL(p_ref_date, CURRENT_DATE());

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', x.id,
             'code', x.code,
             'name', x.name,
             'description', x.description,
             'is_active', x.is_active,
             'current_driver_user_id', x.current_driver_user_id,
             'current_driver_name', x.current_driver_name
           ) ORDER BY x.name SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT
      r.id,
      r.code,
      r.name,
      r.description,
      r.is_active,
      u.id AS current_driver_user_id,
      u.full_name AS current_driver_name
    FROM delivery_routes r
    LEFT JOIN route_drivers rd
      ON rd.route_id = r.id
     AND rd.assigned_from <= v_ref_date
     AND (rd.assigned_to IS NULL OR rd.assigned_to >= v_ref_date)
    LEFT JOIN users u ON u.id = rd.user_id
    WHERE (IFNULL(p_only_active, 0) = 0 OR r.is_active = 1)
    ORDER BY r.name
  ) x;

  SET o_code = 1;
  SET o_message = 'rutas listadas';
  SET o_data_json = CONCAT('{"items":', IFNULL(v_items_json, '[]'), '}');
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
             'category_id', x.category_id,
             'tax_rate_id', x.tax_rate_id,
             'unit', x.unit,
             'base_price', x.base_price,
             'min_stock', x.min_stock,
             'is_active', x.is_active
           ) ORDER BY x.id SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT p.id, p.sku, p.name, p.category_id, p.tax_rate_id, p.unit, p.base_price, p.min_stock, p.is_active
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

DROP PROCEDURE IF EXISTS sp_raw_material_list $$
CREATE PROCEDURE sp_raw_material_list(
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
  FROM raw_materials rm
  WHERE rm.deleted_at IS NULL
    AND (IFNULL(p_only_active, 0) = 0 OR rm.is_active = 1)
    AND (p_category_id IS NULL OR rm.category_id = p_category_id)
    AND (
      p_search IS NULL OR p_search = ''
      OR rm.sku LIKE CONCAT('%', p_search, '%')
      OR rm.name LIKE CONCAT('%', p_search, '%')
    );

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', x.id,
             'sku', x.sku,
             'name', x.name,
             'category_id', x.category_id,
             'supplier_id', x.supplier_id,
             'unit', x.unit,
             'unit_cost', x.unit_cost,
             'min_stock', x.min_stock,
             'is_active', x.is_active
           ) ORDER BY x.id SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT rm.id, rm.sku, rm.name, rm.category_id, rm.supplier_id, rm.unit, rm.unit_cost, rm.min_stock, rm.is_active
    FROM raw_materials rm
    WHERE rm.deleted_at IS NULL
      AND (IFNULL(p_only_active, 0) = 0 OR rm.is_active = 1)
      AND (p_category_id IS NULL OR rm.category_id = p_category_id)
      AND (
        p_search IS NULL OR p_search = ''
        OR rm.sku LIKE CONCAT('%', p_search, '%')
        OR rm.name LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY rm.id DESC
    LIMIT v_offset, v_page_size
  ) x;

  SET o_code = 1;
  SET o_message = 'materias primas listadas';
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
