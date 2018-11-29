# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG BASE_BUSYBOX_IMAGE=e2eteam/busybox:1.29
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
