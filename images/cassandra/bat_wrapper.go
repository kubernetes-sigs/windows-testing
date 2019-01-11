/*
Copyright 2018 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package  main

import (
    "bytes"
    "path/filepath"
    "fmt"
    "os"
    "os/exec"
    "strings"
)

func ExecBat(name string, args []string) error {
    name = strings.TrimSuffix(name, filepath.Ext(name))
    batName := fmt.Sprintf("%s.bat", name)

    cmd := exec.Command(batName, args...)
    var out bytes.Buffer
    cmd.Stdout = &out
    err := cmd.Run()

    if err != nil {
        fmt.Printf("error from %s (%q):\n", batName, err)
        return err
    }

    output := strings.TrimSpace(out.String())
    if len(output) != 0 {
        fmt.Printf(output)
    }

    return nil
}


func main() {
    ExecBat(os.Args[0], os.Args[1:])
}
