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
FROM $BASE_IMAGE AS download
ENV CURL_VERSION 7.57.0
WORKDIR /curl
ADD https://skanthak.homepage.t-online.de/download/curl-$CURL_VERSION.cab curl.cab
RUN expand /R curl.cab /F:* .

FROM $BASE_IMAGE
RUN mkdir C:\curl && setx /M PATH "C:\curl;%PATH%"
COPY --from=download /curl/AMD64/ /curl
COPY --from=download /curl/CURL.LIC /curl
ENTRYPOINT ["curl.exe"]
