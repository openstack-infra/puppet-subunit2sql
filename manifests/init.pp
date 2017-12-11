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
class subunit2sql (
) {
  include ::pip

  package {'python-mysqldb':
    ensure => present,
  }

  package {'python-psycopg2':
    ensure => present,
  }

  package {'python-netifaces':
    ensure => present,
  }

  package { 'python-subunit':
    ensure   => latest,
    provider => openstack_pip,
    require  => Class['pip'],
  }

  exec { 'install-subunit2sql-safely':
    command => '/usr/bin/pip install --upgrade --upgrade-strategy=only-if-needed subunit2sql',
    # This checks the current installed subunit2sql version with pip list and
    # the latest version of subunit2sql on pypi with pip search and if they are
    # different then we know we need to upgrade to reconcile the local version
    # with the upstream version.
    #
    # We do this using this check here rather than a pip package resource so we
    # can override pip's default upgrade strategy in order to avoid replacing
    # deps we've preinstalled from system packages because they lack wheels on
    # PyPI and must be otherwise rebuilt from sdist instead (specifically
    # netifaces).
    onlyif  => '/bin/bash -c "test $(/usr/bin/pip list --format columns | sed -ne \'s/^subunit2sql\s\+\(.*\)$/\1/p\') != $(/usr/bin/pip search \'subunit2sql$\' | sed -ne \'s/^subunit2sql (\(.*\)).*$/\1/p\')"',
    require => [
      Class['pip'],
      Package['python-mysqldb'],
      Package['python-psycopg2'],
      Package['python-netifaces']
    ],
  }

  package { 'os-performance-tools':
    ensure   => latest,
    provider => openstack_pip,
    require  => [
      Class['pip']
    ],
  }

  package { 'testtools':
    ensure   => latest,
    provider => openstack_pip,
    require  => Class['pip'],
  }

  if ! defined(Package['python-daemon']) {
    package { 'python-daemon':
      ensure => present,
    }
  }

  if ! defined(Package['python-zmq']) {
    package { 'python-zmq':
      ensure => present,
    }
  }

  if ! defined(Package['python-yaml']) {
    package { 'python-yaml':
      ensure => present,
    }
  }

  if ! defined(Package['gear']) {
    package { 'gear':
      ensure   => latest,
      provider => openstack_pip,
      require  => Class['pip'],
    }
  }

  if ! defined(Package['statsd']) {
    package { 'statsd':
      ensure   => latest,
      provider => openstack_pip,
      require  => Class['pip']
    }
  }

  file { '/usr/local/bin/subunit-gearman-worker.py':
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    source  => 'puppet:///modules/subunit2sql/subunit-gearman-worker.py',
    require => [
      Package['python-daemon'],
      Package['python-zmq'],
      Package['python-yaml'],
      Package['gear'],
      Exec['install-subunit2sql-safely'],
      Package['python-subunit'],
      Package['testtools']
    ],
  }
}
