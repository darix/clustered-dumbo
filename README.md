# Salt Formula for patroni

## What can the formula do?

## installation

## Required salt master config:

```
file_roots:
  base:
    - {{ salt_base_dir }}/salt
    - {{ formulas_base_dir }}/opensuse-patroni/salt

pillar_roots:
  base:
    - {{ salt_base_dir }}/pillar/
    - {{ formulas_base_dir }}/opensuse-patroni/pillar/
## License

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)