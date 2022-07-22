#!/usr/bin/env bash

SHORT=p:,s:,c:,help
LONG=peers:,servers:,cidrs:,help
OPTS=$(getopt --alternative --name ntp --options $SHORT --longoptions $LONG -- "$@")

help()
{
    echo "Usage: ntp-csi-input.sh \\
               [ -p | --peers ]
               [ -s | --servers ]
               [ -c | --cidrs ]
               [ -h | --help  ]

Example: ./ntp-csi-input.sh --peers ncn-w001,ncn-w002,ncn-w003,ncn-s001 \\
                            --servers ncn-m001,lumintp.csc.fi \\
                            --cidrs 10.120.0.0/14,10.106.0.0/17,10.252.0.0/17
"
    exit 2
}

if [ $# -lt 6 ]; then
  help
fi

eval set -- "${OPTS}"

while :
do
  case "$1" in
    -p | --peers )
      peers="$2"
      shift 2
      ;;
    -s | --servers )
      servers="$2"
      shift 2
      ;;
    -c | --cidrs)
      cidrs="$2"
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

NTP_TEMPLATE='
{
    "user-data": {
        "ntp": {
            "allow": [],
            "config": {
                "confpath": "/etc/chrony.d/cray.conf",
                "template": "## template: jinja\n# csm-generated config.  Do not modify--changes can be overwritten\n{% for pool in pools | sort -%}\n{% if local_hostname == ncn-m001 and pool == ncn-m001 %}\n{% endif %}\n{% if local_hostname != ncn-m001 and pool != ncn-m001 %}\n{% else %}\npool {{ pool }} iburst\n{% endif %}\n{% endfor %}\n{% for server in servers | sort -%}\n{% if local_hostname == ncn-m001 and server == ncn-m001 %}\n{% endif %}\n{% if local_hostname != ncn-m001 and server != ncn-m001 %}\n{% else %}\nserver {{ server }} iburst trust\ninitstepslew 1 {{ server }}\n{% endif %}\n{% endfor %}\n{% for peer in peers | sort -%}\n{% if local_hostname == peer %}\n{% else %}\n{% if loop.index <= 9 %}\n{# Only add 9 peers to prevent too much NTP traffic #}\npeer {{ peer }} minpoll -2 maxpoll 9 iburst\n{% endif %}\n{% endif %}\n{% endfor %}\n{% for net in allow | sort -%}\nallow {{ net }}\n{% endfor %}\n{% if local_hostname == ncn-m001 %}\nlocal stratum 8 orphan\n{% else %}\nlocal stratum 10 orphan\n{% endif %}\nlog measurements statistics tracking\nlogchange 1.0\nmakestep 0.1 3\n"
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

jq --arg cidrs $cidrs \
   --arg peers $peers \
   --arg servers $servers \
   '."user-data".ntp.allow |= .+ ($cidrs | split(",")) | ."user-data".ntp.peers |= .+ ($peers | split(",")) | ."user-data".ntp.servers |= .+ ($servers | split(","))' \
   <<< "${NTP_TEMPLATE}"
