# postgresql
{%- set postgresql_locale                 = 'C.UTF-8' %}
{%- set postgresql_version                = 16 %}
{%- set postgresql_instances_dir          = '/srv/patroni/' %}
{%- set postgresql_data_directory         = postgresql_instances_dir ~ postgresql_version ~ '/data' %}

{%- set postgresql_password_encryption    = 'scram-sha-256' %}
{%- set postgresql_auth_method            = postgresql_password_encryption ~ ' clientcert=verify-full' %}

{%- set postgresql_use_synchronous_commit = false %}

{%- set patroni_dcs = 'etcd' %}

{%- set server_cert_filename = "/etc/step/certs/generic.host.full.pem" %}
{%- set client_cert_filename = "/etc/step/certs/generic.user.full.pem" %}


etcd:
  server_cert:   {{ server_cert_filename }}
  client_cert:   {{ client_cert_filename }}

patroni:
  initialize_cluster: false
  use_synchronous_commit: {{ postgresql_use_synchronous_commit }}
  config:
    cert: {{ server_cert_filename }}
    dcs: {{ patroni_dcs }}
    use_synchronous_commit: {{ postgresql_use_synchronous_commit }}

pgbackrest:
  config:
    global:
      process-max:          4
      compress-type:        zst
      log-level-file:       detail
      # 2 fullbacks are kept
      repo1-retention-full: 2
      repo-cipher-type:     aes-256-cbc
      #
      repo1-type:           s3
      # this is important otherwise stanza-create works but info doesnt
      # https://github.com/pgbackrest/pgbackrest/issues/1576
      # repo configuation
      # path on the remote
      repo1-path:           /
      repo1-s3-uri-style:   path
      # needs to be calculated in the
      # needs to match the region you configured in minio or your S3 backend
      repo1-s3-bucket:      pgbackrest

postgresql:
  version: {{ postgresql_version }}
  instancesdir: {{ postgresql_instances_dir }}
  data_directory: {{ postgresql_data_directory }}
  locale: {{ postgresql_locale }}
  # example for "needs client cert and password"
  client:
    auth_method: {{ postgresql_auth_method }}
  replication:
    user: replicator
    auth_method: {{ postgresql_auth_method }}
    databases: replication
  # cert auth only
  # replication_auth: cert
  # scram passwords only
  # replication_auth: scram-sha-256
  # scram passwords with client certificate
  # replication_auth: scram-sha-256 clientcert=verify-full
  # example for "needs client cert and password"
  authentication:
    # we do not list certificates here as we have a pattern for the certname
    replication:
      username: replicator
      password: supersecure
    superuser:
      username: postgres
      password: supersecure
    rewind:  # Has no effect on postgres 10 and lower
      username: rewind_user
      password: supersecure
  parameters:
    password_encryption: {{ postgresql_password_encryption }}
    archive_mode: on
    log_timezone: 'UTC'
    timezone: 'UTC'
    lc_messages: '{{ postgresql_locale }}'
    lc_monetary: '{{ postgresql_locale }}'
    lc_numeric: '{{ postgresql_locale }}'
    lc_time: '{{ postgresql_locale }}'
    #
    ssl: "on"
    ssl_cert_file: {{ server_cert_filename }}
    ssl_key_file: {{ server_cert_filename }}
    ssl_dh_params_file: {{ server_cert_filename }}
  pg_hba_defaults:
    # replication user for local access with password
    replication_local_password_access:
      auth_type: local
      databases: replication
      user: replicator
      address:
      auth_method: {{ postgresql_password_encryption }}
    # allow the PG user to login with sudo -u -i postgres psql
    postgresql_local_acccess_via_ident:
      auth_type: local
      databases: all
      user: postgres
      address:
      auth_method: ident