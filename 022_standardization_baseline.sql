-- Standardization baseline: error catalog + config + utility routines
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Standardization Baseline
 * File              :- 022_standardization_baseline.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   Activos transversales: catalogo de errores, configuracion y utilidades
 *   de consulta para contrato estandar de respuestas.
 *
 * Routines in file:
 *   - fn_std_error_json
 *   - sp_std_error_lookup
 *   - sp_std_config_get
 * --------------------------------------------------------------------------- */

USE panaderia_db;

CREATE TABLE IF NOT EXISTS std_error_catalog (
  error_code VARCHAR(80) NOT NULL,
  domain VARCHAR(40) NOT NULL,
  category ENUM('validation','business','security','not_found','conflict','technical') NOT NULL,
  default_message VARCHAR(255) NOT NULL,
  http_status SMALLINT UNSIGNED NOT NULL,
  retryable TINYINT(1) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (error_code),
  KEY idx_std_error_domain (domain),
  KEY idx_std_error_active (is_active)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS std_app_config (
  config_key VARCHAR(100) NOT NULL,
  config_value VARCHAR(255) NOT NULL,
  description VARCHAR(255) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (config_key),
  KEY idx_std_app_config_active (is_active)
) ENGINE=InnoDB;

INSERT INTO std_app_config (config_key, config_value, description, is_active)
VALUES
  ('auth.login.max_attempts_15m', '5', 'Maximo de intentos fallidos en 15 minutos antes de bloqueo', 1),
  ('auth.login.window_minutes', '15', 'Ventana en minutos para contar intentos fallidos', 1),
  ('auth.password.min_length', '10', 'Longitud minima de contraseña definida en aplicacion', 1),
  ('inventory.allow_negative_stock', '0', '0 = no permitir inventario negativo', 1),
  ('session.refresh.default_days', '7', 'Duracion por defecto del refresh token en dias', 1)
ON DUPLICATE KEY UPDATE
  config_value = VALUES(config_value),
  description = VALUES(description),
  is_active = VALUES(is_active);

INSERT INTO std_error_catalog (error_code, domain, category, default_message, http_status, retryable, is_active)
VALUES
  ('COMMON.OK', 'COMMON', 'business', 'Operacion completada correctamente', 200, 0, 1),
  ('COMMON.SQL_ERROR', 'COMMON', 'technical', 'Error tecnico de base de datos', 500, 1, 1),

  ('AUTH.INVALID_CREDENTIALS', 'AUTH', 'security', 'Credenciales invalidas', 401, 0, 1),
  ('AUTH.ACCOUNT_BLOCKED', 'AUTH', 'security', 'Cuenta bloqueada', 423, 0, 1),
  ('AUTH.ACCOUNT_INACTIVE', 'AUTH', 'security', 'Cuenta inactiva', 403, 0, 1),
  ('AUTH.SESSION_NOT_FOUND', 'AUTH', 'not_found', 'Sesion no encontrada', 404, 0, 1),
  ('AUTH.SESSION_EXPIRED', 'AUTH', 'security', 'Sesion expirada', 401, 0, 1),
  ('AUTH.SESSION_REVOKED', 'AUTH', 'security', 'Sesion revocada', 401, 0, 1),
  ('AUTH.PASSWORD_MISMATCH', 'AUTH', 'security', 'La contraseña actual no coincide', 401, 0, 1),
  ('AUTH.PASSWORD_POLICY_FAIL', 'AUTH', 'validation', 'No cumple la politica de contraseña', 422, 0, 1),

  ('USER.NOT_FOUND', 'USER', 'not_found', 'Usuario no encontrado', 404, 0, 1),
  ('USER.USERNAME_EXISTS', 'USER', 'conflict', 'El nombre de usuario ya existe', 409, 0, 1),
  ('USER.EMAIL_EXISTS', 'USER', 'conflict', 'El correo ya existe', 409, 0, 1),
  ('USER.STATUS_INVALID', 'USER', 'validation', 'Estado de usuario invalido', 422, 0, 1),

  ('ROLE.NOT_FOUND', 'RBAC', 'not_found', 'Rol no encontrado', 404, 0, 1),
  ('ROLE.CODE_EXISTS', 'RBAC', 'conflict', 'El codigo de rol ya existe', 409, 0, 1),
  ('PERMISSION.NOT_FOUND', 'RBAC', 'not_found', 'Permiso no encontrado', 404, 0, 1),
  ('PERMISSION.CODE_EXISTS', 'RBAC', 'conflict', 'El codigo de permiso ya existe', 409, 0, 1),

  ('CATALOG.NOT_FOUND', 'CATALOG', 'not_found', 'Entidad de catalogo no encontrada', 404, 0, 1),
  ('CATALOG.DUPLICATE_CODE', 'CATALOG', 'conflict', 'El codigo del catalogo ya existe', 409, 0, 1),
  ('CATALOG.DUPLICATE_NAME', 'CATALOG', 'conflict', 'El nombre del catalogo ya existe', 409, 0, 1),

  ('CUSTOMER.NOT_FOUND', 'CUSTOMER', 'not_found', 'Cliente no encontrado', 404, 0, 1),
  ('ROUTE.NOT_FOUND', 'ROUTE', 'not_found', 'Ruta no encontrada', 404, 0, 1),
  ('ROUTE.DRIVER_OVERLAP', 'ROUTE', 'business', 'La asignacion de repartidor se cruza con el rango de fechas', 409, 0, 1),

  ('ORDER.NOT_FOUND', 'ORDER', 'not_found', 'Pedido no encontrado', 404, 0, 1),
  ('ORDER.INVALID_STATUS_TRANSITION', 'ORDER', 'business', 'Transicion de estado de pedido no permitida', 409, 0, 1),
  ('ORDER.EMPTY', 'ORDER', 'validation', 'El pedido no tiene items', 422, 0, 1),

  ('PURCHASE.NOT_FOUND', 'PURCHASE', 'not_found', 'Orden de compra no encontrada', 404, 0, 1),
  ('PURCHASE.INVALID_STATUS_TRANSITION', 'PURCHASE', 'business', 'Transicion de estado de compra no permitida', 409, 0, 1),

  ('PRODUCTION.NOT_FOUND', 'PRODUCTION', 'not_found', 'Orden de produccion no encontrada', 404, 0, 1),
  ('PRODUCTION.PENDING_ITEMS', 'PRODUCTION', 'business', 'La orden de produccion tiene items pendientes', 409, 0, 1),

  ('INVENTORY.INSUFFICIENT_STOCK', 'INVENTORY', 'business', 'Stock insuficiente', 409, 0, 1),
  ('INVENTORY.ITEM_NOT_FOUND', 'INVENTORY', 'not_found', 'Item de inventario no encontrado', 404, 0, 1),
  ('INVENTORY.MOVEMENT_INVALID', 'INVENTORY', 'validation', 'Movimiento de inventario invalido', 422, 0, 1),

  ('RECIPE.NOT_FOUND', 'RECIPE', 'not_found', 'Receta no encontrada', 404, 0, 1),
  ('RECIPE.EMPTY', 'RECIPE', 'validation', 'La receta no tiene items', 422, 0, 1),
  ('RECIPE.INVALID_QUANTITY', 'RECIPE', 'validation', 'Cantidad de receta invalida', 422, 0, 1)
ON DUPLICATE KEY UPDATE
  domain = VALUES(domain),
  category = VALUES(category),
  default_message = VALUES(default_message),
  http_status = VALUES(http_status),
  retryable = VALUES(retryable),
  is_active = VALUES(is_active);

DROP VIEW IF EXISTS vw_std_error_catalog_active;
CREATE VIEW vw_std_error_catalog_active AS
SELECT
  error_code,
  domain,
  category,
  default_message,
  http_status,
  retryable
FROM std_error_catalog
WHERE is_active = 1;

DROP VIEW IF EXISTS vw_std_app_config_active;
CREATE VIEW vw_std_app_config_active AS
SELECT
  config_key,
  config_value,
  description
FROM std_app_config
WHERE is_active = 1;

DELIMITER $$

DROP FUNCTION IF EXISTS fn_std_error_json $$
CREATE FUNCTION fn_std_error_json(
  p_error_code VARCHAR(80),
  p_detail VARCHAR(255),
  p_meta JSON
)
RETURNS JSON
READS SQL DATA
BEGIN
  DECLARE v_domain VARCHAR(40);
  DECLARE v_category VARCHAR(20);
  DECLARE v_default_message VARCHAR(255);
  DECLARE v_http_status SMALLINT UNSIGNED;
  DECLARE v_retryable TINYINT(1);

  SELECT
    domain,
    category,
    default_message,
    http_status,
    retryable
  INTO
    v_domain,
    v_category,
    v_default_message,
    v_http_status,
    v_retryable
  FROM std_error_catalog
  WHERE error_code = p_error_code
    AND is_active = 1
  LIMIT 1;

  IF v_default_message IS NULL THEN
    SET v_domain = 'COMMON';
    SET v_category = 'technical';
    SET v_default_message = 'Codigo de error estandar desconocido';
    SET v_http_status = 500;
    SET v_retryable = 1;
  END IF;

  RETURN JSON_OBJECT(
    'error_code', IFNULL(p_error_code, 'COMMON.SQL_ERROR'),
    'domain', v_domain,
    'category', v_category,
    'http_status', v_http_status,
    'retryable', v_retryable,
    'message', v_default_message,
    'detail', p_detail,
    'meta', IFNULL(p_meta, JSON_OBJECT())
  );
END $$

DROP PROCEDURE IF EXISTS sp_std_error_lookup $$
CREATE PROCEDURE sp_std_error_lookup(
  IN p_error_code VARCHAR(80),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_exists INT DEFAULT 0;

  SELECT COUNT(*) INTO v_exists
  FROM std_error_catalog
  WHERE error_code = p_error_code
    AND is_active = 1;

  IF v_exists = 0 THEN
    SET o_code = 0;
    SET o_message = 'codigo de error estandar no encontrado';
    SET o_data_json = CAST(fn_std_error_json('COMMON.SQL_ERROR', CONCAT('codigo no registrado: ', IFNULL(p_error_code, 'NULL')), JSON_OBJECT()) AS CHAR);
  ELSE
    SET o_code = 1;
    SET o_message = 'codigo de error estandar encontrado';
    SET o_data_json = CAST(fn_std_error_json(p_error_code, NULL, JSON_OBJECT()) AS CHAR);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_std_config_get $$
CREATE PROCEDURE sp_std_config_get(
  IN p_config_key VARCHAR(100),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_value VARCHAR(255);
  DECLARE v_description VARCHAR(255);

  SELECT config_value, description
    INTO v_value, v_description
  FROM std_app_config
  WHERE config_key = p_config_key
    AND is_active = 1
  LIMIT 1;

  IF v_value IS NULL THEN
    SET o_code = 0;
    SET o_message = 'clave de configuracion no encontrada';
    SET o_data_json = NULL;
  ELSE
    SET o_code = 1;
    SET o_message = 'clave de configuracion encontrada';
    SET o_data_json = JSON_OBJECT('config_key', p_config_key, 'config_value', v_value, 'description', v_description);
  END IF;
END $$

DELIMITER ;
