'''
Helpers for our patroni cluster
===============================
'''


import re
import os.path
from salt.modules.jinja import import_yaml

cached_default_settings = None
cached_pillar_postgresql = None
cached_pillar_pgbackrest = None
cached_pillar_patroni = None
cached_pillar_etcd = None

def default_settings():
    if cached_default_settings is None:
        current_dir = os.path.basename(__file__)
        target_path = current_dir + '/../patroni/defaults.sls'
        cached_default_settings = import_yaml(target_path)
    return cached_default_settings

# TODO: in an ideal world we wouldnt want a way to check that the new pillar is not just the defaults
#       then it would also make sense to refactor this out.
def pillar_postgresql():
    if cached_pillar_postgresql is None:
        cached_pillar_postgresql = __pillar__.get('postgresql', defaults=default_settings().get('postgresql', {}), merge=True)
    return cached_pillar_postgresql

def pillar_pgbackrest():
    if cached_pillar_pgbackrest is None:
        cached_pillar_pgbackrest = __pillar__.get('pgbackrest', defaults=default_settings().get('pgbackrest', {}), merge=True)
    return cached_pillar_pgbackrest

def pillar_patroni():
    if cached_pillar_patroni is None:
        cached_pillar_patroni = __pillar__.get('patroni',    defaults=default_settings().get('patroni', {}),    merge=True)
    return cached_pillar_patroni

def pillar_etcd():
    if cached_pillar_etcd is None:
        cached_pillar_etcd = __pillar__.get('etcd',       defaults=default_settings().get('etcd', {}),       merge=True)
    return cached_pillar_etcd

def pg_hba_rules(config_data, auth_scope):
    rules = []
    if 'mine_target' in config_data and 'mine_functions' in config_data:
        host_addresses = __salt__['mine.get'](config_data['mine_target'], config_data['mine_functions'], tgt_type='compound')
        for minion_id, data in host_addresses.items():
            if not isinstance(data, list):
                data = [data]
            for address in data:
                config_data['address'] = address
                rules.append(pg_hba_single_rule(config_data, auth_scope))
    else:
        rules.append(pg_hba_single_rule(config_data, auth_scope))
    return rules


def pg_hba_fetch_value_or_default(config_data, auth_scope, option_name, default=None):
    pillar_postgresql = pillar_postgresql()
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


def pg_hba_single_rule(config_data, auth_scope):
    rule_elements = []
    rule_elements.append(pg_hba_fetch_value_or_default(config_data, auth_scope, 'auth_type', 'hostssl'))
    rule_elements.append(pg_hba_fetch_value_or_default(config_data, auth_scope, 'databases', 'nonexistant-db-check-your-pillar'))
    rule_elements.append(pg_hba_fetch_value_or_default(config_data, auth_scope, 'user', 'nonexistant-user-check-your-pillar'))
    rule_elements.append(pg_hba_fetch_value_or_default(config_data, auth_scope, 'address'))
    rule_elements.append(pg_hba_fetch_value_or_default(config_data, auth_scope, 'auth_method', 'scram-sha-256 clientcert=verify-full'))
    return '    '.join(rule_elements)


def rules():
    pg_pillar = pillar_postgresql()

    rules = []

    if 'pg_hba' in pg_pillar:
        for identifier, config_data in pg_pillar['pg_hba'].items():
            rules += pg_hba_rules(config_data, 'client')

    patroni_cluster_role = pillar_patroni()['cluster_role']
    rules += pg_hba_rules({'mine_target': patroni_cluster_role,  'mine_functions': 'mgmt_ip_addrs'}, 'replication')

    if 'pg_hba_defaults' in pg_pillar:
        for identifier, config_data in pg_pillar['pg_hba_defaults'].items():
            rules += pg_hba_rules(config_data, 'client')

    return rules

def cacert(subpillar):
    cacert = ''
    pillar_for_cacert = {}
    match subpillar:
        case 'patroni':
            pillar_for_cacert = pillar_patroni()
        case 'etcd':
            pillar_for_cacert = pillar_etcd()
        case 'postgresql':
            pillar_for_cacert = pillar_postgresql()
        case 'pgbackrest':
            pillar_for_cacert = pillar_pgbackrest()

    if 'cacert' in pillar_for_cacert:
        cacert = pillar_for_cacert.cacert
    else:
        if 'local_ca_cert' in __pillar__:
            cacert = __pillar__['local_ca_cert']
    return cacert


def pg_setting_or_default(settings, key, default_pillar_key=None, default_value=None):
    if key in pillar_postgresql()['parameters']:
        value = pillar_postgresql()['parameters'][key]
    else:
        if default_pillar_key in __pillar__:
            value = __pillar__[default_pillar_key]
        else:
            value = default_value
    if value is not None:
        settings[key] = value


def settings():
    result = {}
    if 'parameters' in pillar_postgresql():
        for parameter, value in pillar_postgresql()['parameters'].items():
            result[parameter] = value
    pgbackrest_stanza = pillar_pgbackrest()['stanza']
    pg_setting_or_default(result, 'archive_command',          default_value='/usr/bin/pgbackrest --stanza=' + pgbackrest_stanza + ' archive-push "%p"' )
    pg_setting_or_default(result, 'restore_command',          default_value='/usr/bin/pgbackrest --stanza=' + pgbackrest_stanza + ' archive-get %f "%p"' )
    pg_setting_or_default(result, 'ssl_min_protocol_version', default_pillar_key='ssl_minimum_version' )
    pg_setting_or_default(result, 'ssl_max_protocol_version', default_pillar_key='ssl_maximum_version' )
    pg_setting_or_default(result, 'ssl_ciphers',              default_pillar_key='ssl_ciphers' )
    pg_setting_or_default(result, 'ssl_ca_file',              default_pillar_key='local_ca_cert' )
    return result


def get_etcd_url(minion_id, hostname, protocol, port ):
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
