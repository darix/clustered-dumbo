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