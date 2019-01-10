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
EXPOSE 80
ENV chocolateyUseWindowsCompression false
RUN powershell -Command \
    Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')); \
    choco feature disable --name showDownloadProgress
RUN powershell -Command \
    choco install apache-httpd -y; \
    choco install php -y --params '"/ThreadSafe "'
RUN powershell -Command \
    $oldpath = (Get-ItemProperty -Path ‘Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment’ -Name PATH).path; \
    $newpath = “$oldpath;c:\tools\php72\;c:\Users\ContainerAdministrator\AppData\Roaming\Apache24\bin\”; \
    Set-ItemProperty -Path ‘Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment’ -Name PATH -Value $newPath
RUN powershell -Command \
    cd c:/Users/ContainerAdministrator/AppData/Roaming/Apache24/htdocs/ ; \
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 ; \
    Invoke-WebRequest -Method Get -Uri https://github.com/nrk/predis/archive/v1.1.1.zip -OutFile Predis.zip; \
    Expand-Archive Predis.zip .; \
    Remove-Item Predis.zip -Force; \
    mv predis-1.1.1 Predis
COPY php.ini tools/php72/php.ini
COPY httpd.conf /Users/ContainerAdministrator/AppData/Roaming/Apache24/conf/httpd.conf
ADD guestbook.php /Users/ContainerAdministrator/AppData/Roaming/Apache24/htdocs/guestbook.php
ADD controllers.js /Users/ContainerAdministrator/AppData/Roaming/Apache24/htdocs/controllers.js
ADD index.html /Users/ContainerAdministrator/AppData/Roaming/Apache24/htdocs/index.html
COPY run.ps1 run.ps1
USER ContainerAdministrator
CMD ["powershell", "-Command", "/run.ps1"]
