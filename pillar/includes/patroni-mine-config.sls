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