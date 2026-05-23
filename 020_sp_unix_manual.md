# SP Manual (Unix Style)

Objetivo: documentar todos los procedimientos almacenados con formato profesional tipo Unix para operacion, soporte y auditoria.

Convenciones:

- `o_code`: `1` exito, `0` validacion negocio, `-1` error tecnico SQL.
- `o_message`: mensaje legible para backend y soporte.
- `o_data_json`: datos de salida estructurados.

## 1) Auth Core (004_auth_procedures.sql)

### sp_user_create
- NAME: crear usuario interno.
- SYNOPSIS: alta de usuario + asignacion de rol inicial.
- INPUT: username, email, password_hash, algo, full_name, phone, role_code, flags.
- OUTPUT: user_id y datos base.
- RULES: username/email unicos, rol existente, validaciones minimas.
- SIDE EFFECTS: inserta en users, user_roles, audit_logs.

### sp_user_force_password_reset
- NAME: forzar cambio de clave.
- SYNOPSIS: activa must_change_password.
- INPUT: user_id, actor.
- OUTPUT: confirmacion.
- RULES: usuario existente.
- SIDE EFFECTS: update users, audit.

### sp_auth_login_start
- NAME: iniciar login.
- SYNOPSIS: obtiene datos de validacion de cuenta para backend.
- INPUT: identifier (username/email).
- OUTPUT: user_id, hash, flags de cuenta, intentos recientes.
- RULES: cuenta activa, no eliminada.
- SIDE EFFECTS: none.

### sp_auth_login_fail
- NAME: registrar fallo de login.
- SYNOPSIS: persiste intento fallido y bloquea por umbral.
- INPUT: identifier, user_id opcional, ip.
- OUTPUT: intentos ventana y estado bloqueo.
- RULES: bloqueo por intentos en ventana temporal.
- SIDE EFFECTS: login_attempts, users(status blocked), audit.

### sp_auth_login_success
- NAME: registrar login exitoso.
- SYNOPSIS: registra exito y abre sesion de refresh token.
- INPUT: user_id, identifier, refresh_hash, user_agent, ip, expires_at.
- OUTPUT: session_id y flags.
- RULES: cuenta activa.
- SIDE EFFECTS: login_attempts(success), users(last_login), user_sessions, audit.

### sp_auth_refresh_session
- NAME: rotar refresh token.
- SYNOPSIS: reemplaza hash y extiende expiracion.
- INPUT: session_id, user_id, current_hash, new_hash, new_expires_at.
- OUTPUT: session_id y nueva expiracion.
- RULES: sesion vigente, no revocada, hash coincidente.
- SIDE EFFECTS: update user_sessions, audit.

### sp_auth_logout
- NAME: cerrar sesion actual.
- SYNOPSIS: revoca sesion puntual.
- INPUT: session_id, user_id.
- OUTPUT: estado revocado.
- RULES: sesion activa existente.
- SIDE EFFECTS: update user_sessions.revoked_at, audit.

### sp_auth_change_password
- NAME: cambiar clave autenticada.
- SYNOPSIS: reemplaza hash, limpia must_change_password, opcional revoca sesiones.
- INPUT: user_id, expected_hash opcional, new_hash, algo, revoke_all.
- OUTPUT: sesiones revocadas.
- RULES: usuario existe, hash nuevo valido, hash actual opcionalmente consistente.
- SIDE EFFECTS: update users, update user_sessions opcional, audit.

### sp_permission_list_by_user
- NAME: listar permisos efectivos.
- SYNOPSIS: devuelve roles y permisos agregados por usuario.
- INPUT: user_id.
- OUTPUT: roles[] y permissions[] en JSON.
- RULES: usuario existente.
- SIDE EFFECTS: none.

## 2) Business Core (002_business_procedures.sql)

### sp_create_order
- NAME: crear pedido.
- SYNOPSIS: alta pedido en borrador.
- INPUT: branch, customer, route opcional, fechas, notas, actor.
- OUTPUT: order_id.
- RULES: sede/cliente/ruta validos y activos.
- SIDE EFFECTS: insert orders, audit.

### sp_order_upsert_item
- NAME: agregar/editar item pedido.
- SYNOPSIS: upsert por (order, product) y recalculo de totales.
- INPUT: order_id, product_id, quantity, actor.
- OUTPUT: confirmacion.
- RULES: pedido editable, producto e impuesto validos, cantidad > 0.
- SIDE EFFECTS: upsert order_items, recalculo orders, audit.

