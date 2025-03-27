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

{%- import_yaml './defaults.sls' as default_settings %}

{%- set pillar_etcd            = salt['patroni_helpers.pillar_etcd'](default_settings=default_settings) %}


etcd_cluster_packages:
  pkg.installed:
    - pkgs:
      - etcdutl: '>= 3.5.17'
      - etcdctl: '>= 3.5.17'
      - etcd:    '>= 3.5.17'

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
      - /etc/default/etcd:
        - source: salt://{{ slspath }}/files/etc/default/etcd.j2
    - context:
      pillar_etcd:                {{ pillar_etcd }}

etcd_service:
  service.running:
    - name: etcd.service
    - enable: true
    - watch:
      - sysconfig_etcd
    - require:
      - sysconfig_etcd