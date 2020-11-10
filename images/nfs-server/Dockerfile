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

ARG BASE_IMAGE=k8sprow.azurecr.io/kubernetes-e2e-test-images/busybox:1.29
FROM $BASE_IMAGE

USER ContainerAdministrator
RUN powershell -Command \
wget -uri 'https://kent.dl.sourceforge.net/project/winnfsd/WinNFSd/2.0/WinNFSd-2.0.zip' -OutFile 'C:\WinNFSd-2.0.zip'; \
Expand-Archive -Path C:\WinNFSd-2.0.zip -DestinationPath C:\WinNFSd -Force; \
Remove-Item 'C:\WinNFSd-2.0.zip'; \
mkdir C:\exports; \
mkdir C:\usr\sbin

EXPOSE 2049
WORKDIR /WinNFSd
ADD start.ps1 /WinNFSd/start.ps1
ADD rpc.nfsd /usr/sbin/rpc.nfsd

ENTRYPOINT ["powershell.exe", "/WinNFSd/start.ps1"]