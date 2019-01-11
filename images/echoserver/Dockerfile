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

# RUN mkdir C:\build\openresty\source
RUN powershell -Command "wget -uri 'https://openresty.org/download/openresty-1.13.6.2-win64.zip' -OutFile 'C:\busybox\openresty-1.13.6.2-win64.zip'"
RUN powershell -Command "Expand-Archive -Path C:\busybox\openresty-1.13.6.2-win64.zip -DestinationPath C:\busybox\openresty -Force"
RUN powershell -Command "Remove-Item 'C:\busybox\openresty-1.13.6.2-win64.zip'"

USER ContainerAdministrator
ENV chocolateyUseWindowsCompression false
RUN powershell -Command \
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')); \
choco feature disable --name showDownloadProgress
RUN powershell -Command choco install openssl.light -y

USER ContainerUser

RUN mkdir C:\busybox\openresty\openresty-1.13.6.2-win64\certs

ADD run.sh /busybox/openresty/openresty-1.13.6.2-win64/run.sh
ADD nginx.conf /busybox/openresty/openresty-1.13.6.2-win64/conf/nginx.conf
ADD template.lua /busybox/openresty/openresty-1.13.6.2-win64/lua/template.lua

WORKDIR /busybox/openresty/openresty-1.13.6.2-win64
EXPOSE 80 443 8080 8443
ENTRYPOINT ["/bin/sh", "/busybox/openresty/openresty-1.13.6.2-win64/run.sh"]