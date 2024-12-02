{%- import_yaml './defaults.sls' as default_settings %}

{%- set pillar_postgresql = salt['patroni_helpers.pillar_postgresql'](default_settings=default_settings) %}
{%- set pillar_pgbackrest = salt['patroni_helpers.pillar_pgbackrest'](default_settings=default_settings) %}
{%- set pillar_patroni    = salt['patroni_helpers.pillar_patroni'](default_settings=default_settings) %}
{%- set pillar_etcd       = salt['patroni_helpers.pillar_etcd'](default_settings=default_settings) %}

{%- set own_cluster_ip_address  = salt['mine.get'](grains.id,                    'mgmt_ip_addrs')[grains.id][0]        %}
{%- set cluster_ip_addresses    = salt['mine.get'](pillar_patroni.cluster_role,  'mgmt_ip_addrs', tgt_type='compound') %}
{%- set cluster_hostnames       = salt['mine.get'](pillar_patroni.cluster_role,  'host',          tgt_type='compound') %}
{%- set cluster_fqdns           = salt['mine.get'](pillar_patroni.cluster_role,  'fqdn',          tgt_type='compound') %}
{%- set minio_host              = salt['mine.get'](pillar_pgbackrest.minio_role, 'fqdn',          tgt_type='compound') %}

{%- set etcd_protocol       = 'https' %}
{%- set etcd_client_port    = 2379 %}
{%- set etcd_peer_port      = 2380 %}


{%- set minio_url = 'https://' ~ grains.id ~ ':9000/' %}
{%- set postgresql_port = 5432 %}
{%- if 'port' in pillar_postgresql.parameters %}
{%- set postgresql_port = pillar_postgresql.parameters.port %}
{%- endif %}
{%- set postgresql_data_directory = pillar_postgresql.data_directory %}

postgresql_packages:
  pkg.installed:
    - names:
      - postgresql{{ pillar_postgresql.version }}-server
      - postgresql{{ pillar_postgresql.version }}-contrib
      {%- if grains.osfullname in ['openSUSE Tumbleweed', 'Leap'] %}
      - postgresql{{ pillar_postgresql.version }}-llvmjit
      {%- endif %}
{%- if "modules" in pillar_postgresql and pillar_postgresql.modules|length > 0 %}
  {%- for module in pillar_postgresql.modules %}
      - postgresql{{ pillar_postgresql.version }}-{{ module }}
  {%- endfor %}
{%- endif %}

patroni_cluster_packages:
  pkg.installed:
    - names:
      - {{ pillar_patroni.config.dcs }}
      - patroni

pgbackrest_packages:
  pkg.installed:
    - names:
      - pgbackrest

{% if pillar_patroni.config.dcs== 'etcd' -%}
sysconfig_etcd:
  file.managed:
    - makedirs: true
    - mode: '0644'
    - user: root
    - group: root
    - template: jinja
    - require:
      - patroni_cluster_packages
    - names:
      - /etc/sysconfig/etcd:
        - source: salt://{{ slspath }}/files/etc/sysconfig/etcd.j2
    - context:
      pillar_etcd: {{ pillar_etcd }}
      patroni_cluster_role: {{ pillar_patroni.cluster_role }}
      own_ip:              {{ own_cluster_ip_address }}
      etcd_protocol:       {{ etcd_protocol }}
      etcd_client_port:    {{ etcd_client_port }}
      etcd_peer_port:      {{ etcd_peer_port }}

etcd_service:
  service.running:
    - name: etcd.service
    - enable: true
    - watch:
      - sysconfig_etcd
    - require:
      - sysconfig_etcd
{%- endif %}

postgresql_instances_dir:
  file.directory:
    - name: {{ pillar_postgresql.instancesdir }}
    - user: postgres
    - group: postgres
    - mode: '0700'
    - require:
      - postgresql_packages

{%- set sysconfig_setting = "POSTGRES_DATADIR" %}
sysconfig_postgresql_datadir:
  file.replace:
    - require:
      - postgresql_packages
    - name: /etc/sysconfig/postgresql
    - pattern: "^{{ sysconfig_setting }} *=.*"
    - repl: {{ sysconfig_setting }}="{{ postgresql_data_directory }}"
    - append_if_not_found: True

