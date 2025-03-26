#
# clustered-dumbo
#
# Copyright (C) 2025   darix
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# postgresql
{%- set postgresql_locale                 = 'C.UTF-8' %}
{%- set postgresql_version                = pillar.get('postgresql', {}).get('version', 17) %}
{%- set postgresql_instances_dir          = '/srv/patroni/' %}
{%- set postgresql_data_directory         = postgresql_instances_dir ~ postgresql_version ~ '/data' %}

{%- set postgresql_password_encryption    = salt['patroni_helpers.password_encryption']() %}
{%- set postgresql_auth_method            = postgresql_password_encryption ~ ' clientcert=verify-full' %}

{%- set postgresql_use_synchronous_commit = false %}

{%- set patroni_dcs = 'etcd' %}

{%- set server_cert_filename = "/etc/step/certs/generic.host.full.pem" %}
{%- set client_cert_filename = "/etc/step/certs/generic.user.full.pem" %}
{%- set ca_certs_filename    = pillar.step.client_config.ca.root_cert.path %}


etcd:
  server_cert:   {{ server_cert_filename }}
  client_cert:   {{ client_cert_filename }}
  ca_cert:       {{ ca_certs_filename }}

patroni:
  ca_cert:       {{ ca_certs_filename }}
  initialize_cluster: false
  use_synchronous_commit: {{ postgresql_use_synchronous_commit }}
  config:
    cert: {{ server_cert_filename }}
    dcs: {{ patroni_dcs }}
    use_synchronous_commit: {{ postgresql_use_synchronous_commit }}

pgbackrest:
  timers_enabled:
    - all
  ca_cert:       {{ ca_certs_filename }}
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
  ca_cert:       {{ ca_certs_filename }}
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
    ssl_ca_file: {{ ca_certs_filename }}
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
    # for pg_rewind
    rewind_user:
      databases: postgres
      user: rewind_user
      mine_target:    {{ pillar.patroni.cluster_role }}
      mine_functions: {{ pillar.patroni.cluster_mine_function }}