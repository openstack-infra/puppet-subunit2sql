$content = "gearman-host: logstash.openstack.org
gearman-port: 4730
config: /etc/subunit2sql/subunit2sql.conf
mqtt-host: firehose.openstack.org
mqtt-port: 8883
mqtt-topic: gearman-subunit/localhost
mqtt-user: 'mqtt_user'
mqtt-pass: 'mqtt_pass'
mqtt-ca-certs: /etc/subunit2sql/mqtt-root-CA.pem.crt"

file { '/etc/subunit2sql/subunit-woker.yaml':
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0555',
  content => $content,
}

include 'subunit2sql'

class { 'subunit2sql::server':
  db_host => 'subunit2sql_db_host',
  db_pass => 'subunit2sql_db_pass',
}

subunit2sql::worker { 'A':
  config_file => '/etc/subunit2sql/subunit-woker.yaml',
  db_host     => $subunit2sql_db_host,
  db_pass     => $subunit2sql_db_pass,
}
