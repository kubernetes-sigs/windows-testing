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
	"bufio"
	"fmt"
	"io/ioutil"
	"os"
	"regexp"
)


func check(e error) {
	if e != nil {
		panic(e)
	}
}

func getent(name string) string {
	var content string;
	hosts_file := "C:/Windows/System32/drivers/etc/hosts"

	if name == "" {
		content, err := ioutil.ReadFile(hosts_file)
		check(err)
		return string(content)
	}

	file, err := os.Open(hosts_file)
	check(err)
	defer file.Close()

	scanner := bufio.NewScanner(file)
	r, _ := regexp.Compile(fmt.Sprintf("^[^#].*[\\s]+%s($|\\s)", name))
	for scanner.Scan() {
		content = scanner.Text()
		if r.MatchString(content) {
			return content
		}
	}

	err = scanner.Err()
	check(err)
	return ""
}


func main() {
	if len(os.Args) < 2 {
		fmt.Println(fmt.Sprintf("Expected usage: %s hosts [entry]", os.Args[0]))
		os.Exit(1)
	}

	entry := "";
	if len(os.Args) > 2 {
		entry = os.Args[2]
	}

	result := getent(entry)
	if result != "" {
		fmt.Println(result)
	}
}