### sp_confirm_order
- NAME: confirmar pedido.
- SYNOPSIS: cambia estado draft -> confirmed.
- INPUT: order_id, actor.
- OUTPUT: confirmacion.
- RULES: estado draft, pedido con items.
- SIDE EFFECTS: update orders, audit.

### sp_apply_inventory_movement
- NAME: aplicar movimiento inventario atomico.
- SYNOPSIS: ajusta stock (materia/producto) + registra movimiento.
- INPUT: branch, item_type, item_id, movement_type, quantity, costos y referencias.
- OUTPUT: movement_id.
- RULES: item valido, cantidad > 0, no stock negativo en salidas.
- SIDE EFFECTS: update stock_raw/materials or stock_products, insert inventory_movements, audit.

### sp_register_production_result
- NAME: registrar produccion real.
- SYNOPSIS: consume materias por receta y acredita producto terminado.
- INPUT: branch, product, recipe, produced_qty, actor, referencia.
- OUTPUT: confirmacion.
- RULES: receta activa del producto, stock suficiente de materias, qty > 0.
- SIDE EFFECTS: update stock materias/producto, insert inventory_movements, audit.

## 3) IAM Admin (006_auth_admin_procedures.sql)

### sp_user_update_profile
- NAME: actualizar perfil usuario.
- SYNOPSIS: edita full_name, email, phone y status.
- RULES: email unico, status valido.
- SIDE EFFECTS: update users, audit.

### sp_user_assign_roles
- NAME: reasignar roles usuario.
- SYNOPSIS: reemplaza set completo de roles desde JSON array.
- RULES: usuario existente, roles existentes, array no vacio.
- SIDE EFFECTS: delete/insert user_roles, audit.

### sp_user_set_status
- NAME: cambiar estado usuario.
- SYNOPSIS: active/inactive/blocked.
- RULES: estado valido.
- SIDE EFFECTS: update users, revoca sesiones si no active, audit.

### sp_auth_logout_all
- NAME: cerrar todas las sesiones.
- SYNOPSIS: revoca sesiones activas de un usuario.
- RULES: usuario existente.
- SIDE EFFECTS: update user_sessions, audit.

### sp_auth_reset_password_admin
- NAME: reset admin de clave.
- SYNOPSIS: setea nuevo hash, fuerza cambio opcional, revoca sesiones opcional.
- RULES: target existente, hash nuevo valido.
- SIDE EFFECTS: update users, update sessions opcional, audit.

## 4) Catalogs (008_catalog_procedures.sql)

### sp_branch_create
- NAME: crear sede.
- RULES: code unico, name requerido.
- SIDE EFFECTS: insert branches, audit.

### sp_branch_update
- NAME: editar sede.
- RULES: sede existente.
- SIDE EFFECTS: update branches, audit.

### sp_tax_rate_create
- NAME: crear impuesto.
- RULES: code unico, rate 0..100.
- SIDE EFFECTS: insert tax_rates, audit.

### sp_tax_rate_update
- NAME: editar impuesto.
- RULES: impuesto existe, rate 0..100.
- SIDE EFFECTS: update tax_rates, audit.

### sp_product_category_create
- NAME: crear categoria de producto.
- RULES: nombre unico.
- SIDE EFFECTS: insert product_categories, audit.

### sp_product_category_update
- NAME: editar categoria de producto.
- RULES: categoria existe.
- SIDE EFFECTS: update product_categories, audit.

### sp_raw_material_category_create
- NAME: crear categoria de materia prima.
- RULES: nombre unico.
- SIDE EFFECTS: insert raw_material_categories, audit.

### sp_raw_material_category_update
- NAME: editar categoria de materia prima.
- RULES: categoria existe.
- SIDE EFFECTS: update raw_material_categories, audit.

### sp_supplier_create
- NAME: crear proveedor.
- RULES: status valido, tax_id unico opcional.
- SIDE EFFECTS: insert suppliers, audit.

### sp_supplier_update
- NAME: editar proveedor.
- RULES: proveedor existe, status valido, tax_id no duplicado.
- SIDE EFFECTS: update suppliers, audit.

### sp_product_create
- NAME: crear producto.
- RULES: sku unico, categoria/impuesto validos, precios no negativos.
- SIDE EFFECTS: insert products, audit.

### sp_product_update
- NAME: editar producto.
- RULES: producto existe, categoria/impuesto validos, valores no negativos.
- SIDE EFFECTS: update products, audit.

### sp_product_set_status
- NAME: activar/desactivar producto.
- RULES: producto existe.
- SIDE EFFECTS: update products, audit.

### sp_raw_material_create
- NAME: crear materia prima.
- RULES: sku unico, categoria valida, proveedor valido opcional, costos no negativos.
- SIDE EFFECTS: insert raw_materials, audit.

