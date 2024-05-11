'''
Helpers for our patroni cluster
===============================
'''


import re


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
    if auth_scope in __pillar__['postgresql'] and option_name in __pillar__['postgresql'][auth_scope]:
        value = __pillar__['postgresql'][auth_scope][option_name]
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
    pg_pillar = __pillar__['postgresql']

    rules = []

    if 'pg_hba' in pg_pillar:
        for identifier, config_data in pg_pillar['pg_hba'].items():
            rules += pg_hba_rules(config_data, 'client')

    patroni_cluster_role = __pillar__['patroni']['cluster_role']
    rules += pg_hba_rules({'mine_target': patroni_cluster_role,  'mine_functions': 'mgmt_ip_addrs'}, 'replication')

    if 'pg_hba_defaults' in pg_pillar:
        for identifier, config_data in pg_pillar['pg_hba_defaults'].items():
            rules += pg_hba_rules(config_data, 'client')

    return rules


def cacert(subpillar):
    cacert = ''
    if 'cacert' in __pillar__[subpillar]:
        cacert = __pillar__[subpillar].cacert
    else:
        if 'local_ca_cert' in __pillar__:
            cacert = __pillar__['local_ca_cert']
    return cacert


def pg_setting_or_default(settings, key, default_pillar_key=None, default_value=None):
    if key in __pillar__['postgresql']['parameters']:
        value = __pillar__['postgresql']['parameters'][key]
    else:
        if default_pillar_key in __pillar__:
            value = __pillar__[default_pillar_key]
        else:
            value = default_value
    if value is not None:
        settings[key] = value


def settings():
    result = {}
    if 'parameters' in __pillar__['postgresql']:
        for parameter, value in __pillar__['postgresql']['parameters'].items():
            result[parameter] = value
    pgbackrest_stanza = __pillar__['pgbackrest']['stanza']
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
