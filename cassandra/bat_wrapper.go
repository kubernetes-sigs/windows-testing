package main

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
