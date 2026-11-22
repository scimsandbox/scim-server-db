FROM dhi.io/flyway:12-debian13@sha256:ea35d91f704faf7812ecad6b7a48b6956037bf82b3a131a811a5443e2ef3e9d3

USER 0:0
COPY --chown=0:0 --chmod=0444 sql/ /usr/share/flyway/sql/
# Remove unused MSSQL JDBC driver (flagged as CVE-2025-59250 by Trivy) and lock down
# only the top-level /usr/share/flyway directories owned by 65532 so OverlayFS does not
# copy up the read-only root-owned /usr/share/flyway/lib JAR layer.
RUN rm -f /usr/share/flyway/lib/mssql-jdbc-*.jar \
    && chown 0:0 /usr/share/flyway /usr/share/flyway/sql /usr/share/flyway/conf /usr/share/flyway/jars /usr/share/flyway/drivers \
    && chmod a-st,a=rx /usr/share/flyway /usr/share/flyway/sql /usr/share/flyway/conf /usr/share/flyway/jars /usr/share/flyway/drivers

USER 65532:65532

ENTRYPOINT ["flyway", "migrate", "-locations=filesystem:/usr/share/flyway/sql", "-connectRetries=5"]
