-- Customer neighborhood or zone for delivery details.
-- Run after:
--   051_commercial_product_categories.sql

USE panaderia_db;

SET @customers_neighborhood_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customers'
    AND COLUMN_NAME = 'neighborhood'
);

SET @customers_neighborhood_sql = IF(
  @customers_neighborhood_exists = 0,
  'ALTER TABLE customers
     ADD COLUMN neighborhood VARCHAR(120) NULL AFTER address,
     ADD KEY idx_customers_neighborhood (neighborhood)',
  'SELECT 1'
);

PREPARE customers_neighborhood_stmt FROM @customers_neighborhood_sql;
EXECUTE customers_neighborhood_stmt;
DEALLOCATE PREPARE customers_neighborhood_stmt;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_customer_create $$
CREATE PROCEDURE sp_customer_create(
  IN p_tax_id VARCHAR(30),
  IN p_name VARCHAR(150),
  IN p_email VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_address VARCHAR(255),
  IN p_neighborhood VARCHAR(120),
  IN p_status VARCHAR(20),
  IN p_credit_limit DECIMAL(12,2),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED;

  IF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SET o_code = 0;
    SET o_message = 'el nombre del cliente es obligatorio';
    SET o_data_json = NULL;
  ELSEIF p_status NOT IN ('active', 'inactive') THEN
    SET o_code = 0;
    SET o_message = 'estado de cliente invalido';
    SET o_data_json = NULL;
  ELSEIF IFNULL(p_credit_limit, 0) < 0 THEN
    SET o_code = 0;
    SET o_message = 'credit_limit debe ser >= 0';
    SET o_data_json = NULL;
  ELSEIF p_tax_id IS NOT NULL AND TRIM(p_tax_id) <> ''
      AND EXISTS (SELECT 1 FROM customers WHERE tax_id = TRIM(p_tax_id) AND deleted_at IS NULL) THEN
    SET o_code = 0;
    SET o_message = 'el tax_id del cliente ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO customers (
      tax_id,
      name,
      email,
      phone,
      address,
      neighborhood,
      status,
      credit_limit
    ) VALUES (
      NULLIF(TRIM(p_tax_id), ''),
      TRIM(p_name),
      p_email,
      p_phone,
      p_address,
      NULLIF(TRIM(p_neighborhood), ''),
      p_status,
      IFNULL(p_credit_limit, 0)
    );

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'customer.create', 'customers', CAST(v_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'cliente creado';
    SET o_data_json = JSON_OBJECT('customer_id', v_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_customer_update $$
CREATE PROCEDURE sp_customer_update(
  IN p_customer_id BIGINT UNSIGNED,
  IN p_tax_id VARCHAR(30),
  IN p_name VARCHAR(150),
  IN p_email VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_address VARCHAR(255),
  IN p_neighborhood VARCHAR(120),
  IN p_status VARCHAR(20),
  IN p_credit_limit DECIMAL(12,2),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SET o_code = 0;
    SET o_message = 'el nombre del cliente es obligatorio';
    SET o_data_json = NULL;
  ELSEIF p_status NOT IN ('active', 'inactive') THEN
    SET o_code = 0;
    SET o_message = 'estado de cliente invalido';
    SET o_data_json = NULL;
  ELSEIF IFNULL(p_credit_limit, 0) < 0 THEN
    SET o_code = 0;
    SET o_message = 'credit_limit debe ser >= 0';
    SET o_data_json = NULL;
  ELSEIF p_tax_id IS NOT NULL AND TRIM(p_tax_id) <> ''
      AND EXISTS (
        SELECT 1
        FROM customers
        WHERE tax_id = TRIM(p_tax_id)
          AND id <> p_customer_id
          AND deleted_at IS NULL
      ) THEN
    SET o_code = 0;
    SET o_message = 'el tax_id del cliente ya existe';
    SET o_data_json = NULL;
  ELSE
    UPDATE customers
    SET tax_id = NULLIF(TRIM(p_tax_id), ''),
        name = TRIM(p_name),
        email = p_email,
        phone = p_phone,
        address = p_address,
        neighborhood = NULLIF(TRIM(p_neighborhood), ''),
        status = p_status,
        credit_limit = IFNULL(p_credit_limit, 0),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id
      AND deleted_at IS NULL;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'cliente no encontrado';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (p_actor_user_id, 'customer.update', 'customers', CAST(p_customer_id AS CHAR));

      SET o_code = 1;
      SET o_message = 'cliente actualizado';
      SET o_data_json = JSON_OBJECT('customer_id', p_customer_id);
    END IF;
  END IF;
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
      OR c.tax_id LIKE CONCAT('%', p_search, '%')
      OR c.name LIKE CONCAT('%', p_search, '%')
      OR c.phone LIKE CONCAT('%', p_search, '%')
      OR c.address LIKE CONCAT('%', p_search, '%')
      OR c.neighborhood LIKE CONCAT('%', p_search, '%')
    );

  SELECT IFNULL(
           CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
             'id', x.id,
             'tax_id', x.tax_id,
             'name', x.name,
             'email', x.email,
             'phone', x.phone,
             'address', x.address,
             'neighborhood', x.neighborhood,
             'status', x.status,
             'credit_limit', x.credit_limit
           ) ORDER BY x.id SEPARATOR ','), ']'),
           '[]'
         )
    INTO v_items_json
  FROM (
    SELECT
      c.id,
      c.tax_id,
      c.name,
      c.email,
      c.phone,
      c.address,
      c.neighborhood,
      c.status,
      c.credit_limit
    FROM customers c
    WHERE c.deleted_at IS NULL
      AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
      AND (
        p_search IS NULL OR p_search = ''
        OR c.tax_id LIKE CONCAT('%', p_search, '%')
        OR c.name LIKE CONCAT('%', p_search, '%')
        OR c.phone LIKE CONCAT('%', p_search, '%')
        OR c.address LIKE CONCAT('%', p_search, '%')
        OR c.neighborhood LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY c.id DESC
    LIMIT v_offset, v_page_size
  ) x;

  SET o_code = 1;
  SET o_message = 'clientes listados';
  SET o_data_json = CONCAT(
    '{"page":', v_page,
    ',"page_size":', v_page_size,
    ',"total":', v_total,
    ',"items":', IFNULL(v_items_json, '[]'),
    '}'
  );
END $$

DELIMITER ;
