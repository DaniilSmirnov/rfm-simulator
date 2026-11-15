#!/bin/sh
# Builds coturn's config from rally.conf and the environment, then runs it.
#   TURN_SECRET       required: the same secret the room server signs with
#   TURN_EXTERNAL_IP  public address, when the VPS sits behind 1:1 NAT
#                     (Yandex Cloud, AWS): "public" or "public/private"
#   TURN_CERT, TURN_KEY  certificate and key for TURN over TLS; without them
#                     only UDP/TCP 3478 is served
#   TURN_TLS_PORT     TLS port (default 443)
#   TURN_REALM        realm (default rally)
# The secret goes into a file only this container can read, never on the
# command line (other users of the host see process arguments).
set -eu
if [ -z "${TURN_SECRET:-}" ]; then
	echo "rally-turn: TURN_SECRET is not set" >&2
	exit 1
fi
config="$(mktemp /tmp/turnserver.XXXXXX.conf)"
chmod 600 "$config"
cat /etc/coturn/rally.conf > "$config"
{
	echo "static-auth-secret=${TURN_SECRET}"
	[ -n "${TURN_REALM:-}" ] && echo "realm=${TURN_REALM}"
	[ -n "${TURN_EXTERNAL_IP:-}" ] && echo "external-ip=${TURN_EXTERNAL_IP}"
	if [ -n "${TURN_CERT:-}" ] && [ -n "${TURN_KEY:-}" ]; then
		echo "tls-listening-port=${TURN_TLS_PORT:-443}"
		echo "cert=${TURN_CERT}"
		echo "pkey=${TURN_KEY}"
	else
		echo "no-tls"
		echo "no-dtls"
	fi
} >> "$config"
unset TURN_SECRET
exec turnserver -c "$config"
