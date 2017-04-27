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

# == Class: subunit_processor::worker
#
define subunit2sql::worker (
  $config_file,
  $db_pass,
  $db_host,
  $db_dialect = 'mysql',
  $db_user = 'subunit2sql',
  $db_port = '3306',
  $db_name = 'subunit2sql',
) {
  $suffix = "-${name}"

  if ! defined(File['/etc/logstash']) {
    file { '/etc/logstash':
      ensure => absent,
    }
  }
  if ! defined(Package['paho-mqtt']) {
    package {'paho-mqtt':
      ensure   => latest,
      provider => openstack_pip,
      require  => Class['pip'],
    }
  }

  if ! defined(User['subunit']) {
    user { 'subunit':
      ensure => present,
      system => true,
    }
  }

  if ! defined(File['/etc/subunit2sql']) {
    file { '/etc/subunit2sql':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0644',
    }
  }

if ! defined(File['/var/log/subunit2sql']) {
    file { '/var/log/subunit2sql':
      ensure  => directory,
      owner   => 'subunit',
      group   => 'subunit',
      mode    => '0644',
      require => User['subunit'],
    }
  }
  if ! defined(File['/etc/subunit2sql/subunit2sql.conf']) {
    file { '/etc/subunit2sql/subunit2sql.conf':
      ensure  => present,
      owner   => 'root',
      group   => 'root',
      mode    => '0555',
      content => template('subunit2sql/subunit2sql.conf.erb'),
      require => File['/etc/subunit2sql'],
    }
  }

  file { "/etc/subunit2sql/jenkins-subunit-worker${suffix}.yaml":
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0555',
    source  => $config_file,
    require => File['/etc/subunit2sql'],
  }

  file { "/etc/init.d/jenkins-subunit-worker${suffix}":
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0555',
    content => template('subunit2sql/jenkins-subunit-worker.init.erb'),
    require => [
      File['/usr/local/bin/subunit-gearman-worker.py'],
      File["/etc/subunit2sql/jenkins-subunit-worker${suffix}.yaml"],
    ],
  }

  service { "jenkins-subunit-worker${suffix}":
    enable     => true,
    hasrestart => true,
    subscribe  => [
      File["/etc/subunit2sql/jenkins-subunit-worker${suffix}.yaml"],
      Package['subunit2sql'],
    ],
    require    => [
      File['/etc/subunit2sql'],
      File["/etc/init.d/jenkins-subunit-worker${suffix}"],
    ],
  }

  include ::logrotate
  logrotate::file { "subunit-worker${suffix}-debug.log":
    log     => "/var/log/subunit2sql/subunit-worker${suffix}-debug.log",
    options => [
      'compress',
      'copytruncate',
      'missingok',
      'rotate 7',
      'daily',
      'notifempty',
    ],
    require => Service["jenkins-subunit-worker${suffix}"],
  }
}
