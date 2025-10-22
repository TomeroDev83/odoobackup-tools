-- Copyright 2025 TomeroDev83
-- Licensed under the Apache License, Version 2.0
-- http://www.apache.org/licenses/LICENSE-2.0

-- Deactivate crons
UPDATE ir_cron SET active=FALSE;

-- Deactivate email servers
UPDATE ir_mail_server SET active=FALSE;
UPDATE fetchmail_server SET active=FALSE;

-- Reset UUID for DB
UPDATE ir_config_parameter SET value=(SELECT gen_random_uuid()) WHERE key='database.uuid';
UPDATE ir_config_parameter SET value=(SELECT gen_random_uuid()) WHERE key='database.secret';
