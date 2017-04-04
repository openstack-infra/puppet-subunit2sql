# Copyright 2012-2013 Hewlett-Packard Development Company, L.P.
# Copyright 2013 OpenStack Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# == Class: subunit2sql
#
class subunit2sql::server (
  $db_pass,
  $db_host,
  $db_dialect = 'mysql',
  $db_user = 'subunit2sql',
  $db_port = '3306',
  $db_name = 'subunit2sql',
  $expire_age = '186',
  $expire_cron_minute = '0',
  $expire_cron_hour = '3',
  $expire_cron_weekday = '7',
) {

  file { '/etc/subunit2sql.conf':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0555',
    content => template('subunit2sql/subunit2sql.conf.erb'),
  }

  file {'/etc/subunit2sql-my.cnf':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0400',
    content => template('subunit2sql/subunit2sql-my.cnf.erb'),
  }

  file {'/usr/local/bin/run_migrations.sh':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0555',
    source  => 'puppet:///modules/subunit2sql/run_migrations.sh',
    require => File['/etc/subunit2sql.conf']
  }

  exec { 'upgrade_subunit2sql_db':
    command     => '/usr/local/bin/run_migrations.sh',
    require     => File['/usr/local/bin/run_migrations.sh'],
    subscribe   => Package['subunit2sql'],
    refreshonly => true,
    timeout     => 0,
  }

  cron { 'subunit2sql-prune':
    ensure      => present,
    command     => "subunit2sql-db-manage --config-file /etc/subunit2sql.conf expire --expire-age ${expire_age} >> /var/log/subunit2sql_migration.log 2>&1 & ",
    minute      => $expire_cron_minute,
    hour        => $expire_cron_hour,
    weekday     => $expire_cron_weekday,
    environment => 'PATH=/usr/local/bin:/usr/bin:/bin/',
  }
}
