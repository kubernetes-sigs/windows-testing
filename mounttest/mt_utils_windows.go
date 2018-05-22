// +build windows

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

package main

import (
    "bytes"
    "fmt"
    "io/ioutil"
    "os"
    "os/exec"
    "path/filepath"
    "regexp"
    "strings"

    "github.com/hectane/go-acl"
)


func resolveFilePath(path string) (string) {
    var (
        symlinkTarget   string
        newPath         string
        fi              os.FileInfo
        err             error
    )

    fi, err = os.Lstat(path)
    if err != nil {
        // file might not even exist. we can't resolve. return as-is.
        return path
    }

    if fi.Mode() & os.ModeSymlink == 0 {
        // not a symlink. return absolute path instead..
        newPath, err = filepath.Abs(path)
        return newPath
    }

    newPath, _ = filepath.Split(path)
    symlinkTarget, _ = os.Readlink(path)

    bits := strings.Split(symlinkTarget, string(os.PathSeparator))
    for _, element := range bits {
        newPath = filepath.Join(newPath, element)
        newPath = resolveFilePath(newPath)
    }

    return newPath
}

func Umask(mask int) (old int, err error) {
    return 0, nil
}

func fsType(path string) error {
    if path == "" {
        return nil
    }

    fullPath := resolveFilePath(path)

    cmd := exec.Command("cmd.exe", "/c", "fsutil.exe", "fsinfo", "volumeInfo",
                        fullPath, "|", "find", "\"File System Name\"")
    var out bytes.Buffer
    cmd.Stdout = &out
    err := cmd.Run()

    if err != nil {
        fmt.Printf("error from fsutil.exe(%q): %v\n", path, err)
        return err
    }

    output := strings.TrimSpace(out.String())
    if len(output) != 0 {
        format := output[len("File System Name : "):]
        fmt.Printf("mount type of %q: %v\n", path, format)
    }

    return nil
}

func fileMode(path string) error {
    permissions, err := _getFilePerm(path)
    if permissions == "" || err != nil {
        return err
    }

    fmt.Printf("mode of Windows file %q: %v\n", path, permissions)
    return nil
}

func filePerm(path string) error {
    permissions, err := _getFilePerm(path)
    if permissions == "" || err != nil {
        return err
    }

    fmt.Printf("perms of Windows file %q: %v\n", path, permissions)
    return nil
}

func _getFilePerm(path string) (string, error) {
    var (
        fullPath            string
        out                 bytes.Buffer
        err                 error
        output              string
        val                 int
        mask                string
    )

    if path == "" {
        return "", nil
    }

    fullPath = resolveFilePath(path)
    cmd := exec.Command("powershell.exe", "-NonInteractive", "./filePermissions.ps1",
                        "-FileName", fullPath)
    cmd.Stdout = &out
    err = cmd.Run()

    if err != nil {
        fmt.Printf("error from PowerShell Script: %v\n", err)
        return "", err
    }

    output = strings.TrimSpace(out.String())

    mask = "-"
    for i := 1; i < len(output); i++ {
        val = int(output[i])
        if val & 4 != 0 {
            mask += "r"
        } else {
            mask += "-"
        }

        if val & 2 != 0 {
            mask += "w"
        } else {
            mask += "-"
        }

        if val & 1 != 0 {
            mask += "x"
        } else {
            mask += "-"
        }
    }
    return mask, nil
}

func fileOwner(path string) error {
    // Windows does not have owner UID / GID. However, it has owner SID.
    // $sid = gwmi -Query ''
    if path == "" {
        return nil
    }

    fullPath := resolveFilePath(path)

    // we need 2 backslashes for the query.
    fullPath = strings.Replace(fullPath, "\\", "\\\\", -1)
    query := fmt.Sprintf("'ASSOCIATORS OF {Win32_LogicalFileSecuritySetting.Path=\"%s\"} " +
                         "WHERE AssocClass = Win32_LogicalFileOwner ResultClass = Win32_SID'", fullPath)
    cmd := exec.Command("powershell.exe", "-NonInteractive", "gwmi", "-Query", query)
    var out bytes.Buffer
    cmd.Stdout = &out
    err := cmd.Run()

    if err != nil {
        fmt.Printf("error from gwmi query(%q): %v\n", query, err)
        return err
    }

    output := out.String()
    re, _ := regexp.Compile("SID\\s*: (.*)")
    match := re.FindStringSubmatch(output)
    if len(match) != 0 {
        fmt.Printf("owner SID of %q: %v\n", path, match[1])
    }

    return nil
}

func Chmod(path string, perm os.FileMode) error {
    return acl.Chmod(path, perm)
}

func ReadFile(filename string) ([]byte, error) {
    // Windows containers cannot handle relative symlinks properly.
    // For the purposes of testing, we'll use the absolute path instead.
    fullPath := resolveFilePath(filename)
    return ioutil.ReadFile(fullPath)
}
