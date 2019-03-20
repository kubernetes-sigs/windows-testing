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

$VerbosePreference = "continue"

Write-Verbose "Checking if Go is installed / can be found..."
Get-Command -ErrorAction Ignore -Name go | Out-Null
if (!$?) {
    Write-Verbose "Go is not installed or not found. Noop."
    exit 1
}

Write-Verbose "Go found. Installing dependencies..."

$goDependencies = @(
    "github.com/ghodss/yaml",
    "github.com/gogo/protobuf",
    "github.com/golang/glog",
    "github.com/google/gofuzz",
    "github.com/hectane/go-acl",
    "github.com/json-iterator/go",
    "github.com/spf13/pflag",
    "golang.org/x/net/http2",
    "gopkg.in/inf.v0",
    "k8s.io/api/admission",
    "k8s.io/api/admissionregistration",
    "k8s.io/api/core/v1",
    "k8s.io/apiextensions-apiserver",
    "k8s.io/apiserver",
    "k8s.io/client-go/rest",
    "k8s.io/component-base/cli/flag",
    "k8s.io/component-base/logs",
    "k8s.io/examples",
    "k8s.io/kubernetes/test",
    "k8s.io/sample-apiserver"
)

# Install Go dependencies.
foreach ($dependency in $goDependencies) {
    Write-Verbose "Installing $dependency"
    go get $dependency
}

# the sample-apiserver image requires a specific tag.
pushd $env:GOPATH\src\k8s.io\sample-apiserver
git checkout --track origin/release-1.10
popd
