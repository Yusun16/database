-- Pidomi Panaderia - Customer and route procedures (Phase C)
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Customers and Routes (Phase C)
 * File              :- 010_customer_route_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   SP para ciclo comercial de clientes, rutas y asignacion de repartidores.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : summary text
 *   o_data_json : json payload
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_customer_create $$
CREATE PROCEDURE sp_customer_create(
  IN p_tax_id VARCHAR(30),
  IN p_name VARCHAR(150),
  IN p_email VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_address VARCHAR(255),
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
      status,
      credit_limit
    ) VALUES (
      NULLIF(TRIM(p_tax_id), ''),
      TRIM(p_name),
      p_email,
      p_phone,
      p_address,
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

DROP PROCEDURE IF EXISTS sp_customer_set_status $$
CREATE PROCEDURE sp_customer_set_status(
  IN p_customer_id BIGINT UNSIGNED,
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
    SET o_message = 'estado de cliente invalido';
    SET o_data_json = NULL;
  ELSE
    UPDATE customers
    SET status = p_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id
      AND deleted_at IS NULL;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'cliente no encontrado';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'customer.set_status',
        'customers',
        CAST(p_customer_id AS CHAR),
        JSON_OBJECT('status', p_status)
      );

      SET o_code = 1;
      SET o_message = 'estado de cliente actualizado';
      SET o_data_json = JSON_OBJECT('customer_id', p_customer_id, 'status', p_status);
    END IF;
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_route_create $$
CREATE PROCEDURE sp_route_create(
  IN p_code VARCHAR(30),
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

  IF p_code IS NULL OR CHAR_LENGTH(TRIM(p_code)) < 2 THEN
    SET o_code = 0;
    SET o_message = 'el codigo de ruta es obligatorio';
    SET o_data_json = NULL;
  ELSEIF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 2 THEN
    SET o_code = 0;
    SET o_message = 'el nombre de ruta es obligatorio';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM delivery_routes WHERE code = TRIM(p_code)) THEN
    SET o_code = 0;
    SET o_message = 'el codigo de ruta ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO delivery_routes (code, name, description, is_active)
    VALUES (TRIM(p_code), TRIM(p_name), p_description, IFNULL(p_is_active, 1));

    SET v_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'route.create', 'delivery_routes', CAST(v_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'ruta creada';
    SET o_data_json = JSON_OBJECT('route_id', v_id, 'code', TRIM(p_code));
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_route_update $$
CREATE PROCEDURE sp_route_update(
  IN p_route_id BIGINT UNSIGNED,
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

  UPDATE delivery_routes
  SET name = TRIM(p_name),
      description = p_description,
      is_active = IFNULL(p_is_active, is_active),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_route_id;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    SET o_code = 0;
    SET o_message = 'ruta no encontrada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'route.update', 'delivery_routes', CAST(p_route_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'ruta actualizada';
    SET o_data_json = JSON_OBJECT('route_id', p_route_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_route_set_status $$
CREATE PROCEDURE sp_route_set_status(
  IN p_route_id BIGINT UNSIGNED,
  IN p_is_active TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  UPDATE delivery_routes
  SET is_active = IFNULL(p_is_active, is_active),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_route_id;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    SET o_code = 0;
    SET o_message = 'ruta no encontrada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'route.set_status',
      'delivery_routes',
      CAST(p_route_id AS CHAR),
      JSON_OBJECT('is_active', IFNULL(p_is_active, 1))
    );

    SET o_code = 1;
    SET o_message = 'estado de ruta actualizado';
    SET o_data_json = JSON_OBJECT('route_id', p_route_id, 'is_active', IFNULL(p_is_active, 1));
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_route_assign_driver $$
CREATE PROCEDURE sp_route_assign_driver(
  IN p_route_id BIGINT UNSIGNED,
  IN p_user_id BIGINT UNSIGNED,
  IN p_assigned_from DATE,
  IN p_assigned_to DATE,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_assignment_id BIGINT UNSIGNED;

  IF p_assigned_from IS NULL THEN
    SET o_code = 0;
    SET o_message = 'la fecha inicial de asignacion (assigned_from) es obligatoria';
    SET o_data_json = NULL;
  ELSEIF p_assigned_to IS NOT NULL AND p_assigned_to < p_assigned_from THEN
    SET o_code = 0;
    SET o_message = 'la fecha final de asignacion (assigned_to) debe ser mayor o igual que assigned_from';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (SELECT 1 FROM delivery_routes WHERE id = p_route_id AND is_active = 1) THEN
    SET o_code = 0;
    SET o_message = 'ruta no encontrada o inactiva';
    SET o_data_json = NULL;
  ELSEIF NOT EXISTS (
    SELECT 1
    FROM users
    WHERE id = p_user_id
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SET o_code = 0;
    SET o_message = 'usuario repartidor no encontrado o inactivo';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1
    FROM route_drivers rd
    WHERE rd.route_id = p_route_id
      AND rd.user_id = p_user_id
      AND (
        p_assigned_to IS NULL
        OR rd.assigned_to IS NULL
        OR rd.assigned_from <= p_assigned_to
      )
      AND (
        rd.assigned_to IS NULL
        OR rd.assigned_to >= p_assigned_from
      )
  ) THEN
    SET o_code = 0;
    SET o_message = 'repartidor ya asignado en periodo traslapado';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO route_drivers (route_id, user_id, assigned_from, assigned_to)
    VALUES (p_route_id, p_user_id, p_assigned_from, p_assigned_to);

    SET v_assignment_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'route.assign_driver',
      'route_drivers',
      CAST(v_assignment_id AS CHAR),
      JSON_OBJECT('route_id', p_route_id, 'user_id', p_user_id)
    );

    SET o_code = 1;
    SET o_message = 'repartidor asignado a ruta';
    SET o_data_json = JSON_OBJECT('route_driver_id', v_assignment_id);
  END IF;
END $$

DELIMITER ;
