# Catalogo Funcional de Stored Procedures

Este documento describe que hace cada SP del proyecto, agrupado por modulo.

## Convencion de contrato

La mayoria de SP usan el contrato estandar:

- `o_code`: 1 exito, 0 validacion/no encontrado, -1 error SQL.
- `o_message`: mensaje de resultado.
- `o_data_json`: payload JSON de respuesta.

Excepcion historica:

- `sp_create_order` retorna `o_order_id` en lugar de `o_data_json` (compatibilidad legacy).

## Core transaccional

Origen: `database/002_business_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_create_order` | Crea un pedido en estado `draft`, valida referencias (sede, cliente, ruta) y registra auditoria. |
| `sp_order_upsert_item` | Inserta o actualiza un item del pedido, recalcula subtotal/impuestos/total y audita la operacion. |
| `sp_confirm_order` | Confirma un pedido si esta en estado permitido y tiene items. |
| `sp_apply_inventory_movement` | Aplica un movimiento de inventario para materia prima o producto y registra traza. |
| `sp_register_production_result` | Registra resultado de produccion, descuenta insumos por receta y suma stock de producto terminado. |

## IAM autenticacion

Origen: `database/004_auth_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_user_create` | Crea usuario, asigna rol inicial, aplica politicas basicas y registra auditoria. |
| `sp_user_force_password_reset` | Fuerza cambio de contrasena en siguiente inicio de sesion. |
| `sp_auth_login_start` | Prepara datos de validacion para login (estado, hash, intentos fallidos recientes). |
| `sp_auth_login_fail` | Registra intento fallido y bloquea cuenta si supera umbral. |
| `sp_auth_login_success` | Registra login exitoso, crea sesion de refresh token y audita. |
| `sp_auth_refresh_session` | Rota hash de refresh token y renueva expiracion de sesion activa. |
| `sp_auth_logout` | Revoca una sesion puntual. |
| `sp_auth_change_password` | Cambia contrasena de usuario y opcionalmente revoca todas sus sesiones. |
| `sp_permission_list_by_user` | Devuelve roles y permisos efectivos del usuario para autorizacion en backend/frontend. |

## IAM administracion

Origen: `database/006_auth_admin_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_user_update_profile` | Actualiza datos de perfil y estado del usuario, con validaciones y auditoria. |
| `sp_user_assign_roles` | Reemplaza roles del usuario a partir de un arreglo JSON de codigos de rol. |
| `sp_user_set_status` | Cambia estado del usuario y revoca sesiones si pasa a no activo. |
| `sp_auth_logout_all` | Revoca todas las sesiones activas de un usuario. |
| `sp_auth_reset_password_admin` | Restablece contrasena por administrador, con opcion de forzar cambio y revocar sesiones. |

## Catalogos

Origen: `database/008_catalog_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_branch_create` | Crea sede. |
| `sp_branch_update` | Actualiza datos de sede. |
| `sp_tax_rate_create` | Crea tasa de impuesto. |
| `sp_tax_rate_update` | Actualiza tasa de impuesto. |
| `sp_product_category_create` | Crea categoria de producto. |
| `sp_product_category_update` | Actualiza categoria de producto. |
| `sp_raw_material_category_create` | Crea categoria de materia prima. |
| `sp_raw_material_category_update` | Actualiza categoria de materia prima. |
| `sp_supplier_create` | Crea proveedor. |
| `sp_supplier_update` | Actualiza proveedor. |
| `sp_product_create` | Crea producto terminado (SKU, precio, impuestos, minimos). |
| `sp_product_update` | Actualiza producto terminado. |
| `sp_product_set_status` | Activa/inactiva producto terminado. |
| `sp_raw_material_create` | Crea materia prima (SKU, costo, proveedor, categoria). |
| `sp_raw_material_update` | Actualiza materia prima. |
| `sp_raw_material_set_status` | Activa/inactiva materia prima. |

## Clientes y rutas

Origen: `database/010_customer_route_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_customer_create` | Crea cliente con validaciones comerciales (estado, limite, tax id). |
| `sp_customer_update` | Actualiza datos de cliente. |
| `sp_customer_set_status` | Cambia estado de cliente. |
| `sp_route_create` | Crea ruta de reparto. |
| `sp_route_update` | Actualiza ruta. |
| `sp_route_set_status` | Activa/inactiva ruta. |
| `sp_route_assign_driver` | Asigna repartidor a ruta con control de fechas y traslapes. |

## Operacion diaria

Origen: `database/012_operational_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_cancel_order` | Cancela pedido en estados permitidos y audita. |
| `sp_receive_purchase_order` | Marca recepcion de compra y aumenta inventario de materias primas. |
| `sp_dispatch_order` | Despacha pedido y descuenta inventario de productos. |
| `sp_close_production_order` | Cierra orden de produccion cuando no hay pendientes. |

## Recetas

Origen: `database/016_recipe_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_recipe_create` | Crea receta/version para un producto con cantidad de salida. |
| `sp_recipe_add_item` | Agrega o actualiza un insumo de receta (cantidad y merma). |
| `sp_recipe_remove_item` | Elimina insumo de receta. |
| `sp_recipe_publish_version` | Publica version activa de receta tras validaciones. |

## RBAC avanzado

Origen: `database/018_rbac_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_role_create` | Crea rol de seguridad. |
| `sp_role_update` | Actualiza rol de seguridad. |
| `sp_permission_create` | Crea permiso de seguridad. |
| `sp_role_set_permissions` | Reemplaza permisos de un rol desde arreglo JSON de codigos de permiso. |

## Estandarizacion transversal

Origen: `database/022_standardization_baseline.sql`

| SP | Que hace |
|---|---|
| `sp_std_error_lookup` | Consulta un codigo de error estandar y devuelve payload estructurado. |
| `sp_std_config_get` | Consulta una clave de configuracion estandar activa. |

## API de lectura (GET/LIST)

Origen: `database/027_read_procedures.sql`

| SP | Que hace |
|---|---|
| `sp_user_get_by_id` | Devuelve detalle de usuario por id, incluyendo roles. |
| `sp_user_list` | Lista usuarios con filtros por estado/busqueda y paginacion. |
| `sp_branch_list` | Lista sedes (todas o solo activas). |
| `sp_customer_list` | Lista clientes con filtros y paginacion. |
| `sp_route_list` | Lista rutas y conductor vigente para una fecha de referencia. |
| `sp_product_list` | Lista productos con filtros por estado/categoria/busqueda y paginacion. |
| `sp_raw_material_list` | Lista materias primas con filtros por estado/categoria/busqueda y paginacion. |

## Resumen total

Total de SP documentados: 63
