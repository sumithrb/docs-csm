#!/usr/bin/env bash
#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#

SHORT=p:,s:,c:,f:,help
LONG=peers:,servers:,cidrs:,from_file:,help
OPTS=$(getopt --alternative --name ntp --options $SHORT --longoptions $LONG -- "$@")

help() {
  echo "Usage: ntp-csi-input.sh \\
             [ -p | --peers ]
             [ -s | --servers ]
             [ -c | --cidrs ]
             [ -f | --from_file ]
             [ -h | --help  ]

Example: ./ntp-csi-input.sh --peers ncn-w001,ncn-w002,ncn-w003,ncn-s001 \\
                            --servers ncn-m001,lumintp.csc.fi \\
                            --cidrs 10.120.0.0/14,10.106.0.0/17,10.252.0.0/17

Example: ./ntp-csi-input.sh --from_file my_config

# my_config example
servers=(
ntp-server-1
ntp-server-2
)
cidrs=(
10.120.0.0/14
10.106.0.0/17
10.252.0.0/17
)
peers=(
ncn-m001
ncn-m002
ncn-w001
)
"
  exit 2
}

NTP_TEMPLATE='
{
    "user-data": {
        "ntp": {
            "allow": [],
            "config": {
                "confpath": "/etc/chrony.d/cray.conf",
                "template": ""
            },
            "enabled": true,
            "ntp_client": "chrony",
            "peers": [],
            "pools": [],
            "servers": []
        }
    }
}
'

JINJA_FILTER='
## template: jinja
# csm-generated config.  Do not modify--changes can be overwritten
{% for pool in pools | sort -%}
    {% if local_hostname == ncn-m001 and pool == ncn-m001 %}
    {% endif %}
    {% if local_hostname != ncn-m001 and pool != ncn-m001 %}
    {% else %}
        pool {{ pool }} iburst
    {% endif %}
{% endfor %}
{% for server in servers | sort -%}
    {% if local_hostname == ncn-m001 and server == ncn-m001 %}
    {% endif %}
    {% if local_hostname != ncn-m001 and server != ncn-m001 %}
    {% else %}
        server {{ server }} iburst trust
        initstepslew 1 {{ server }}
    {% endif %}
{% endfor %}
{% for peer in peers | sort -%}
    {% if local_hostname == peer %}
    {% else %}
        {% if loop.index <= 9 %}
            {# Only add 9 peers to prevent too much NTP traffic #}
            peer {{ peer }} minpoll -2 maxpoll 9 iburst
        {% endif %}
    {% endif %}
{% endfor %}
{% for net in allow | sort -%}
    allow {{ net }}
{% endfor %}
{% if local_hostname == ncn-m001 %}
    local stratum 8 orphan
{% else %}
    local stratum 10 orphan
{% endif %}
log measurements statistics tracking
logchange 1.0
makestep 0.1 3
'
json_from_file() {
  # convert bash array to csv
  local sed_cmd="sed -e 's/\s\+/,/g'"
  local file_cidrs=$(echo -n ${cidrs[@]} | eval ${sed_cmd})
  local file_peers=$(echo -n ${peers[@]} | eval ${sed_cmd})
  local file_servers=$(echo -n ${servers[@]} | eval ${sed_cmd})

  create_json ${file_cidrs} ${file_peers} ${file_servers}
}

create_json() {
  jq --arg cidrs $1 \
     --arg peers $2 \
     --arg servers $3 \
     --arg jinja "${JINJA_FILTER}" \
     '."user-data".ntp.config.template |= $jinja | ."user-data".ntp.allow |= ($cidrs | split(",")) | ."user-data".ntp.peers |= ($peers | split(",")) | ."user-data".ntp.servers |= ($servers | split(","))' \
     <<< "${NTP_TEMPLATE}"
  exit 0
}

if [ $# -lt 2 ]; then
  help
fi

eval set -- "${OPTS}"

while :
do
  case "$1" in
    -p | --peers )
      PEERS="$2"
      shift 2
      ;;
    -s | --servers )
      SERVERS="$2"
      shift 2
      ;;
    -c | --cidrs)
      CIDRS="$2"
      shift 2
      ;;
    -f | --from_file)
      . "$2"
      json_from_file
      shift 2
      ;;
    -h | --help)
      help
      exit 2
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      ;;
  esac
done

# Runs only if passing in peers,servers,cidrs on the command line (not from file)
create_json ${CIDRS} ${PEERS} ${SERVERS}
