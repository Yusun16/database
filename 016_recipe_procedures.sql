-- Pidomi Panaderia - Recipe procedures (pending core)
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Recipes (Phase F)
 * File              :- 016_recipe_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   SP para versionado de recetas y administracion de insumos por formula.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : summary text
 *   o_data_json : json payload
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_recipe_create $$
CREATE PROCEDURE sp_recipe_create(
  IN p_product_id BIGINT UNSIGNED,
  IN p_output_quantity DECIMAL(12,3),
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_recipe_id BIGINT UNSIGNED;
  DECLARE v_next_version INT UNSIGNED DEFAULT 1;

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

  IF p_output_quantity IS NULL OR p_output_quantity <= 0 THEN
    SET o_code = 0;
    SET o_message = 'la cantidad de salida (output_quantity) debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    IF NOT EXISTS (
      SELECT 1
      FROM products
      WHERE id = p_product_id
        AND is_active = 1
        AND deleted_at IS NULL
    ) THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'producto no encontrado o inactivo';
      SET o_data_json = NULL;
    ELSE
      SELECT COALESCE(MAX(version_no), 0) + 1
        INTO v_next_version
      FROM recipes
      WHERE product_id = p_product_id
      FOR UPDATE;

      UPDATE recipes
      SET is_active = 0,
          updated_at = CURRENT_TIMESTAMP
      WHERE product_id = p_product_id
        AND is_active = 1;

      INSERT INTO recipes (
        product_id,
        version_no,
        output_quantity,
        notes,
        is_active
      ) VALUES (
        p_product_id,
        v_next_version,
        p_output_quantity,
        p_notes,
        1
      );

      SET v_recipe_id = LAST_INSERT_ID();

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'recipe.create',
        'recipes',
        CAST(v_recipe_id AS CHAR),
        JSON_OBJECT('product_id', p_product_id, 'version_no', v_next_version)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'receta creada';
      SET o_data_json = JSON_OBJECT('recipe_id', v_recipe_id, 'product_id', p_product_id, 'version_no', v_next_version);
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_recipe_add_item $$
CREATE PROCEDURE sp_recipe_add_item(
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_raw_material_id BIGINT UNSIGNED,
  IN p_quantity DECIMAL(12,4),
  IN p_wastage_percent DECIMAL(5,2),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_product_id BIGINT UNSIGNED;

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

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    SET o_code = 0;
    SET o_message = 'la cantidad (quantity) debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSEIF p_wastage_percent IS NULL OR p_wastage_percent < 0 OR p_wastage_percent > 100 THEN
    SET o_code = 0;
    SET o_message = 'wastage_percent debe estar entre 0 y 100';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    SELECT product_id
      INTO v_product_id
    FROM recipes
    WHERE id = p_recipe_id
    FOR UPDATE;

    IF v_product_id IS NULL THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'receta no encontrada';
      SET o_data_json = NULL;
    ELSEIF NOT EXISTS (
      SELECT 1
      FROM raw_materials
      WHERE id = p_raw_material_id
        AND is_active = 1
        AND deleted_at IS NULL
    ) THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'materia prima no encontrada o inactiva';
      SET o_data_json = NULL;
    ELSE
      INSERT INTO recipe_items (recipe_id, raw_material_id, quantity, wastage_percent)
      VALUES (p_recipe_id, p_raw_material_id, p_quantity, p_wastage_percent)
      ON DUPLICATE KEY UPDATE
        quantity = VALUES(quantity),
        wastage_percent = VALUES(wastage_percent);

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'recipe.item.upsert',
        'recipes',
        CAST(p_recipe_id AS CHAR),
        JSON_OBJECT('raw_material_id', p_raw_material_id, 'quantity', p_quantity, 'wastage_percent', p_wastage_percent)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'item de receta insertado o actualizado';
      SET o_data_json = JSON_OBJECT('recipe_id', p_recipe_id, 'raw_material_id', p_raw_material_id);
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_recipe_remove_item $$
CREATE PROCEDURE sp_recipe_remove_item(
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_raw_material_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;

  START TRANSACTION;

  DELETE FROM recipe_items
  WHERE recipe_id = p_recipe_id
    AND raw_material_id = p_raw_material_id;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'item de receta no encontrado';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'recipe.item.remove',
      'recipes',
      CAST(p_recipe_id AS CHAR),
      JSON_OBJECT('raw_material_id', p_raw_material_id)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'item de receta eliminado';
    SET o_data_json = JSON_OBJECT('recipe_id', p_recipe_id, 'raw_material_id', p_raw_material_id);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_recipe_publish_version $$
CREATE PROCEDURE sp_recipe_publish_version(
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_product_id BIGINT UNSIGNED;
  DECLARE v_item_count INT DEFAULT 0;

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

  START TRANSACTION;

  SELECT product_id
    INTO v_product_id
  FROM recipes
  WHERE id = p_recipe_id
  FOR UPDATE;

  IF v_product_id IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'receta no encontrada';
    SET o_data_json = NULL;
  ELSE
    SELECT COUNT(*)
      INTO v_item_count
    FROM recipe_items
    WHERE recipe_id = p_recipe_id;

    IF v_item_count = 0 THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'la receta no tiene items';
      SET o_data_json = NULL;
    ELSE
      UPDATE recipes
      SET is_active = 0,
          updated_at = CURRENT_TIMESTAMP
      WHERE product_id = v_product_id;

      UPDATE recipes
      SET is_active = 1,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = p_recipe_id;

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'recipe.publish',
        'recipes',
        CAST(p_recipe_id AS CHAR),
        JSON_OBJECT('product_id', v_product_id)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'receta publicada';
      SET o_data_json = JSON_OBJECT('recipe_id', p_recipe_id, 'product_id', v_product_id, 'is_active', 1);
    END IF;
  END IF;
END $$

DELIMITER ;
