-- Pidomi Panaderia - RBAC advanced procedures
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- RBAC Advanced (Phase G)
 * File              :- 018_rbac_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   SP para administracion de roles, permisos y asignaciones de seguridad.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : summary text
 *   o_data_json : json payload
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_role_create $$
CREATE PROCEDURE sp_role_create(
  IN p_code VARCHAR(50),
  IN p_name VARCHAR(100),
  IN p_description VARCHAR(255),
  IN p_is_system_role TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_role_id BIGINT UNSIGNED;

  IF p_code IS NULL OR CHAR_LENGTH(TRIM(p_code)) < 3 THEN
    SET o_code = 0;
    SET o_message = 'el codigo de rol es obligatorio';
    SET o_data_json = NULL;
  ELSEIF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 3 THEN
    SET o_code = 0;
    SET o_message = 'el nombre de rol es obligatorio';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM roles WHERE code = TRIM(p_code)) THEN
    SET o_code = 0;
    SET o_message = 'el codigo de rol ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO roles (code, name, description, is_system_role)
    VALUES (TRIM(p_code), TRIM(p_name), p_description, IFNULL(p_is_system_role, 0));

    SET v_role_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'role.create', 'roles', CAST(v_role_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'rol creado';
    SET o_data_json = JSON_OBJECT('role_id', v_role_id, 'code', TRIM(p_code));
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_role_update $$
CREATE PROCEDURE sp_role_update(
  IN p_role_id BIGINT UNSIGNED,
  IN p_name VARCHAR(100),
  IN p_description VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  IF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 3 THEN
    SET o_code = 0;
    SET o_message = 'el nombre de rol es obligatorio';
    SET o_data_json = NULL;
  ELSE
    UPDATE roles
    SET name = TRIM(p_name),
        description = p_description,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_role_id;

    SET v_rows = ROW_COUNT();

    IF v_rows = 0 THEN
      SET o_code = 0;
      SET o_message = 'rol no encontrado';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (p_actor_user_id, 'role.update', 'roles', CAST(p_role_id AS CHAR));

      SET o_code = 1;
      SET o_message = 'rol actualizado';
      SET o_data_json = JSON_OBJECT('role_id', p_role_id);
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_permission_create $$
CREATE PROCEDURE sp_permission_create(
  IN p_code VARCHAR(100),
  IN p_name VARCHAR(150),
  IN p_description VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_permission_id BIGINT UNSIGNED;

  IF p_code IS NULL OR CHAR_LENGTH(TRIM(p_code)) < 3 THEN
    SET o_code = 0;
    SET o_message = 'el codigo de permiso es obligatorio';
    SET o_data_json = NULL;
  ELSEIF p_name IS NULL OR CHAR_LENGTH(TRIM(p_name)) < 3 THEN
    SET o_code = 0;
    SET o_message = 'el nombre de permiso es obligatorio';
    SET o_data_json = NULL;
  ELSEIF EXISTS (SELECT 1 FROM permissions WHERE code = TRIM(p_code)) THEN
    SET o_code = 0;
    SET o_message = 'el codigo de permiso ya existe';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO permissions (code, name, description)
    VALUES (TRIM(p_code), TRIM(p_name), p_description);

    SET v_permission_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (p_actor_user_id, 'permission.create', 'permissions', CAST(v_permission_id AS CHAR));

    SET o_code = 1;
    SET o_message = 'permiso creado';
    SET o_data_json = JSON_OBJECT('permission_id', v_permission_id, 'code', TRIM(p_code));
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_role_set_permissions $$
CREATE PROCEDURE sp_role_set_permissions(
  IN p_role_id BIGINT UNSIGNED,
  IN p_permission_codes_json JSON,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_role_exists INT DEFAULT 0;
  DECLARE v_input_count INT DEFAULT 0;
  DECLARE v_found_count INT DEFAULT 0;
  DECLARE v_assigned_count INT DEFAULT 0;
  DECLARE v_idx INT DEFAULT 0;
  DECLARE v_permission_code VARCHAR(100);

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  IF p_permission_codes_json IS NULL OR JSON_VALID(p_permission_codes_json) = 0 OR JSON_TYPE(p_permission_codes_json) <> 'ARRAY' THEN
    SET o_code = 0;
    SET o_message = 'el parametro p_permission_codes_json debe ser un arreglo JSON valido';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    SELECT COUNT(*)
      INTO v_role_exists
    FROM roles
    WHERE id = p_role_id
    FOR UPDATE;

    IF v_role_exists = 0 THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'rol no encontrado';
      SET o_data_json = NULL;
    ELSE
      DROP TEMPORARY TABLE IF EXISTS tmp_permission_codes;
      CREATE TEMPORARY TABLE tmp_permission_codes (
        permission_code VARCHAR(100) NOT NULL,
        PRIMARY KEY (permission_code)
      ) ENGINE=Memory;

      SET v_idx = 0;
      WHILE v_idx < JSON_LENGTH(p_permission_codes_json) DO
        SET v_permission_code = TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_permission_codes_json, CONCAT('$[', v_idx, ']'))));

        IF v_permission_code IS NOT NULL AND v_permission_code <> '' THEN
          INSERT IGNORE INTO tmp_permission_codes (permission_code)
          VALUES (v_permission_code);
        END IF;

        SET v_idx = v_idx + 1;
      END WHILE;

      SELECT COUNT(*) INTO v_input_count FROM tmp_permission_codes;

      IF v_input_count = 0 THEN
        ROLLBACK;
        SET o_code = 0;
        SET o_message = 'al menos un codigo de permiso es obligatorio';
        SET o_data_json = NULL;
      ELSE
        SELECT COUNT(*)
          INTO v_found_count
        FROM tmp_permission_codes t
        INNER JOIN permissions p ON p.code = t.permission_code;

        IF v_input_count <> v_found_count THEN
          ROLLBACK;
          SET o_code = 0;
          SET o_message = 'uno o mas permisos no existen';
          SET o_data_json = NULL;
        ELSE
          DELETE FROM role_permissions WHERE role_id = p_role_id;

          INSERT INTO role_permissions (role_id, permission_id)
          SELECT p_role_id, p.id
          FROM tmp_permission_codes t
          INNER JOIN permissions p ON p.code = t.permission_code;

          SET v_assigned_count = ROW_COUNT();

          INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
          VALUES (
            p_actor_user_id,
            'role.set_permissions',
            'roles',
            CAST(p_role_id AS CHAR),
            JSON_OBJECT('permissions_assigned', v_assigned_count)
          );

          COMMIT;

          SET o_code = 1;
          SET o_message = 'permisos del rol actualizados';
          SET o_data_json = JSON_OBJECT('role_id', p_role_id, 'permissions_assigned', v_assigned_count);
        END IF;
      END IF;
    END IF;
  END IF;
END $$

DELIMITER ;
