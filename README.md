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
```
## cfgmgmt-template integration

if you are using our [cfgmgmt-template](https://github.com/darix/cfgmgmt-template) as a starting point the saltmaster you can simplify the setup with:

```
git submodule add https://github.com/darix/clustered-dumbo formulas/clustered-dumbo
ln -s /srv/cfgmgmt/formulas/clustered-dumbo/config/enable_clustered_dumbo.conf /etc/salt/master.d/
systemctl restart saltmaster
```

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)