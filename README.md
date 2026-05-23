# Base de datos inicial (MySQL 8)

Archivo principal de esquema:

- `database/001_init_schema.sql`
- `database/002_business_procedures.sql`
- `database/003_sp_flow_blueprint.md`
- `database/004_auth_procedures.sql`
- `database/005_auth_smoke_tests.sql`
- `database/006_auth_admin_procedures.sql`
- `database/007_auth_admin_smoke_tests.sql`
- `database/008_catalog_procedures.sql`
- `database/009_catalog_smoke_tests.sql`
- `database/010_customer_route_procedures.sql`
- `database/011_customer_route_smoke_tests.sql`
- `database/012_operational_procedures.sql`
- `database/013_operational_smoke_tests.sql`
- `database/014_reporting_views.sql`
- `database/015_reporting_smoke_tests.sql`
- `database/016_recipe_procedures.sql`
- `database/017_recipe_smoke_tests.sql`
- `database/018_rbac_procedures.sql`
- `database/019_rbac_smoke_tests.sql`
- `database/020_sp_unix_manual.md`
- `database/021_business_rules_coverage_audit.md`
- `database/022_standardization_baseline.sql`
- `database/023_standardization_contract_views.sql`
- `database/024_standardization_smoke_tests.sql`
- `database/025_mysql_sp_architecture_standard.md`
- `database/026_mysql_sp_template.sql`
- `database/027_read_procedures.sql`
- `database/028_read_smoke_tests.sql`
- `database/029_sp_functional_catalog.md`

## Requisitos

- MySQL 8.0+
- `sql_mode` estricto recomendado:

```sql
SET GLOBAL sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
```

## Ejecucion

```bash
mysql -u root -p < database/001_init_schema.sql
mysql -u root -p < database/002_business_procedures.sql
mysql -u root -p < database/004_auth_procedures.sql
mysql -u root -p < database/006_auth_admin_procedures.sql
mysql -u root -p < database/005_auth_smoke_tests.sql
mysql -u root -p < database/007_auth_admin_smoke_tests.sql
mysql -u root -p < database/008_catalog_procedures.sql
mysql -u root -p < database/009_catalog_smoke_tests.sql
mysql -u root -p < database/010_customer_route_procedures.sql
mysql -u root -p < database/011_customer_route_smoke_tests.sql
mysql -u root -p < database/012_operational_procedures.sql
mysql -u root -p < database/013_operational_smoke_tests.sql
mysql -u root -p < database/014_reporting_views.sql
mysql -u root -p < database/015_reporting_smoke_tests.sql
mysql -u root -p < database/016_recipe_procedures.sql
mysql -u root -p < database/017_recipe_smoke_tests.sql
mysql -u root -p < database/018_rbac_procedures.sql
mysql -u root -p < database/027_read_procedures.sql
mysql -u root -p < database/028_read_smoke_tests.sql
mysql -u root -p < database/019_rbac_smoke_tests.sql
mysql -u root -p < database/022_standardization_baseline.sql
mysql -u root -p < database/023_standardization_contract_views.sql
mysql -u root -p < database/024_standardization_smoke_tests.sql
```

## SP de lectura (GET/LIST)

Script:

- `database/027_read_procedures.sql`

Procedimientos agregados:

- `sp_user_get_by_id`
- `sp_user_list`
- `sp_branch_list`
- `sp_customer_list`
- `sp_route_list`
- `sp_product_list`
- `sp_raw_material_list`

Notas:

- Mantienen el mismo contrato de salida (`o_code`, `o_message`, `o_data_json`).
- Son procedimientos de consulta (no escriben datos de negocio).
- Incluyen filtros y paginacion para consumo de frontend.

## Smoke test Lectura

Script:

- `database/028_read_smoke_tests.sql`

Casos cubiertos:

1. Consulta de usuario por id.
2. Listado paginado de usuarios.
3. Listado de sedes (todas y activas).
4. Listado paginado de clientes con y sin filtro de busqueda.
5. Listado de rutas con conductor vigente por fecha de referencia.
6. Listado paginado de productos con y sin filtro.
7. Listado paginado de materias primas con y sin filtro.

## SP de autenticacion (Sprint 1)

Procedimientos agregados:

- `sp_user_create`
- `sp_user_force_password_reset`
- `sp_auth_login_start`
- `sp_auth_login_fail`
- `sp_auth_login_success`
- `sp_auth_refresh_session`
- `sp_auth_logout`
- `sp_auth_change_password`
- `sp_permission_list_by_user`

Todos usan salida estandar por `OUT`:

- `o_code`
- `o_message`
- `o_data_json`

## Smoke test Auth

Script:

- `database/005_auth_smoke_tests.sql`

Casos cubiertos:

