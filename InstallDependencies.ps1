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
    "k8s.io/kubernetes/test"
)

# Install Go dependencies.
foreach ($dependency in $goDependencies) {
    Write-Verbose "Installing $dependency"
    go get $dependency
}
