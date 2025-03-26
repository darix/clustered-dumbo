systemd:
  overrides:
    {%- for backup_type in ["full", "incr", "diff" ] %}
    pgbackrest-{{ backup_type }}@.service:
      Service:
        - ExecCondition=/usr/bin/postgresql-is-primary
    {%- endfor %}