1. Alta de usuario.
2. Inicio de login (`sp_auth_login_start`).
3. Fallos de login y bloqueo por intentos.
4. Login exitoso y apertura de sesion.
5. Refresh de sesion.
6. Consulta de permisos.
7. Cambio de clave con revocacion de sesiones.
8. Nuevo login y logout.

## SP de administracion IAM (Sprint 2)

Procedimientos agregados:

- `sp_user_update_profile`
- `sp_user_assign_roles`
- `sp_user_set_status`
- `sp_auth_logout_all`
- `sp_auth_reset_password_admin`

Notas:

- `sp_user_assign_roles` recibe `p_role_codes_json` como arreglo JSON, por ejemplo: `["ADMIN","VENTAS"]`.
- `sp_user_set_status` revoca sesiones activas automaticamente cuando el estado no es `active`.

## Smoke test Auth Admin

Script:

- `database/007_auth_admin_smoke_tests.sql`

Casos cubiertos:

1. Update de perfil de usuario.
2. Asignacion de roles por JSON array.
3. Logout global (`sp_auth_logout_all`).
4. Reset de clave por admin (`sp_auth_reset_password_admin`).
5. Cambio de estado a `inactive` y revocacion automatica de sesiones.

## SP de catalogos (Fase B)

Procedimientos agregados:

- `sp_branch_create`
- `sp_branch_update`
- `sp_tax_rate_create`
- `sp_tax_rate_update`
- `sp_product_category_create`
- `sp_product_category_update`
- `sp_raw_material_category_create`
- `sp_raw_material_category_update`
- `sp_supplier_create`
- `sp_supplier_update`
- `sp_product_create`
- `sp_product_update`
- `sp_product_set_status`
- `sp_raw_material_create`
- `sp_raw_material_update`
- `sp_raw_material_set_status`

## Smoke test Catalogos

Script:

- `database/009_catalog_smoke_tests.sql`

Casos cubiertos:

1. Sedes.
2. Impuestos.
3. Categorias de productos.
4. Categorias de materias primas.
5. Proveedores.
6. Productos.
7. Materias primas.

## SP de clientes y rutas (Fase C)

Procedimientos agregados:

- `sp_customer_create`
- `sp_customer_update`
- `sp_customer_set_status`
- `sp_route_create`
- `sp_route_update`
- `sp_route_set_status`
- `sp_route_assign_driver`

## Smoke test Clientes y Rutas

Script:

- `database/011_customer_route_smoke_tests.sql`

Casos cubiertos:

1. Alta de usuario activo para usar como repartidor.
2. Alta/edicion/estado de clientes.
3. Alta/edicion/estado de rutas.
4. Asignacion de repartidor a ruta.
5. Validacion de traslape de asignaciones.

## SP operativos (Fase D)

Procedimientos agregados:

- `sp_cancel_order`
- `sp_receive_purchase_order`
- `sp_dispatch_order`
- `sp_close_production_order`

## Smoke test Operacion

Script:

- `database/013_operational_smoke_tests.sql`

Casos cubiertos:

1. Cancelacion de pedido en estado permitido.
2. Recepcion de orden de compra con entrada a inventario.
3. Despacho de pedido con salida de inventario de productos.
4. Cierre de orden de produccion cuando no hay items pendientes.

## Vistas de reportes (Fase E)

Script:

- `database/014_reporting_views.sql`

Vistas agregadas:

- `vw_sales_daily`
- `vw_sales_by_customer_daily`
- `vw_top_products_30d`
- `vw_production_daily`
- `vw_purchase_daily`
- `vw_inventory_current_raw`
- `vw_inventory_current_products`
- `vw_inventory_movements_daily`
- `vw_audit_recent`

## Smoke test Reportes

Script:

- `database/015_reporting_smoke_tests.sql`

Casos cubiertos:

1. Ventas diarias y por cliente.
2. Top de productos 30 dias.
3. Produccion diaria.
4. Compras diarias.
5. Estado de inventario actual (materias y productos).
6. Movimientos de inventario diarios.
7. Auditoria reciente.

## SP de recetas

Script:

- `database/016_recipe_procedures.sql`

Procedimientos agregados:

- `sp_recipe_create`
- `sp_recipe_add_item`
- `sp_recipe_remove_item`
- `sp_recipe_publish_version`

## Smoke test Recetas

Script:

- `database/017_recipe_smoke_tests.sql`

Casos cubiertos:

1. Creacion de receta versionada por producto.
2. Alta, edicion (upsert) y eliminacion de items de receta.
3. Publicacion de version activa.

## SP RBAC avanzados

Script:

- `database/018_rbac_procedures.sql`

Procedimientos agregados:

- `sp_role_create`
- `sp_role_update`
- `sp_permission_create`
- `sp_role_set_permissions`

## Smoke test RBAC

Script:

- `database/019_rbac_smoke_tests.sql`

Casos cubiertos:

1. Creacion y edicion de rol.
2. Creacion de permisos.
3. Asignacion masiva de permisos por JSON array.

