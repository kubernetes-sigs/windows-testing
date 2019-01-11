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

ARG BASE_IMAGE=microsoft/windowsservercore:1803
FROM $BASE_IMAGE
LABEL Description="Redis" Vendor="MSOpenTech" Version="3.2"
EXPOSE 6379
WORKDIR /redis
RUN powershell -Command \
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 ; \
Invoke-WebRequest -Method Get -Uri https://github.com/MSOpenTech/redis/releases/download/win-3.2.100/Redis-x64-3.2.100.zip -OutFile redis.zip ; \
Expand-Archive redis.zip . ; \
Remove-Item redis.zip -Force ; \
mkdir C:\data
COPY redis.conf ./redis.windows.conf
COPY run.ps1 /run.ps1
USER ContainerAdministrator
CMD ["powershell", "-Command", "/run.ps1"]
