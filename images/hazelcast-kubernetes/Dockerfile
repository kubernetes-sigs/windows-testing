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

ARG BASE_IMAGE=k8sprow.azurecr.io/kubernetes-e2e-test-images/java:openjdk-8-jre
FROM $BASE_IMAGE

# download the Kubernetes Hazelcast bootstrapper.
ADD https://github.com/pires/hazelcast-kubernetes-bootstrapper/releases/download/3.8_1/hazelcast-kubernetes-bootstrapper-3.8_1.jar /bootstrapper.jar

# expose port for Hazelcast.
EXPOSE 5701/tcp

ENTRYPOINT ["java", "-jar", "/bootstrapper.jar"]
