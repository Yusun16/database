-- Custom display name for employees using the generic "other" job type.
-- Run after:
--   047_order_notifications_and_prints.sql

USE panaderia_db;

SET @employees_custom_job_title_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'employees'
    AND COLUMN_NAME = 'custom_job_title'
);

SET @employees_custom_job_title_sql = IF(
  @employees_custom_job_title_exists = 0,
  'ALTER TABLE employees
     ADD COLUMN custom_job_title VARCHAR(100) NULL AFTER job_type,
     ADD KEY idx_employees_custom_job_title (custom_job_title)',
  'SELECT 1'
);

PREPARE employees_custom_job_title_stmt FROM @employees_custom_job_title_sql;
EXECUTE employees_custom_job_title_stmt;
DEALLOCATE PREPARE employees_custom_job_title_stmt;
