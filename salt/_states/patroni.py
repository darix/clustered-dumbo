import patroni.ctl
import json
import copy

def listify(string: str) -> List[str]:
    return [line + '\n' for line in string.rstrip('\n').split('\n')]

def postgresql_config_present(name):
  ret = {'name': name, 'result': None, 'changes': {}, 'comment': ""}
  postgresql_parameters = __pillar__.get("postgresql:parameters", {})

  if len(postgresql_parameters) == 0
    ret["result"] = True
    ret["comment"] = "No configuration settings in pillar"
  elif len(postgresql_parameters) > 0:
    patroni_config = patroni.ctl.load_config("/etc/patroni.yml", None)
    dcs = patroni.ctl._get_dcs(config)
    cluster = dcs.get_cluster()

    changed_data = copy.deepcopy(cluster.config.data)
    patroni.ctl.patch_config(changed_data, postgresql_parameters)

    if cluster.config.data == changed_data:
      ret["result"] = True
      ret["comment"] = "Configuration already completely set"
    else
      before_editing = patroni.ctl.format_config_for_editing(cluster.config.data)
      after_editing  = patroni.ctl.format_config_for_editing(changed_data)
      unified_diff   = difflib.unified_diff(listify(before_editing), listify(after_editing))

      if __opts__["test"]:
        ret["comment"] = f"The following diff will be applied:\n{unified_diff}\n"
      else:
        if dcs.set_config_value(json.dumps(changed_data, separators=(',', ':')), cluster.config.version):
          ret["result"] = True
          ret["changes"]["postgresql_config_present"] = unified_diff
        else:
          ret["result"] = False
          ret["comment"] = "Applying the configuration failed, maybe due to concurrent changes."
  return ret