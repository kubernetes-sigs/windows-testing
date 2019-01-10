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

ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE
RUN mkdir c:\build\nginx\source &&\
powershell -Command "wget -uri 'http://nginx.org/download/nginx-1.9.3.zip' -OutFile 'c:\nginx-1.9.3.zip'" &&\
powershell -Command "Expand-Archive -Path C:\nginx-1.9.3.zip -DestinationPath C:\nginx -Force" &&\
del c:\nginx-1.9.3.zip
USER ContainerAdministrator
RUN mkdir C:\usr\share
RUN mklink /D C:\usr\share\nginx C:\nginx\nginx-1.9.3
RUN mklink C:\Windows\System32\sync.exe C:\Windows\System32\SyncHost.exe
USER ContainerUser
WORKDIR /nginx/nginx-1.9.3
EXPOSE 80
ENTRYPOINT ["nginx.exe"]
