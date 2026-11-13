FROM dhi.io/flyway:12-debian13@sha256:ea35d91f704faf7812ecad6b7a48b6956037bf82b3a131a811a5443e2ef3e9d3

USER 0:0
COPY --chown=0:0 --chmod=0444 sql/ /usr/share/flyway/sql/
RUN chown 0:0 /usr/share/flyway/sql && chmod 0555 /usr/share/flyway/sql

USER 65532:65532

ENTRYPOINT ["flyway", "migrate", "-locations=filesystem:/flyway/sql", "-connectRetries=5"]
