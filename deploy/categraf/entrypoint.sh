#!/bin/sh
set -e

# Allow categraf to send ICMP packets and bind to privileged ports
setcap cap_net_raw,cap_net_bind_service+ep /usr/bin/categraf || echo "Failed to set additional capabilities on /usr/bin/categraf"

exec /usr/bin/categraf -configs=/etc/categraf/conf