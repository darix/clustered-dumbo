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

step:
  certificates:
    host:
      generic:
        cn: {{ grains.id }}
        san:
          - {{ grains.host }}
          - {{ grains.id }}
          {%- for hostname in grains.fqdns|sort %}
          - {{ hostname }}
          {%- endfor %}
          {%- if "global_addresses" in grains %}
            {%- for ip in grains.global_addresses|sort %}
          - {{ ip }}
            {%- endfor %}
          {%- endif %}
        affected_services:
         - etcd
         - patroni
         - postgresql
        acls_for_combined_file:
          - acl_type: user
            acl_names:
            - etcd
            - nagios
            - postgres
    user:
      generic:
        cn: {{ grains.id }}
        san:
          - {{ grains.host }}
          - {{ grains.id }}
          {%- for hostname in grains.fqdns|sort %}
          - {{ hostname }}
          {%- endfor %}
          {%- if "global_addresses" in grains %}
            {%- for ip in grains.global_addresses|sort %}
          - {{ ip }}
            {%- endfor %}
          {%- endif %}
        affected_services:
         - etcd
         - patroni
         - postgresql
        acls_for_combined_file:
          - acl_type: user
            acl_names:
            - etcd
            - nagios
            - postgres
{%- for pg_user in ['postgres', 'replicator', 'rewind_user', 'patroni'] %}
      'pg.{{ pg_user }}':
        cn: {{ pg_user }}
        san:
          - {{ grains.host }}
          - {{ grains.id }}
          {%- for hostname in grains.fqdns|sort %}
          - {{ hostname }}
          {%- endfor %}
          {%- if "global_addresses" in grains %}
            {%- for ip in grains.global_addresses|sort %}
          - {{ ip }}
            {%- endfor %}
          {%- endif %}
        acls_for_combined_file:
          - acl_type: user
            acl_names:
            - postgres
        affected_services:
         - patroni
         - postgresql
{%- endfor %}

patroni:
  ssl_prefix:   '/etc/step/certs/pg.'
  ssl_suffix:   '.user.full.pem'