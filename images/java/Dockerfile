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

# this might take a while. fetching Java takes longer since it's hosted on github.
ENV JAVA_URL "http://github.com/ojdkbuild/ojdkbuild/releases/download/1.8.0.171-1/java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64.zip"
ADD $JAVA_URL /

RUN mkdir C:\java
RUN powershell -Command "Expand-Archive -Path C:\java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64.zip -DestinationPath C:\java -Force" &&\
powershell -Command "Rename-Item -Path C:\java\java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64 -NewName C:\java\java-1.8.0" &&\
del C:\java-1.8.0-openjdk-1.8.0.171-1.b10.ojdkbuild.windows.x86_64.zip

# set Java related env variables.
USER ContainerAdministrator
RUN setx /M PATH "C:\java\java-1.8.0\bin;%PATH%"
ENV _JAVA_OPTIONS "-Xmx512M -Xms512m"
ENV JAVA_HOME "C:\java\java-1.8.0"
USER ContainerUser