### sp_raw_material_update
- NAME: editar materia prima.
- RULES: materia existe, categoria/proveedor validos, costos no negativos.
- SIDE EFFECTS: update raw_materials, audit.

### sp_raw_material_set_status
- NAME: activar/desactivar materia prima.
- RULES: materia existe.
- SIDE EFFECTS: update raw_materials, audit.

## 5) Customers & Routes (010_customer_route_procedures.sql)

### sp_customer_create
- NAME: crear cliente.
- RULES: nombre requerido, status valido, credito >= 0, tax_id unico opcional.
- SIDE EFFECTS: insert customers, audit.

### sp_customer_update
- NAME: editar cliente.
- RULES: cliente existe, status valido, credito >= 0, tax_id no duplicado.
- SIDE EFFECTS: update customers, audit.

### sp_customer_set_status
- NAME: activar/inactivar cliente.
- RULES: cliente existe, status valido.
- SIDE EFFECTS: update customers, audit.

### sp_route_create
- NAME: crear ruta.
- RULES: code unico, name requerido.
- SIDE EFFECTS: insert delivery_routes, audit.

### sp_route_update
- NAME: editar ruta.
- RULES: ruta existe.
- SIDE EFFECTS: update delivery_routes, audit.

### sp_route_set_status
- NAME: activar/inactivar ruta.
- RULES: ruta existe.
- SIDE EFFECTS: update delivery_routes, audit.

### sp_route_assign_driver
- NAME: asignar repartidor a ruta.
- RULES: ruta activa, usuario activo, fechas validas, sin traslape.
- SIDE EFFECTS: insert route_drivers, audit.

## 6) Operations (012_operational_procedures.sql)

### sp_cancel_order
- NAME: cancelar pedido.
- RULES: order existe, estados permitidos draft/confirmed.
- SIDE EFFECTS: update orders(status), audit.

### sp_receive_purchase_order
- NAME: recibir compra.
- RULES: purchase order en estado recibible, con items.
- SIDE EFFECTS: stock_raw + inventory_movements + purchase_orders(status received) + audit.

### sp_dispatch_order
- NAME: despachar pedido.
- RULES: estado confirmed/ready, stock suficiente de productos.
- SIDE EFFECTS: descuento stock_products + inventory_movements(sale_out) + orders(status dispatched) + audit.

### sp_close_production_order
- NAME: cerrar orden produccion.
- RULES: no pending items; estado no completed/cancelled.
- SIDE EFFECTS: update production_orders(status completed), audit.

## 7) Recipes (016_recipe_procedures.sql)

### sp_recipe_create
- NAME: crear version de receta por producto.
- RULES: producto activo, output_quantity > 0.
- SIDE EFFECTS: desactiva versiones activas previas del producto, inserta nueva activa, audit.

### sp_recipe_add_item
- NAME: upsert item de receta.
- RULES: receta existe, materia activa, qty > 0, wastage 0..100.
- SIDE EFFECTS: insert/update recipe_items, audit.

### sp_recipe_remove_item
- NAME: eliminar item receta.
- RULES: item existente.
- SIDE EFFECTS: delete recipe_items, audit.

### sp_recipe_publish_version
- NAME: publicar version de receta.
- RULES: receta existe, tiene items.
- SIDE EFFECTS: setea activa la version objetivo y desactiva otras del producto, audit.

## 8) RBAC Advanced (018_rbac_procedures.sql)

### sp_role_create
- NAME: crear rol.
- RULES: code unico, nombre requerido.
- SIDE EFFECTS: insert roles, audit.

### sp_role_update
- NAME: editar rol.
- RULES: rol existente, nombre valido.
- SIDE EFFECTS: update roles, audit.

### sp_permission_create
- NAME: crear permiso.
- RULES: code unico, nombre valido.
- SIDE EFFECTS: insert permissions, audit.

### sp_role_set_permissions
- NAME: reemplazar permisos de rol.
- RULES: rol existe, JSON valido, permisos existentes.
- SIDE EFFECTS: replace role_permissions, audit.

## 9) Error Model (global)

- `o_code = 1`: operacion completada.
- `o_code = 0`: regla de negocio no satisfecha (estado, existencia, validacion).
- `o_code = -1`: fallo tecnico SQL en bloque transaccional.

## 10) Ops Notes

- Recomendado: ejecutar cada SP bajo usuario de app con privilegios minimos.
- Recomendado: usar UTC para backend y DB de forma consistente.
- Recomendado: no exponer `o_message` tecnico completo al cliente final; registrar en backend y mapear a mensajes de UX.
