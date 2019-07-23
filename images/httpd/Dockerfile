# Copyright 2019 The Kubernetes Authors.
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

FROM BASEIMAGE

ENV chocolateyUseWindowsCompression false
RUN powershell -Command \
    Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')); \
    choco feature disable --name showDownloadProgress
RUN powershell -Command \
    choco install apache-httpd --version 2.4.38 -y; \
    choco install php --version 7.2.14 -y --params '"/ThreadSafe "'
RUN powershell -Command \
    $oldpath = (Get-ItemProperty -Path ‘Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment’ -Name PATH).path; \
    $newpath = “$oldpath;c:\tools\php72\;c:\Users\ContainerAdministrator\AppData\Roaming\Apache24\bin\”; \
    Set-ItemProperty -Path ‘Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment’ -Name PATH -Value $newPath
RUN mkdir C:\usr\local &&\
    mklink /D C:\usr\local\apache2 C:\Users\ContainerAdministrator\AppData\Roaming\Apache24

COPY httpd.conf /Users/ContainerAdministrator/AppData/Roaming/Apache24/conf/httpd.conf
COPY index.html /Users/ContainerAdministrator/AppData/Roaming/Apache24/htdocs/index.html

EXPOSE 80
USER ContainerAdministrator
ENTRYPOINT ["c:/Users/ContainerAdministrator/AppData/Roaming/Apache24/bin/httpd.exe"]
