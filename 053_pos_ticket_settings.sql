-- Editable POS ticket settings.
-- Run after:
--   052_customer_neighborhood.sql

USE panaderia_db;

CREATE TABLE IF NOT EXISTS pos_ticket_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  setting_key VARCHAR(60) NOT NULL,
  setting_value_json LONGTEXT NOT NULL,
  updated_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pos_ticket_settings_key (setting_key),
  KEY idx_pos_ticket_settings_updated_by (updated_by),
  CONSTRAINT fk_pos_ticket_settings_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

INSERT INTO pos_ticket_settings (
  setting_key,
  setting_value_json
)
VALUES (
  'order_receipt',
  JSON_OBJECT(
    'businessName', 'PANADERIA',
    'businessSubtitle', '',
    'logoDataUrl', '',
    'showLogo', false,
    'showBranchName', true,
    'showBranchContact', true,
    'showSeller', true,
    'showDeliveryDate', true,
    'customerTitle', 'CLIENTE',
    'detailTitle', 'DETALLE SOLICITADO',
    'policyTitle', 'POLITICA DE CAMBIOS',
    'policyText', 'Se realizan cambios por producto vencido, con moho, mojado o mal moldeado. La vigencia es de 15 dias desde la entrega. El inconveniente debe reportarse como maximo dentro de los 2 dias siguientes al vencimiento y requiere autorizacion del vendedor.',
    'footerText', 'Gracias por su compra',
    'fontScale', 'normal',
    'bodyFontSize', 12,
    'headerFontSize', 24,
    'customerFontSize', 20,
    'customerContactFontSize', 16,
    'productFontSize', 13,
    'quantityFontSize', 20,
    'totalFontSize', 17,
    'showExtraLegend', false,
    'extraLegendTitle', 'LEYENDA ADICIONAL',
    'extraLegendText', ''
  )
)
ON DUPLICATE KEY UPDATE
  setting_value_json = setting_value_json;
