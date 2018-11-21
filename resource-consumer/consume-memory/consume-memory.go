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
	"flag"
	"fmt"
	_ "net/http/pprof"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

func parseSize(str string) (val int64, err error) {
	if strings.HasSuffix(str, "M") {
		strval := strings.TrimSuffix(str, "M")
		val, err := strconv.ParseInt(strval, 10, 64)
		if err != nil {
			return 0, err
		}
		val = val * int64(sizeMB)
		return val, nil
	}
	return 0, nil
}

func bigBytes(bytes int64) *[]byte {
	s := make([]byte, bytes)
	return &s
}

var (
	mem     runtime.MemStats
	workers = flag.Int("m", 0, "spawn N workers spinning on malloc()/free()")
	sizestr = flag.String("vm-bytes", "256M", "malloc B bytes per vm worker")
	_       = flag.Int("vm-hang", 0, "Dummy flag")
	timeout = flag.String("t", "0", "timeout after N seconds")
	sizeMB  = 32000000 //made match usage reported from task manager as 1 000 000 B didn't cut it
	sizeB   int64
)

func worker(id int, wg *sync.WaitGroup, sleep time.Duration, jobs <-chan int, results chan<- int, errors chan<- error) {
	for j := range jobs {
		s := bigBytes(sizeB)
		if s == nil {
			errors <- fmt.Errorf("pointer is nil, error on job %v", j)
		}
		time.Sleep(sleep)
		wg.Done()
	}
}

func main() {
	var err error
	flag.Parse()
	sizeB, err = parseSize(*sizestr)
	if err != nil {
		fmt.Println("got error: ", err)
	}
	timeoutd, err := strconv.Atoi(*timeout)
	if err != nil {
		fmt.Println("got error: ", err)
	}
	sleep := time.Duration(timeoutd) * time.Second
	jobs := make(chan int, 100)
	results := make(chan int, 100)
	errors := make(chan error, 100)
	var wg sync.WaitGroup
	for w := 1; w <= *workers; w++ {
		go worker(w, &wg, sleep, jobs, results, errors)
	}
	for j := 1; j <= *workers; j++ {
		jobs <- j
		wg.Add(1)
	}
	close(jobs)
	wg.Wait()
	select {
	case err := <-errors:
		fmt.Println("finished with error:", err.Error())
	default:
	}
}
