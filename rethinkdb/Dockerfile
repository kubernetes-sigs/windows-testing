ARG BASE_BUSYBOX_IMAGE=e2eteam/busybox:1.24
FROM $BASE_BUSYBOX_IMAGE

# install download RethinkDB.
ENV RETHINKDB_VERSION 2.3.6
ADD https://download.rethinkdb.com/windows/rethinkdb-$RETHINKDB_VERSION.zip /rethinkdb.zip

RUN powershell -Command "Expand-Archive -Path C:\rethinkdb.zip -DestinationPath C:\ -Force" && \
move C:\rethinkdb-2.3.6 C:\rethinkdb && \
del C:\rethinkdb.zip
ADD run.ps1 /run.ps1

# expose ports for RethinkDB.
EXPOSE 28015/tcp 29015/tcp 8080/tcp

ENTRYPOINT ["powershell", "-Command", "/run.ps1"]
