-- Production packaging flow.
-- Run after:
--   001_init_schema.sql
--   002_business_procedures.sql
--   016_recipe_procedures.sql

USE panaderia_db;

SET @raw_materials_bag_size_grams_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'raw_materials'
    AND COLUMN_NAME = 'bag_size_grams'
);
SET @raw_materials_bag_size_grams_sql = IF(
  @raw_materials_bag_size_grams_exists = 0,
  'ALTER TABLE raw_materials ADD COLUMN bag_size_grams DECIMAL(14,3) NULL AFTER unit_cost',
  'SELECT 1'
);
PREPARE raw_materials_bag_size_grams_stmt FROM @raw_materials_bag_size_grams_sql;
EXECUTE raw_materials_bag_size_grams_stmt;
DEALLOCATE PREPARE raw_materials_bag_size_grams_stmt;

CREATE TABLE IF NOT EXISTS employees (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  employee_code VARCHAR(60) NULL,
  document_id VARCHAR(30) NULL,
  job_type ENUM('baker','packer','operator','admin','other') NOT NULL DEFAULT 'other',
  status ENUM('active','inactive') NOT NULL DEFAULT 'active',
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_employees_user (user_id),
  UNIQUE KEY uq_employees_code (employee_code),
  KEY idx_employees_job_type (job_type),
  KEY idx_employees_status (status),
  CONSTRAINT fk_employees_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS recipe_outputs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipe_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  expected_quantity DECIMAL(14,3) NOT NULL,
  packing_note VARCHAR(255) NULL,
  sort_order INT UNSIGNED NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipe_outputs_recipe_product (recipe_id, product_id),
  KEY idx_recipe_outputs_product (product_id),
  CONSTRAINT fk_recipe_outputs_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_recipe_outputs_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_recipe_outputs_qty CHECK (expected_quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS production_batches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  branch_id BIGINT UNSIGNED NOT NULL,
  recipe_id BIGINT UNSIGNED NOT NULL,
  baker_employee_id BIGINT UNSIGNED NOT NULL,
  produced_date DATE NOT NULL,
  batch_quantity DECIMAL(14,3) NOT NULL DEFAULT 1,
  status ENUM('pending_packaging','partially_packed','packed','cancelled') NOT NULL DEFAULT 'pending_packaging',
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_batches_branch_date (branch_id, produced_date),
  KEY idx_production_batches_recipe (recipe_id),
  KEY idx_production_batches_baker (baker_employee_id),
  KEY idx_production_batches_status (status),
  CONSTRAINT fk_production_batches_branch
    FOREIGN KEY (branch_id) REFERENCES branches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_batches_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_batches_baker
    FOREIGN KEY (baker_employee_id) REFERENCES employees (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_batches_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_production_batches_qty CHECK (batch_quantity > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS production_batch_outputs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_batch_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  expected_quantity DECIMAL(14,3) NOT NULL,
  produced_quantity DECIMAL(14,3) NOT NULL,
  packed_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  damaged_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  missing_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  packing_note VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_batch_outputs_batch_product (production_batch_id, product_id),
  KEY idx_batch_outputs_product (product_id),
  CONSTRAINT fk_batch_outputs_batch
    FOREIGN KEY (production_batch_id) REFERENCES production_batches (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_batch_outputs_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_batch_outputs_qty CHECK (
    expected_quantity > 0
    AND produced_quantity >= 0
    AND packed_quantity >= 0
    AND damaged_quantity >= 0
    AND missing_quantity >= 0
  )
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS packing_reports (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_batch_id BIGINT UNSIGNED NOT NULL,
  packer_employee_id BIGINT UNSIGNED NOT NULL,
  packed_date DATE NOT NULL,
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_packing_reports_batch (production_batch_id),
  KEY idx_packing_reports_packer (packer_employee_id),
  KEY idx_packing_reports_date (packed_date),
  CONSTRAINT fk_packing_reports_batch
    FOREIGN KEY (production_batch_id) REFERENCES production_batches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_packing_reports_packer
    FOREIGN KEY (packer_employee_id) REFERENCES employees (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_packing_reports_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS packing_report_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  packing_report_id BIGINT UNSIGNED NOT NULL,
  production_batch_output_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  packed_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  damaged_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  missing_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  damage_reason ENUM('cut','packaging') NULL,
  missing_reason ENUM('count_difference','handling_loss','suspected_theft','other') NULL,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_packing_report_output (packing_report_id, production_batch_output_id),
  KEY idx_packing_report_items_report (packing_report_id),
  KEY idx_packing_report_items_output (production_batch_output_id),
  KEY idx_packing_report_items_product (product_id),
  CONSTRAINT fk_packing_items_report
    FOREIGN KEY (packing_report_id) REFERENCES packing_reports (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_packing_items_output
    FOREIGN KEY (production_batch_output_id) REFERENCES production_batch_outputs (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_packing_items_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_packing_items_qty CHECK (
    packed_quantity >= 0
    AND damaged_quantity >= 0
    AND missing_quantity >= 0
  )
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS production_damages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_batch_id BIGINT UNSIGNED NOT NULL,
  production_batch_output_id BIGINT UNSIGNED NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  responsible_employee_id BIGINT UNSIGNED NULL,
  damage_stage ENUM('oven','cut','packaging') NOT NULL,
  quantity DECIMAL(14,3) NOT NULL,
  damaged_date DATE NOT NULL,
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_damages_batch (production_batch_id),
  KEY idx_production_damages_product (product_id),
  KEY idx_production_damages_responsible (responsible_employee_id),
  KEY idx_production_damages_date (damaged_date),
  CONSTRAINT fk_production_damages_batch
    FOREIGN KEY (production_batch_id) REFERENCES production_batches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_damages_output
    FOREIGN KEY (production_batch_output_id) REFERENCES production_batch_outputs (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_production_damages_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_damages_responsible
    FOREIGN KEY (responsible_employee_id) REFERENCES employees (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_production_damages_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_production_damages_qty CHECK (quantity > 0)
) ENGINE=InnoDB;

INSERT INTO roles (code, name, description, is_system_role)
VALUES
  ('PANADERO', 'Panadero', 'Registra produccion y reporta danos de produccion', 0),
  ('EMPAQUETADOR', 'Empaquetador', 'Registra empaque y danos de corte o empaque', 0)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

INSERT INTO permissions (code, name, description)
VALUES
  ('employees.manage', 'Gestionar empleados', 'Crear y consultar empleados operativos'),
  ('packaging.manage', 'Gestionar empaque', 'Registrar empaque de produccion'),
  ('production.damage.manage', 'Gestionar danos de produccion', 'Registrar danos de horno, corte o empaque')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('production.manage', 'recipes.manage', 'reports.view')
WHERE r.code = 'PANADERO';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('production.manage', 'packaging.manage', 'production.damage.manage', 'reports.view')
WHERE r.code = 'EMPAQUETADOR';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('employees.manage', 'packaging.manage', 'production.damage.manage')
WHERE r.code IN ('ADMIN', 'SUPER_ADMIN');

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_employee_create $$
CREATE PROCEDURE sp_employee_create(
  IN p_user_id BIGINT UNSIGNED,
  IN p_employee_code VARCHAR(60),
  IN p_document_id VARCHAR(30),
  IN p_job_type VARCHAR(30),
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_employee_id BIGINT UNSIGNED;
  DECLARE v_job_type VARCHAR(30) DEFAULT 'other';

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

  SET v_job_type = CASE
    WHEN p_job_type IN ('baker','packer','operator','admin','other') THEN p_job_type
    ELSE 'other'
  END;

  START TRANSACTION;

  IF NOT EXISTS (
    SELECT 1
    FROM users
    WHERE id = p_user_id
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'usuario no encontrado o inactivo';
  END IF;

  INSERT INTO employees (
    user_id,
    employee_code,
    document_id,
    job_type,
    status,
    notes
  )
  VALUES (
    p_user_id,
    NULLIF(TRIM(p_employee_code), ''),
    NULLIF(TRIM(p_document_id), ''),
    v_job_type,
    'active',
    p_notes
  );

  SET v_employee_id = LAST_INSERT_ID();

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'employee.create',
    'employees',
    CAST(v_employee_id AS CHAR),
    JSON_OBJECT('user_id', p_user_id, 'job_type', v_job_type)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'empleado creado';
  SET o_data_json = JSON_OBJECT('employee_id', v_employee_id);
END $$

DROP PROCEDURE IF EXISTS sp_employee_list $$
CREATE PROCEDURE sp_employee_list(
  IN p_status VARCHAR(20),
  IN p_job_type VARCHAR(30),
  IN p_search VARCHAR(120),
  IN p_page INT,
  IN p_page_size INT,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_page INT DEFAULT 1;
  DECLARE v_page_size INT DEFAULT 50;
  DECLARE v_offset INT DEFAULT 0;

  SET v_page = GREATEST(COALESCE(p_page, 1), 1);
  SET v_page_size = LEAST(GREATEST(COALESCE(p_page_size, 50), 1), 200);
  SET v_offset = (v_page - 1) * v_page_size;

  SET o_code = 1;
  SET o_message = 'empleados listados';

  SELECT JSON_OBJECT(
    'items',
    COALESCE(JSON_ARRAYAGG(
      JSON_OBJECT(
        'id', x.id,
        'user_id', x.user_id,
        'employee_code', x.employee_code,
        'document_id', x.document_id,
        'job_type', x.job_type,
        'status', x.status,
        'notes', x.notes,
        'full_name', x.full_name,
        'username', x.username,
        'email', x.email
      )
    ), JSON_ARRAY()),
    'page', v_page,
    'pageSize', v_page_size
  )
  INTO o_data_json
  FROM (
    SELECT
      e.id,
      e.user_id,
      e.employee_code,
      e.document_id,
      e.job_type,
      e.status,
      e.notes,
      u.full_name,
      u.username,
      u.email
    FROM employees e
    INNER JOIN users u ON u.id = e.user_id
    WHERE e.deleted_at IS NULL
      AND (p_status IS NULL OR p_status = '' OR e.status = p_status)
      AND (p_job_type IS NULL OR p_job_type = '' OR e.job_type = p_job_type)
      AND (
        p_search IS NULL OR p_search = ''
        OR u.full_name LIKE CONCAT('%', p_search, '%')
        OR u.username LIKE CONCAT('%', p_search, '%')
        OR u.email LIKE CONCAT('%', p_search, '%')
        OR e.employee_code LIKE CONCAT('%', p_search, '%')
        OR e.document_id LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY u.full_name
    LIMIT v_page_size OFFSET v_offset
  ) x;
END $$

DROP PROCEDURE IF EXISTS sp_recipe_output_add $$
CREATE PROCEDURE sp_recipe_output_add(
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_product_id BIGINT UNSIGNED,
  IN p_expected_quantity DECIMAL(14,3),
  IN p_packing_note VARCHAR(255),
  IN p_sort_order INT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_output_id BIGINT UNSIGNED;

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

  IF p_expected_quantity IS NULL OR p_expected_quantity <= 0 THEN
    SET o_code = 0;
    SET o_message = 'la cantidad esperada debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM recipes WHERE id = p_recipe_id) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'receta no encontrada';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM products
      WHERE id = p_product_id
        AND is_active = 1
        AND deleted_at IS NULL
    ) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'producto no encontrado o inactivo';
    END IF;

    INSERT INTO recipe_outputs (
      recipe_id,
      product_id,
      expected_quantity,
      packing_note,
      sort_order
    )
    VALUES (
      p_recipe_id,
      p_product_id,
      p_expected_quantity,
      p_packing_note,
      COALESCE(p_sort_order, 1)
    )
    ON DUPLICATE KEY UPDATE
      expected_quantity = VALUES(expected_quantity),
      packing_note = VALUES(packing_note),
      sort_order = VALUES(sort_order),
      updated_at = CURRENT_TIMESTAMP;

    SELECT id INTO v_output_id
    FROM recipe_outputs
    WHERE recipe_id = p_recipe_id
      AND product_id = p_product_id;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'recipe.output.upsert',
      'recipe_outputs',
      CAST(v_output_id AS CHAR),
      JSON_OBJECT('recipe_id', p_recipe_id, 'product_id', p_product_id, 'expected_quantity', p_expected_quantity)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'producto final de receta guardado';
    SET o_data_json = JSON_OBJECT('recipe_output_id', v_output_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_recipe_output_remove $$
CREATE PROCEDURE sp_recipe_output_remove(
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_product_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_output_id BIGINT UNSIGNED;
  DECLARE v_output_count INT DEFAULT 0;

  SELECT COUNT(*) INTO v_output_count
  FROM recipe_outputs
  WHERE recipe_id = p_recipe_id
    AND product_id = p_product_id;

  IF v_output_count = 0 THEN
    SET o_code = 0;
    SET o_message = 'producto final de receta no encontrado';
    SET o_data_json = NULL;
  ELSE
    SELECT id INTO v_output_id
    FROM recipe_outputs
    WHERE recipe_id = p_recipe_id
      AND product_id = p_product_id;

    START TRANSACTION;

    DELETE FROM recipe_outputs WHERE id = v_output_id;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'recipe.output.remove',
      'recipe_outputs',
      CAST(v_output_id AS CHAR),
      JSON_OBJECT('recipe_id', p_recipe_id, 'product_id', p_product_id)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'producto final de receta eliminado';
    SET o_data_json = JSON_OBJECT('recipe_output_id', v_output_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_recipe_outputs_list $$
CREATE PROCEDURE sp_recipe_outputs_list(
  IN p_recipe_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  SET o_code = 1;
  SET o_message = 'productos finales de receta listados';

  SELECT COALESCE(JSON_ARRAYAGG(
    JSON_OBJECT(
      'id', ro.id,
      'recipe_id', ro.recipe_id,
      'product_id', ro.product_id,
      'product_name', p.name,
      'product_sku', p.sku,
      'expected_quantity', ro.expected_quantity,
      'packing_note', ro.packing_note,
      'sort_order', ro.sort_order
    )
  ), JSON_ARRAY())
  INTO o_data_json
  FROM recipe_outputs ro
  INNER JOIN products p ON p.id = ro.product_id
  WHERE ro.recipe_id = p_recipe_id
  ORDER BY ro.sort_order, p.name;
END $$

DROP PROCEDURE IF EXISTS sp_production_batch_register $$
CREATE PROCEDURE sp_production_batch_register(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_baker_employee_id BIGINT UNSIGNED,
  IN p_produced_date DATE,
  IN p_batch_quantity DECIMAL(14,3),
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_batch_id BIGINT UNSIGNED;
  DECLARE v_batch_qty DECIMAL(14,3) DEFAULT 1;
  DECLARE v_recipe_output_qty DECIMAL(12,3);
  DECLARE v_output_count INT DEFAULT 0;

  DECLARE v_raw_material_id BIGINT UNSIGNED;
  DECLARE v_base_qty DECIMAL(12,4);
  DECLARE v_wastage DECIMAL(5,2);
  DECLARE v_required_qty DECIMAL(14,3);
  DECLARE v_stock_qty DECIMAL(14,3);
  DECLARE v_signal_msg VARCHAR(255);

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE done INT DEFAULT 0;

  DECLARE cur_recipe CURSOR FOR
    SELECT raw_material_id, quantity, wastage_percent
    FROM recipe_items
    WHERE recipe_id = p_recipe_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  SET v_batch_qty = COALESCE(p_batch_quantity, 1);

  IF v_batch_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad de produccion debe ser mayor que 0';
  END IF;

  START TRANSACTION;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sucursal no encontrada o inactiva';
  END IF;

  SELECT output_quantity
    INTO v_recipe_output_qty
  FROM recipes
  WHERE id = p_recipe_id
    AND is_active = 1
  FOR UPDATE;

  IF v_recipe_output_qty IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'receta no encontrada o inactiva';
  END IF;

  SELECT COUNT(*) INTO v_output_count
  FROM recipe_outputs
  WHERE recipe_id = p_recipe_id;

  IF v_output_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la receta no tiene productos finales asociados';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM employees
    WHERE id = p_baker_employee_id
      AND job_type = 'baker'
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'panadero no encontrado o inactivo';
  END IF;

  INSERT INTO production_batches (
    branch_id,
    recipe_id,
    baker_employee_id,
    produced_date,
    batch_quantity,
    status,
    notes,
    created_by
  )
  VALUES (
    p_branch_id,
    p_recipe_id,
    p_baker_employee_id,
    COALESCE(p_produced_date, CURRENT_DATE),
    v_batch_qty,
    'pending_packaging',
    p_notes,
    p_actor_user_id
  );

  SET v_batch_id = LAST_INSERT_ID();

  OPEN cur_recipe;

  read_loop: LOOP
    FETCH cur_recipe INTO v_raw_material_id, v_base_qty, v_wastage;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    SET v_required_qty = ROUND((v_base_qty * v_batch_qty) * (1 + (v_wastage / 100)), 3);

    INSERT IGNORE INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
    VALUES (p_branch_id, v_raw_material_id, 0, 0);

    SELECT quantity_on_hand
      INTO v_stock_qty
    FROM stock_raw_materials
    WHERE branch_id = p_branch_id
      AND raw_material_id = v_raw_material_id
    FOR UPDATE;

    IF v_stock_qty < v_required_qty THEN
      SET v_signal_msg = CONCAT('stock insuficiente para materia prima ', v_raw_material_id);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_signal_msg;
    END IF;

    UPDATE stock_raw_materials
    SET quantity_on_hand = quantity_on_hand - v_required_qty
    WHERE branch_id = p_branch_id
      AND raw_material_id = v_raw_material_id;

    INSERT INTO inventory_movements (
      branch_id, item_type, raw_material_id, product_id, movement_type,
      quantity, unit_cost, reference_type, reference_id, notes, created_by
    )
    VALUES (
      p_branch_id, 'raw_material', v_raw_material_id, NULL, 'production_out',
      v_required_qty, NULL, 'production_batch', v_batch_id, p_notes, p_actor_user_id
    );
  END LOOP;

  CLOSE cur_recipe;

  INSERT INTO production_batch_outputs (
    production_batch_id,
    product_id,
    expected_quantity,
    produced_quantity,
    packing_note
  )
  SELECT
    v_batch_id,
    product_id,
    expected_quantity,
    ROUND(expected_quantity * v_batch_qty, 3),
    packing_note
  FROM recipe_outputs
  WHERE recipe_id = p_recipe_id;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'production_batch.register',
    'production_batches',
    CAST(v_batch_id AS CHAR),
    JSON_OBJECT('branch_id', p_branch_id, 'recipe_id', p_recipe_id, 'baker_employee_id', p_baker_employee_id, 'batch_quantity', v_batch_qty)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'produccion registrada y pendiente por empacar';
  SET o_data_json = JSON_OBJECT('production_batch_id', v_batch_id);
END $$

DROP PROCEDURE IF EXISTS sp_packing_pending_list $$
CREATE PROCEDURE sp_packing_pending_list(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_search VARCHAR(120),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  SET o_code = 1;
  SET o_message = 'pendientes por empacar listados';

  SELECT COALESCE(JSON_ARRAYAGG(
    JSON_OBJECT(
      'production_batch_id', x.production_batch_id,
      'branch_id', x.branch_id,
      'branch_name', x.branch_name,
      'recipe_id', x.recipe_id,
      'recipe_name', x.recipe_name,
      'baker_employee_id', x.baker_employee_id,
      'baker_name', x.baker_name,
      'produced_date', x.produced_date,
      'status', x.status,
      'items', x.items
    )
  ), JSON_ARRAY())
  INTO o_data_json
  FROM (
    SELECT
      pb.id AS production_batch_id,
      pb.branch_id,
      b.name AS branch_name,
      pb.recipe_id,
      COALESCE(r.notes, p.name) AS recipe_name,
      pb.baker_employee_id,
      u.full_name AS baker_name,
      pb.produced_date,
      pb.status,
      JSON_ARRAYAGG(
        JSON_OBJECT(
          'production_batch_output_id', pbo.id,
          'product_id', pbo.product_id,
          'product_name', po.name,
          'product_sku', po.sku,
          'produced_quantity', pbo.produced_quantity,
          'packed_quantity', pbo.packed_quantity,
          'damaged_quantity', pbo.damaged_quantity,
          'pending_quantity', GREATEST(pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity, 0),
          'packing_note', pbo.packing_note
        )
      ) AS items
    FROM production_batches pb
    INNER JOIN branches b ON b.id = pb.branch_id
    INNER JOIN recipes r ON r.id = pb.recipe_id
    INNER JOIN products p ON p.id = r.product_id
    INNER JOIN employees e ON e.id = pb.baker_employee_id
    INNER JOIN users u ON u.id = e.user_id
    INNER JOIN production_batch_outputs pbo ON pbo.production_batch_id = pb.id
    INNER JOIN products po ON po.id = pbo.product_id
    WHERE pb.status IN ('pending_packaging','partially_packed')
      AND (p_branch_id IS NULL OR pb.branch_id = p_branch_id)
      AND (
        p_search IS NULL OR p_search = ''
        OR po.name LIKE CONCAT('%', p_search, '%')
        OR u.full_name LIKE CONCAT('%', p_search, '%')
        OR p.name LIKE CONCAT('%', p_search, '%')
        OR r.notes LIKE CONCAT('%', p_search, '%')
      )
    GROUP BY
      pb.id,
      pb.branch_id,
      b.name,
      pb.recipe_id,
      r.notes,
      p.name,
      pb.baker_employee_id,
      u.full_name,
      pb.produced_date,
      pb.status
    ORDER BY pb.produced_date DESC, pb.id DESC
  ) x;
END $$

DROP PROCEDURE IF EXISTS sp_packing_report_create $$
CREATE PROCEDURE sp_packing_report_create(
  IN p_production_batch_id BIGINT UNSIGNED,
  IN p_packer_employee_id BIGINT UNSIGNED,
  IN p_packed_date DATE,
  IN p_items_json JSON,
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_report_id BIGINT UNSIGNED;
  DECLARE v_branch_id BIGINT UNSIGNED;
  DECLARE v_item_count INT DEFAULT 0;
  DECLARE v_pending_count INT DEFAULT 0;

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

  SELECT branch_id INTO v_branch_id
  FROM production_batches
  WHERE id = p_production_batch_id
    AND status IN ('pending_packaging','partially_packed')
  FOR UPDATE;

  IF v_branch_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'produccion no encontrada o no pendiente por empacar';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM employees
    WHERE id = p_packer_employee_id
      AND job_type = 'packer'
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'empaquetador no encontrado o inactivo';
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_packing_items;

  CREATE TEMPORARY TABLE tmp_packing_items (
    production_batch_output_id BIGINT UNSIGNED NOT NULL,
    packed_quantity DECIMAL(14,3) NOT NULL,
    damaged_quantity DECIMAL(14,3) NOT NULL,
    damage_reason VARCHAR(30) NULL,
    notes VARCHAR(255) NULL
  ) ENGINE=Memory;

  INSERT INTO tmp_packing_items (
    production_batch_output_id,
    packed_quantity,
    damaged_quantity,
    damage_reason,
    notes
  )
  SELECT
    jt.production_batch_output_id,
    COALESCE(jt.packed_quantity, 0),
    COALESCE(jt.damaged_quantity, 0),
    jt.damage_reason,
    jt.notes
  FROM JSON_TABLE(
    p_items_json,
    '$[*]' COLUMNS (
      production_batch_output_id BIGINT UNSIGNED PATH '$.production_batch_output_id',
      packed_quantity DECIMAL(14,3) PATH '$.packed_quantity' DEFAULT '0' ON EMPTY,
      damaged_quantity DECIMAL(14,3) PATH '$.damaged_quantity' DEFAULT '0' ON EMPTY,
      damage_reason VARCHAR(30) PATH '$.damage_reason' NULL ON EMPTY,
      notes VARCHAR(255) PATH '$.notes' NULL ON EMPTY
    )
  ) jt;

  SELECT COUNT(*) INTO v_item_count FROM tmp_packing_items;

  IF v_item_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'agrega al menos un producto empacado';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_packing_items
    WHERE packed_quantity < 0
      OR damaged_quantity < 0
      OR (packed_quantity + damaged_quantity) <= 0
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'las cantidades deben ser mayores o iguales a 0 y al menos una debe ser mayor que 0';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_packing_items t
    LEFT JOIN production_batch_outputs pbo
      ON pbo.id = t.production_batch_output_id
     AND pbo.production_batch_id = p_production_batch_id
    WHERE pbo.id IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'un producto no pertenece a la produccion seleccionada';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_packing_items t
    INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
    WHERE (t.packed_quantity + t.damaged_quantity) > (pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity)
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad empacada o danada supera el pendiente';
  END IF;

  INSERT INTO packing_reports (
    production_batch_id,
    packer_employee_id,
    packed_date,
    notes,
    created_by
  )
  VALUES (
    p_production_batch_id,
    p_packer_employee_id,
    COALESCE(p_packed_date, CURRENT_DATE),
    p_notes,
    p_actor_user_id
  );

  SET v_report_id = LAST_INSERT_ID();

  INSERT INTO packing_report_items (
    packing_report_id,
    production_batch_output_id,
    product_id,
    packed_quantity,
    damaged_quantity,
    damage_reason,
    notes
  )
  SELECT
    v_report_id,
    pbo.id,
    pbo.product_id,
    t.packed_quantity,
    t.damaged_quantity,
    CASE WHEN t.damage_reason IN ('cut','packaging') THEN t.damage_reason ELSE NULL END,
    t.notes
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id;

  INSERT INTO production_damages (
    production_batch_id,
    production_batch_output_id,
    product_id,
    responsible_employee_id,
    damage_stage,
    quantity,
    damaged_date,
    notes,
    created_by
  )
  SELECT
    p_production_batch_id,
    pbo.id,
    pbo.product_id,
    p_packer_employee_id,
    CASE WHEN t.damage_reason = 'cut' THEN 'cut' ELSE 'packaging' END,
    t.damaged_quantity,
    COALESCE(p_packed_date, CURRENT_DATE),
    t.notes,
    p_actor_user_id
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
  WHERE t.damaged_quantity > 0;

  UPDATE production_batch_outputs pbo
  INNER JOIN tmp_packing_items t ON t.production_batch_output_id = pbo.id
  SET pbo.packed_quantity = pbo.packed_quantity + t.packed_quantity,
      pbo.damaged_quantity = pbo.damaged_quantity + t.damaged_quantity,
      pbo.updated_at = CURRENT_TIMESTAMP;

  INSERT INTO inventory_movements (
    branch_id, item_type, raw_material_id, product_id, movement_type,
    quantity, unit_cost, reference_type, reference_id, notes, created_by
  )
  SELECT
    v_branch_id, 'product', NULL, pbo.product_id, 'production_in',
    t.packed_quantity, NULL, 'packing_report', v_report_id, p_notes, p_actor_user_id
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
  WHERE t.packed_quantity > 0;

  INSERT INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
  SELECT DISTINCT v_branch_id, pbo.product_id, 0, 0
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
  ON DUPLICATE KEY UPDATE quantity_on_hand = quantity_on_hand;

  UPDATE stock_products sp
  INNER JOIN (
    SELECT pbo.product_id, SUM(t.packed_quantity) AS qty
    FROM tmp_packing_items t
    INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
    GROUP BY pbo.product_id
  ) x ON x.product_id = sp.product_id
  SET sp.quantity_on_hand = sp.quantity_on_hand + x.qty
  WHERE sp.branch_id = v_branch_id;

  SELECT COUNT(*) INTO v_pending_count
  FROM production_batch_outputs
  WHERE production_batch_id = p_production_batch_id
    AND (produced_quantity - packed_quantity - damaged_quantity) > 0;

  UPDATE production_batches
  SET status = CASE WHEN v_pending_count = 0 THEN 'packed' ELSE 'partially_packed' END,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_production_batch_id;

  DROP TEMPORARY TABLE IF EXISTS tmp_packing_items;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'packing.report.create',
    'packing_reports',
    CAST(v_report_id AS CHAR),
    JSON_OBJECT('production_batch_id', p_production_batch_id, 'packer_employee_id', p_packer_employee_id)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'empaque registrado';
  SET o_data_json = JSON_OBJECT('packing_report_id', v_report_id);
END $$

DROP PROCEDURE IF EXISTS sp_production_damage_register $$
CREATE PROCEDURE sp_production_damage_register(
  IN p_production_batch_id BIGINT UNSIGNED,
  IN p_production_batch_output_id BIGINT UNSIGNED,
  IN p_product_id BIGINT UNSIGNED,
  IN p_responsible_employee_id BIGINT UNSIGNED,
  IN p_damage_stage VARCHAR(30),
  IN p_quantity DECIMAL(14,3),
  IN p_damaged_date DATE,
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_damage_id BIGINT UNSIGNED;
  DECLARE v_output_id BIGINT UNSIGNED;
  DECLARE v_product_id BIGINT UNSIGNED;
  DECLARE v_pending_qty DECIMAL(14,3);
  DECLARE v_output_count INT DEFAULT 0;
  DECLARE v_pending_count INT DEFAULT 0;
  DECLARE v_stage VARCHAR(30);

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

  SET v_stage = CASE
    WHEN p_damage_stage IN ('oven','cut','packaging') THEN p_damage_stage
    ELSE NULL
  END;

  IF v_stage IS NULL THEN
    SET o_code = 0;
    SET o_message = 'motivo de dano invalido';
    SET o_data_json = NULL;
  ELSEIF p_quantity IS NULL OR p_quantity <= 0 THEN
    SET o_code = 0;
    SET o_message = 'la cantidad danada debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    IF p_production_batch_output_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_output_count
      FROM production_batch_outputs pbo
      WHERE pbo.id = p_production_batch_output_id
        AND pbo.production_batch_id = p_production_batch_id;
    ELSE
      SET v_output_count = 0;
    END IF;

    IF v_output_count > 0 THEN
      SELECT
        pbo.id,
        pbo.product_id,
        (pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity)
      INTO v_output_id, v_product_id, v_pending_qty
      FROM production_batch_outputs pbo
      WHERE pbo.production_batch_id = p_production_batch_id
        AND pbo.id = p_production_batch_output_id
      FOR UPDATE;
    ELSE
      SELECT COUNT(*) INTO v_output_count
      FROM production_batch_outputs pbo
      WHERE pbo.production_batch_id = p_production_batch_id
        AND pbo.product_id = p_product_id;

      IF v_output_count > 0 THEN
        SELECT
          pbo.id,
          pbo.product_id,
          (pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity)
        INTO v_output_id, v_product_id, v_pending_qty
        FROM production_batch_outputs pbo
        WHERE pbo.production_batch_id = p_production_batch_id
          AND pbo.product_id = p_product_id
        LIMIT 1
        FOR UPDATE;
      END IF;
    END IF;

    IF v_output_id IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'producto producido no encontrado';
    END IF;

    IF v_pending_qty < p_quantity THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad danada supera el pendiente';
    END IF;

    IF p_responsible_employee_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM employees
        WHERE id = p_responsible_employee_id
          AND status = 'active'
          AND deleted_at IS NULL
      ) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'responsable no encontrado o inactivo';
    END IF;

    INSERT INTO production_damages (
      production_batch_id,
      production_batch_output_id,
      product_id,
      responsible_employee_id,
      damage_stage,
      quantity,
      damaged_date,
      notes,
      created_by
    )
    VALUES (
      p_production_batch_id,
      v_output_id,
      v_product_id,
      p_responsible_employee_id,
      v_stage,
      p_quantity,
      COALESCE(p_damaged_date, CURRENT_DATE),
      p_notes,
      p_actor_user_id
    );

    SET v_damage_id = LAST_INSERT_ID();

    UPDATE production_batch_outputs
    SET damaged_quantity = damaged_quantity + p_quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_output_id;

    SELECT COUNT(*) INTO v_pending_count
    FROM production_batch_outputs
    WHERE production_batch_id = p_production_batch_id
      AND (produced_quantity - packed_quantity - damaged_quantity) > 0;

    UPDATE production_batches
    SET status = CASE WHEN v_pending_count = 0 THEN 'packed' ELSE 'partially_packed' END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_production_batch_id;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'production.damage.register',
      'production_damages',
      CAST(v_damage_id AS CHAR),
      JSON_OBJECT('production_batch_id', p_production_batch_id, 'product_id', v_product_id, 'damage_stage', v_stage, 'quantity', p_quantity)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'dano de produccion registrado';
    SET o_data_json = JSON_OBJECT('production_damage_id', v_damage_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_raw_material_usage_report $$
CREATE PROCEDURE sp_raw_material_usage_report(
  IN p_date_from DATE,
  IN p_date_to DATE,
  IN p_branch_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  SET o_code = 1;
  SET o_message = 'reporte de materias primas generado';

  SELECT COALESCE(JSON_ARRAYAGG(
    JSON_OBJECT(
      'raw_material_id', x.raw_material_id,
      'raw_material_name', x.raw_material_name,
      'raw_material_sku', x.raw_material_sku,
      'grams_used', x.grams_used,
      'bag_size_grams', x.bag_size_grams,
      'bags_used', x.bags_used,
      'unit_cost', x.unit_cost,
      'estimated_cost', x.estimated_cost
    )
  ), JSON_ARRAY())
  INTO o_data_json
  FROM (
    SELECT
      rm.id AS raw_material_id,
      rm.name AS raw_material_name,
      rm.sku AS raw_material_sku,
      SUM(im.quantity) AS grams_used,
      rm.bag_size_grams,
      CASE
        WHEN rm.bag_size_grams IS NULL OR rm.bag_size_grams <= 0 THEN NULL
        ELSE ROUND(SUM(im.quantity) / rm.bag_size_grams, 3)
      END AS bags_used,
      rm.unit_cost,
      ROUND(SUM(im.quantity) * rm.unit_cost, 2) AS estimated_cost
    FROM inventory_movements im
    INNER JOIN raw_materials rm ON rm.id = im.raw_material_id
    WHERE im.item_type = 'raw_material'
      AND im.movement_type = 'production_out'
      AND DATE(im.moved_at) BETWEEN COALESCE(p_date_from, CURRENT_DATE) AND COALESCE(p_date_to, CURRENT_DATE)
      AND (p_branch_id IS NULL OR im.branch_id = p_branch_id)
    GROUP BY rm.id, rm.name, rm.sku, rm.bag_size_grams, rm.unit_cost
    ORDER BY rm.name
  ) x;
END $$

DROP PROCEDURE IF EXISTS sp_packing_summary_report $$
CREATE PROCEDURE sp_packing_summary_report(
  IN p_date_from DATE,
  IN p_date_to DATE,
  IN p_branch_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  SET o_code = 1;
  SET o_message = 'reporte de empaque generado';

  SELECT COALESCE(JSON_ARRAYAGG(
    JSON_OBJECT(
      'product_id', x.product_id,
      'product_name', x.product_name,
      'product_sku', x.product_sku,
      'packed_quantity', x.packed_quantity,
      'damaged_quantity', x.damaged_quantity,
      'bakers', x.bakers,
      'packers', x.packers
    )
  ), JSON_ARRAY())
  INTO o_data_json
  FROM (
    SELECT
      p.id AS product_id,
      p.name AS product_name,
      p.sku AS product_sku,
      SUM(pri.packed_quantity) AS packed_quantity,
      SUM(pri.damaged_quantity) AS damaged_quantity,
      GROUP_CONCAT(DISTINCT baker_user.full_name ORDER BY baker_user.full_name SEPARATOR ', ') AS bakers,
      GROUP_CONCAT(DISTINCT packer_user.full_name ORDER BY packer_user.full_name SEPARATOR ', ') AS packers
    FROM packing_report_items pri
    INNER JOIN packing_reports pr ON pr.id = pri.packing_report_id
    INNER JOIN production_batches pb ON pb.id = pr.production_batch_id
    INNER JOIN products p ON p.id = pri.product_id
    INNER JOIN employees baker ON baker.id = pb.baker_employee_id
    INNER JOIN users baker_user ON baker_user.id = baker.user_id
    INNER JOIN employees packer ON packer.id = pr.packer_employee_id
    INNER JOIN users packer_user ON packer_user.id = packer.user_id
    WHERE pr.packed_date BETWEEN COALESCE(p_date_from, CURRENT_DATE) AND COALESCE(p_date_to, CURRENT_DATE)
      AND (p_branch_id IS NULL OR pb.branch_id = p_branch_id)
    GROUP BY p.id, p.name, p.sku
    ORDER BY p.name
  ) x;
END $$

DELIMITER ;