# # start patroni here
patroni_config:
  file.managed:
    - mode: '0640'
    - user: root
    - group: postgres
    - template: jinja
    - require:
      - pgbackrest_config
      - sysconfig_postgresql_datadir
    - names:
      - /etc/patroni.yml:
        - source: salt://{{ slspath }}/files/etc/patroni.yml.j2
    - context:
      pillar_postgresql: {{ pillar_postgresql }}
      pillar_patroni:    {{ pillar_patroni }}
      pgbackrest_stanza: {{ pillar_pgbackrest.stanza }}
      postgresql_locale: {{ pillar_postgresql.get('locale', 'C.UTF-8') }}
      postgresql_password_encryption: {{ pillar_postgresql.get('parameters:password_encryption', 'scram-sha-256') }}
      postgresql_port: {{ postgresql_port }}
      own_cluster_ip_address: {{ own_cluster_ip_address }}
      # TODO: this code needs error handling it happily sets None as value
      etcd_hosts:
        {%- for minion_id, fqdn in cluster_fqdns.items() %}
        - {{ fqdn }}:{{ etcd_client_port }}
        {%- endfor %}
      pg_hba:
        # rules from the pillar
        {%- for rule in salt['patroni_helpers.rules'](pillar_postgresql=pillar_postgresql) %}
        - '{{ rule }}'
        {%- endfor %}
      pg_settings:
        {%- for parameter, value in salt['patroni_helpers.settings'](pillar_postgresql=pillar_postgresql, pgbackrest_stanza=pillar_pgbackrest.stanza).items() %}
        {{ parameter }}: '{{ value }}'
        {%- endfor %}
        {%- if 'use_synchronous_commit' in pillar_patroni and pillar_patroni.use_synchronous_commit %}
        synchronous_commit: 'on'
        synchronous_standby_names: '{{ cluster_fqdns | join(', ') }}'
        {%- endif %}

patroni_service:
  service.running:
    - name: patroni.service
    - enable: true
    - watch:
      - patroni_config
    - require:
      - patroni_config
      - pgbackrest_config
      #
      # {%- if 'initialize_cluster' in pillar_patroni and pillar_patroni.initialize_cluster and 'initialize_pgbackrest' in pillar_patroni and pillar_patroni.initialize_pgbackrest %}  # noqa: 204
      #   {%- for stanza_name, stanza_data in pillar_pgbackrest.config.stanzas.items() %}
      # - pgbackrest_create_stanza_{{ stanza_name }}:
      #   {%- endfor %}
      # {%- endif %}

pgbackrest_config:
  file.managed:
    - mode: '0640'
    - user: root
    - group: postgres
    - template: jinja
    - require:
      - pgbackrest_packages
    - names:
      - /etc/pgbackrest.conf:
        - source: salt://{{ slspath }}/files/etc/pgbackrest.conf.j2
    - context:
      pillar_pgbackrest: {{ pillar_pgbackrest }}
      postgresql_data_directory: {{ postgresql_data_directory }}
      postgresql_port: {{ postgresql_port }}
      minio_url: {{ minio_url }}

pgbackrest_init_helper:
  file.managed:
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - pgbackrest_config
    - names:
      - /usr/bin/pgbackrest-init:
        - source: salt://{{ slspath }}/files/usr/bin/pgbackrest-init

{%- if 'initialize_cluster' in pillar_patroni and pillar_patroni.initialize_cluster and 'initialize_pgbackrest' in pillar_patroni and pillar_patroni.initialize_pgbackrest %}  # noqa: 204
  {%- for stanza_name, stanza_data in pillar_pgbackrest.config.stanzas.items() %}
pgbackrest_create_stanza_{{ stanza_name }}:
  cmd.run:
    - name: /usr/bin/pgbackrest-init {{ stanza_name }} {{ pillar_postgresql.data_directory }}
    - cwd: {{ pillar_postgresql.data_directory }}
    - runas: postgres
    - creates: {{ pillar_postgresql.data_directory }}/pgbackrest-stanza-created
    - require:
      - patroni_service
      - pgbackrest_init_helper
  {%- endfor %}
{%- endif %}
