# Dedicated room server: the Linux export run headless as an invisible room
# host (game/scripts/net/dedicated.gd). The export comes in as a second build
# context:
#   npm run build:linux
#   docker build --build-context export=dist-linux -t rally-dedicated server/dedicated
#   docker run -d --restart=always --name rally-forest -e RALLY_DEDICATED_TOKEN=… rally-dedicated --stage=0 --room=A1B2C3
# One container is one room: the simulation runs on one core.
FROM debian:bookworm-slim
RUN useradd --create-home --uid 10001 rally
WORKDIR /opt/rally
COPY --from=export --chown=rally RallyFansSimulator.x86_64 RallyFansSimulator.pck ./
COPY --from=export --chown=rally *.so ./
COPY --chown=rally override.cfg ./
USER rally
ENTRYPOINT ["./RallyFansSimulator.x86_64", "--headless", "--", "--dedicated"]
CMD ["--stage=0"]
