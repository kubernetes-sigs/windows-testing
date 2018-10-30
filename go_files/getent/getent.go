package main

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
