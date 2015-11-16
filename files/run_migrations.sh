#!/usr/bin/env bash

(time subunit2sql-db-manage --config-file /etc/subunit2sql.conf upgrade head) > /var/log/subunit2sql_migration.log 2>&1 &
