#!py
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

'''
Helpers for our patroni cluster
===============================
'''


import re
import os.path
import ipaddress
from salt.modules.jinja import import_yaml

cached_default_settings = None
cached_pillar_postgresql = None
cached_pillar_pgbackrest = None
cached_pillar_patroni = None
cached_pillar_etcd = None


# def default_settings():
#     global cached_default_settings
#     if cached_default_settings is None:
#         target_path = 'salt://patroni/defaults.sls'
#         cached_default_settings = __salt__['jinja.import_yaml'](target_path)
#     return cached_default_settings

# TODO: in an ideal world we wouldnt want a way to check that the new pillar is not just the defaults
#       then it would also make sense to refactor this out.
def pillar_postgresql(default_settings={}):
    global cached_pillar_postgresql
    if cached_pillar_postgresql is None:
        cached_pillar_postgresql = __salt__['pillar.get']('postgresql', default=default_settings.get('postgresql', {}), merge=True)
    return cached_pillar_postgresql

def pillar_pgbackrest(default_settings={}):
    global cached_pillar_pgbackrest
    if cached_pillar_pgbackrest is None:
        cached_pillar_pgbackrest = __salt__['pillar.get']('pgbackrest', default=default_settings.get('pgbackrest', {}), merge=True)
    return cached_pillar_pgbackrest

def pillar_patroni(default_settings={}):
    global cached_pillar_patroni
    if cached_pillar_patroni is None:
        cached_pillar_patroni = __salt__['pillar.get']('patroni',    default=default_settings.get('patroni', {}),    merge=True)
    return cached_pillar_patroni

def pillar_etcd(default_settings={}):
    global cached_pillar_etcd
    if cached_pillar_etcd is None:
        cached_pillar_etcd = __salt__['pillar.get']('etcd',       default=default_settings.get('etcd', {}),       merge=True)
    return cached_pillar_etcd

def pg_hba_rules(pillar_postgresql, config_data, auth_scope):
    rules = []
    if 'mine_target' in config_data and 'mine_functions' in config_data:
        host_addresses = __salt__['mine.get'](config_data['mine_target'], config_data['mine_functions'], tgt_type='compound')
        for minion_id, data in host_addresses.items():
            if not isinstance(data, list):
                data = [data]
            for address in data:
                config_data['address'] = address
                rules.append(pg_hba_single_rule(pillar_postgresql, config_data, auth_scope))
    else:
        rules.append(pg_hba_single_rule(pillar_postgresql, config_data, auth_scope))
    return rules


def pg_hba_fetch_value_or_default(pillar_postgresql, config_data, auth_scope, option_name, default=None):
    if auth_scope in pillar_postgresql and option_name in pillar_postgresql[auth_scope]:
        value = pillar_postgresql[auth_scope][option_name]
    else:
        value = default
    if option_name in config_data:
        value = config_data[option_name]
    if value is None:
        value = ''
    if option_name == "address":
        value = add_missing_netmask(value)
    if isinstance(value, list):
        value = ",".join(value)
    return value


