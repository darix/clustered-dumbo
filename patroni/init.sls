{%- import_yaml './defaults.sls' as default_settings %}

{%- set own_cluster_ip_address  = salt['mine.get'](grains.id,                    'mgmt_ip_addrs')[grains.id][0]        %}
{%- set cluster_ip_addresses    = salt['mine.get'](pillar.patroni.cluster_role,  'mgmt_ip_addrs', tgt_type='compound') %}
{%- set cluster_hostnames       = salt['mine.get'](pillar.patroni.cluster_role,  'host',          tgt_type='compound') %}
{%- set cluster_fqdns           = salt['mine.get'](pillar.patroni.cluster_role,  'fqdn',          tgt_type='compound') %}
{%- set minio_host              = salt['mine.get'](pillar.pgbackrest.minio_role, 'fqdn',          tgt_type='compound') %}

{%- set etcd_protocol       = 'https' %}
{%- set etcd_client_port    = 2379 %}
{%- set etcd_peer_port      = 2380 %}


{%- set minio_url = 'https://' ~ grains.id ~ ':9000/' %}
{%- set postgresql_port = 5432 %}
{%- if 'port' in pillar.postgresql.parameters %}
{%- set postgresql_port = pillar.postgresql.parameters.port %}
{%- endif %}

{%- set postgresql_cacert = salt['patroni_helpers.cacert']('patroni') %}

postgresql_packages:
  pkg.installed:
    - names:
      - postgresql{{ pillar.postgresql.version }}-server
      - postgresql{{ pillar.postgresql.version }}-contrib
      - postgresql{{ pillar.postgresql.version }}-llvmjit
{%- if "modules" in pillar.postgresql and pillar.postgresql.modules|length > 0 %}
  {%- for module in pillar.postgresql.modules %}
      - postgresql{{ pillar.postgresql.version }}-{{ module }}
  {%- endif %}
{%- endif %}

patroni_cluster_packages:
  pkg.installed:
    - names:
      - {{ pillar.patroni.config.dcs }}
      - patroni

pgbackest_packages:
  pkg.installed:
    - names:
      - pgbackrest

{% if pillar.patroni.config.dcs== 'etcd' -%}
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
    - name: {{ pillar.postgresql.instancesdir }}
    - user: postgres
    - group: postgres
    - mode: '0700'

# # start patroni here
patroni_config:
  file.managed:
    - mode: '0640'
    - user: root
    - group: postgres
    - template: jinja
    - require:
      - pgbackrest_packages
    - names:
      - /etc/patroni.yml:
        - source: salt://{{ slspath }}/files/etc/patroni.yml.j2
    - context:
      postgresql_port: {{ postgresql_port }}
      own_cluster_ip_address: {{ own_cluster_ip_address }}
      etcd_hosts:
        {%- for minion_id, fqdn in cluster_fqdns.items() %}
        - {{ fqdn }}:{{ etcd_client_port }}
        {%- endfor %}
      pg_hba:
        # rules from the pillar
        {%- for rule in salt['patroni_helpers.rules']() %}
        - '{{ rule }}'
        {%- endfor %}
      pg_settings:
        {%- for parameter, value in salt['patroni_helpers.settings']().items() %}
        {{ parameter }}: '{{ value }}'
        {%- endfor %}
        {%- if 'use_synchronous_commit' in pillar.patroni and pillar.patroni.use_synchronous_commit %}
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
      # {%- if 'initialize_cluster' in pillar.patroni and pillar.patroni.initialize_cluster and 'initialize_pgbackrest' in pillar.patroni and pillar.patroni.initialize_pgbackrest %}  # noqa: 204
      #   {%- for stanza_name, stanza_data in pillar.pgbackrest.config.stanzas.items() %}
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
      - patroni_cluster_packages
    - names:
      - /etc/pgbackrest.conf:
        - source: salt://{{ slspath }}/files/etc/pgbackrest.conf.j2
    - context:
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

{%- if 'initialize_cluster' in pillar.patroni and pillar.patroni.initialize_cluster and 'initialize_pgbackrest' in pillar.patroni and pillar.patroni.initialize_pgbackrest %}  # noqa: 204
  {%- for stanza_name, stanza_data in pillar.pgbackrest.config.stanzas.items() %}
pgbackrest_create_stanza_{{ stanza_name }}:
  cmd.run:
    - name: /usr/bin/pgbackrest-init {{ stanza_name }} {{ pillar.postgresql.datadir }}
    - cwd: {{ pillar.postgresql.datadir }}
    - runas: postgres
    - creates: {{ pillar.postgresql.datadir }}/pgbackrest-stanza-created
    - require:
      - patroni_service
      - pgbackrest_config
      - pgbackrest_init_helper
  {%- endfor %}
{%- endif %}
