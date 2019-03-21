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

ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE

RUN powershell -Command "\
    wget -uri 'https://iperf.fr/download/windows/iperf-2.0.9-win64.zip' -OutFile 'C:\iperf.zip';\
    Expand-Archive -Path C:\iperf.zip -DestinationPath C:\ -Force;\
    Rename-Item C:\iperf-2.0.9-win64 C:\iperf;\
    Remove-Item 'C:\iperf.zip'"

USER ContainerAdministrator
RUN mkdir C:\usr\local && mklink /D C:\usr\local\bin C:\iperf
USER ContainerUser