def add_missing_netmask(value):
    if isinstance(value, str):
        value = re.sub(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$', r'\1/32', value)
        value = re.sub(r'^([0-9a-fA-F:]+)$', r'\1/128', value)
    return value


def pg_hba_single_rule(pillar_postgresql, config_data, auth_scope):
    rule_elements = []
    rule_elements.append(pg_hba_fetch_value_or_default(pillar_postgresql, config_data, auth_scope, 'auth_type', 'hostssl'))
    rule_elements.append(pg_hba_fetch_value_or_default(pillar_postgresql, config_data, auth_scope, 'databases', 'nonexistant-db-check-your-pillar'))
    rule_elements.append(pg_hba_fetch_value_or_default(pillar_postgresql, config_data, auth_scope, 'user', 'nonexistant-user-check-your-pillar'))
    rule_elements.append(pg_hba_fetch_value_or_default(pillar_postgresql, config_data, auth_scope, 'address'))
    rule_elements.append(pg_hba_fetch_value_or_default(pillar_postgresql, config_data, auth_scope, 'auth_method', 'scram-sha-256 clientcert=verify-full'))
    return '    '.join(rule_elements)


def rules(pillar_postgresql):
    pg_pillar = pillar_postgresql

    rules = []

    if 'pg_hba' in pg_pillar:
        for identifier, config_data in pg_pillar['pg_hba'].items():
            rules += pg_hba_rules(pillar_postgresql, config_data, 'client')

    patroni_cluster_role = pillar_patroni()['patroni_cluster_role']
    patroni_cluster_function = pillar_patroni()['patroni_cluster_mine_function']
    rules += pg_hba_rules(pillar_postgresql, {'mine_target': patroni_cluster_role,  'mine_functions': patroni_cluster_function}, 'replication')

    if 'pg_hba_defaults' in pg_pillar:
        for identifier, config_data in pg_pillar['pg_hba_defaults'].items():
            rules += pg_hba_rules(pillar_postgresql, config_data, 'client')

    return rules

def cacert(subpillar):
    cacert = ''
    pillar_for_cacert = {}
    if subpillar ==  'patroni':
            pillar_for_cacert = pillar_patroni()
    elif subpillar ==  'etcd':
            pillar_for_cacert = pillar_etcd()
    elif subpillar ==  'postgresql':
            pillar_for_cacert = pillar_postgresql()
    elif subpillar ==  'pgbackrest':
            pillar_for_cacert = pillar_pgbackrest()

    if 'ca_cert' in pillar_for_cacert:
        cacert = pillar_for_cacert.get('ca_cert')
    else:
        if 'local_ca_cert' in __pillar__:
            cacert = __pillar__['local_ca_cert']
    return cacert


def pg_setting_or_default(pillar_postgresql, settings, key, default_pillar_key=None, default_value=None):
    if key in pillar_postgresql['parameters']:
        value = pillar_postgresql['parameters'][key]
    else:
        if default_pillar_key in __pillar__:
            value = __pillar__[default_pillar_key]
        else:
            value = default_value
    if value is not None:
        settings[key] = value


def settings(pillar_postgresql, pgbackrest_stanza):
    result = {}
    if 'parameters' in pillar_postgresql:
        for parameter, value in pillar_postgresql['parameters'].items():
            result[parameter] = value
    pg_setting_or_default(pillar_postgresql, result, 'archive_command',          default_value='/usr/bin/pgbackrest --stanza=' + pgbackrest_stanza + ' archive-push "%p"' )
    pg_setting_or_default(pillar_postgresql, result, 'restore_command',          default_value='/usr/bin/pgbackrest --stanza=' + pgbackrest_stanza + ' archive-get %f "%p"' )
    pg_setting_or_default(pillar_postgresql, result, 'ssl_min_protocol_version', default_pillar_key='ssl_minimum_version' )
    pg_setting_or_default(pillar_postgresql, result, 'ssl_max_protocol_version', default_pillar_key='ssl_maximum_version' )
    pg_setting_or_default(pillar_postgresql, result, 'ssl_ciphers',              default_pillar_key='ssl_ciphers' )
    pg_setting_or_default(pillar_postgresql, result, 'ssl_ca_file',              default_pillar_key='local_ca_cert' )
    return result


def get_etcd_url(minion_id, hostname, protocol, port ):
    try:
        if ipaddress.ip_address(hostname).version == 6:
            hostname = f"[{hostname}]" 
    except ValueError:
        pass
    return "{minion_id}={protocol}://{hostname}:{port}".format(minion_id=minion_id, protocol=protocol, hostname=hostname, port=port)


def mine_etcd_cluster_url(selector, key, etcd_protocol="https", etcd_port=2380, tgt_type='compound'):
    join_character = ','
    result_list = []
    for minion_id, data in __salt__['mine.get']( selector, key, tgt_type=tgt_type).items():
        if isinstance(data, list):
            for address in data:
                result_list.append(get_etcd_url(minion_id, address, etcd_protocol, etcd_port))
        else:
            result_list.append(get_etcd_url(minion_id, data, etcd_protocol, etcd_port))
    return join_character.join(result_list)

def password_encryption():
    ret = 'scram-sha-256'
    if 'postgresql' in __pillar__ and 'parameters' in __pillar__['postgresql'] and 'password_encryption' in __pillar__['postgresql']['parameters']:
        ret = __pillar__['postgresql']['parameters']['password_encryption']
    return ret

def expand_pgbackrest_timers(input_settings=[]):
    if len(input_settings) == 0:
        return []
    all_timers = ["full", "diff", "incr"]
    if "all" in input_settings:
        return all_timers
    return [e for e in input_settings if e in all_timers]

def has_systemd_override(service_name):
    return "systemd" in __pillar__ and "overrides" in __pillar__["systemd"] and service_name in __pillar__["systemd"]["overrides"]

def minio_url():
    if "minio_url" in pillar_pgbackrest():
        return pillar_pgbackrest()["minio_url"]

    ret = __grains__['id']

    if "minio_cluster_role" in pillar_pgbackrest() and "minio_cluster_mine_function" in pillar_pgbackrest():
        minio_cluster_role     = pillar_pgbackrest()["minio_cluster_role"]
        minio_cluster_function = pillar_pgbackrest()["minio_cluster_mine_function"]
        mined_data             = __mine__.get(minio_cluster_role, minio_cluster_function, tgt_type='compound')

        for minion_id, minio_host in mine_data.items():
            ret = minio_host
            break

    return f"https://{ret}:9000"