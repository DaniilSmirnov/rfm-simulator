# TURN relay for direct links: coturn with the settings the game needs.
# One container per relay server; there may be any number of them, anywhere
# (docs/TURN_SERVERS.md). The room server hands out short-lived passwords for
# them (server/relays.mjs), so the relays need no database.
#   docker build -t rally-turn server/turn
#   docker run -d --restart=always --network=host --name rally-turn \
#     -e TURN_SECRET=… -e TURN_EXTERNAL_IP=… -v /etc/letsencrypt:/certs:ro \
#     -e TURN_CERT=/certs/live/turn.example.ru/fullchain.pem \
#     -e TURN_KEY=/certs/live/turn.example.ru/privkey.pem rally-turn
# The official image allows its non-root user to bind ports under 1024.
FROM coturn/coturn:4.6.3
COPY turnserver.conf /etc/coturn/rally.conf
COPY --chmod=755 entrypoint.sh /usr/local/bin/rally-turn
ENTRYPOINT ["/usr/local/bin/rally-turn"]