## Cierre profesional DB

Documentos de control y calidad:

- `database/020_sp_unix_manual.md`
- `database/021_business_rules_coverage_audit.md`
- `database/029_sp_functional_catalog.md`

Contenido:

1. Manual tipo Unix de todos los SP (nombre, entrada, salida, reglas, efectos).
2. Auditoria de cobertura de reglas de negocio, riesgos residuales y pendientes priorizados.

## Estandarizacion de errores y contratos

Scripts:

- `database/022_standardization_baseline.sql`
- `database/023_standardization_contract_views.sql`
- `database/024_standardization_smoke_tests.sql`

Cobertura:

1. Catalogo central de errores (`std_error_catalog`) con dominio, categoria, http_status y retryable.
2. Configuracion central (`std_app_config`) para parametros operativos.
3. Utilidades de consulta (`sp_std_error_lookup`, `sp_std_config_get`) y funcion (`fn_std_error_json`).
4. Vistas de control de contrato de SP (`o_code`, `o_message`, `o_data_json`) y convenciones de naming.

## Guia y plantilla de SP (estilo profesional)

Archivos:

- `database/025_mysql_sp_architecture_standard.md`
- `database/026_mysql_sp_template.sql`

Incluye:

1. Estandar de documentacion tipo bloque tecnico (Proyecto/Autor/Fecha/Comentario/Reglas/Prueba).
2. Arquitectura interna recomendada para MySQL (`EXIT HANDLER`, validaciones, transaccion, auditoria).
3. Contrato de salida unificado y checklist de aceptacion para nuevos SP.
4. Plantilla ejecutable para clonar en nuevos modulos.

## Patron de respuesta de SP

Todos los SP de negocio implementados retornan por `OUT`:

- `o_code`: `1` exito, `-1` error SQL/negocio.
- `o_message`: detalle del resultado.
- Algunos SP retornan IDs generados (`o_order_id`, `o_movement_id`).

SP incluidos:

- `sp_create_order`
- `sp_order_upsert_item`
- `sp_confirm_order`
- `sp_apply_inventory_movement`
- `sp_register_production_result`

## Ejemplos SQL de uso

```sql
CALL sp_create_order(1, 1, NULL, CURRENT_DATE(), NULL, 'pedido test', 1, @o_code, @o_msg, @o_order_id);
SELECT @o_code AS code, @o_msg AS message, @o_order_id AS order_id;

CALL sp_order_upsert_item(@o_order_id, 1, 10.000, 1, @o_code, @o_msg);
SELECT @o_code AS code, @o_msg AS message;

CALL sp_confirm_order(@o_order_id, 1, @o_code, @o_msg);
SELECT @o_code AS code, @o_msg AS message;

CALL sp_apply_inventory_movement(
	1, 'raw_material', 1, 'purchase_in', 25.000, 4.2000,
	'purchase_order', 10, 'entrada inicial', 1,
	@o_code, @o_msg, @o_movement_id
);
SELECT @o_code AS code, @o_msg AS message, @o_movement_id AS movement_id;
```

## Ejemplo Node (mysql2)

```js
const [resultSets] = await db.query(
	'CALL sp_create_order(?, ?, ?, ?, ?, ?, ?, @o_code, @o_msg, @o_order_id)',
	[branchId, customerId, routeId, orderDate, deliveryDate, notes, userId]
);

const [[out]] = await db.query(
	'SELECT @o_code AS code, @o_msg AS message, @o_order_id AS orderId'
);

if (out.code !== 1) {
	throw new Error(out.message);
}

return out;
```

## Seguridad aplicada en el schema

- Modelo RBAC: usuarios, roles, permisos, tablas de union.
- Sesiones seguras: almacenamiento de hash de refresh token.
- Trazabilidad: `audit_logs` + `login_attempts`.
- Integridad de datos: FKs, `CHECK`, `UNIQUE`, `NOT NULL`, indices.
- Soft delete en entidades criticas (`users`, `products`, `raw_materials`, `customers`).
- Campos temporales (`created_at`, `updated_at`) en tablas operativas.

## Seguridad obligatoria en backend (Node)

- Hash de contrasena con Argon2id.
- JWT corto + refresh token rotativo.
- Rate-limit para login y endpoints sensibles.
- Validacion de payload (zod/joi) en todos los endpoints.
- Uso de consultas parametrizadas (ORM o driver seguro).
- Politica de permisos por endpoint (no solo por frontend).
- Auditoria de acciones criticas (usuarios, precios, stock, pedidos, produccion).

## Siguiente migracion sugerida

- `002_seed_reference_data.sql`: sedes iniciales, impuestos base, categorias iniciales.
- `003_create_views_reports.sql`: vistas para reportes operativos.
- `004_create_procedures_inventory.sql`: procedimientos de movimientos de stock atomicos.
