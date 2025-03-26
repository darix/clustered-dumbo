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

{%- set cluster_role            = 'I@role:patroni' %}
{%- set minio_role              = 'I@role:minio'   %}

# patroni
{%- set patroni_scope     = "cluster1" %}
{%- set patroni_namespace = "patroni" %}

# pgbackrest
{%- set pgbackrest_stanza = patroni_scope ~ '-' ~ patroni_namespace %}

{%- set location       = "eu-west-1" %}
{%- set bucket_name    = "pgbackrest-patroni-pg" %}
{%- set minio_user     = "pgbackrest_patroni_pg" %}
{%- set password_key   = "patroni-minio/" ~ minio_user ~ "/password"   %}
{%- set access_key     = "patroni-minio/" ~ minio_user ~ "/access_key" %}
{%- set secret_key     = "patroni-minio/" ~ minio_user ~ "/secret_key" %}
{%- set encryption_key = "patroni-minio/" ~ minio_user ~ "/encryption_key" %}

etcd:
  bootstrap: false
  cluster_name: {{ pgbackrest_stanza }}

patroni:
  # start a new node - unless initialize_cluster is also true it requires existing hosts/a backup to pull from
  bootstrap: false
  # if you want to set up a new cluster fully from scratch
  initialize_cluster: false
  cluster_role: {{ cluster_role }}
  cluster_mine_function: 'ipaddr'
  config:
    scope: {{ pgbackrest_stanza }}
    namespace: {{ patroni_namespace }}
    restapi:
      username: patroni-admin
      password: {{ "patroni-admin" | gopass }}

pgbackrest:
  minio_role: {{ minio_role }}
  stanza: {{ pgbackrest_stanza }}
  config:
    global:
      # encrypt the backup
      repo1-s3-region:      {{ location }}
      repo1-s3-bucket:      {{ bucket_name }}
      repo-cipher-pass:     {{ encryption_key | gopass }}
      # auth data
      repo1-s3-key:         {{ access_key | gopass }}
      repo1-s3-key-secret:  {{ secret_key | gopass }}
    stanzas:
      {{ pgbackrest_stanza }}:
        enable: True
        use_standby_for_backup: False

postgresql:
  authentication:
    replication:
      password: {{ "patroni/replication" | gopass }}
    superuser:
      password: {{ "patroni/superuser" | gopass }}
    rewind:
      password: {{ "patroni/rewind" | gopass }}