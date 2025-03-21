## those salt mine functions are used throughout the formula.
#  e.g if you want to have your cluster only listen on certain internal IPs you need to provide a salt mine function for that.
#  suse-profile-base has some example function that can be used in https://github.com/darix/suse-base-profile/blob/stable/salt/_modules/filter_interfaces.py
#  to filter ips from certain interfaces
mine_functions:
  fqdn:
    - mine_function: grains.get
    - fqdn
  host:
    - mine_function: grains.get
    - host