/*
Copyright 2015 The Kubernetes Authors.

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
	"flag"
	"fmt"
	"math"
	"syscall"
	"time"

	syswin "golang.org/x/sys/windows"
)

const sleep = time.Duration(10) * time.Millisecond

func doSomething() {
	for i := 1; i < 10000000; i++ {
		x := float64(0)
		x += math.Sqrt(0)
	}
}

type ProcCPUStats struct {
	User   float64   // time spent in user mode
	System float64   // time spent in system mode
	Time   time.Time // when the sample was taken
	Total  float64   // total of all time fields
}

func statsNow(handle syscall.Handle) (s ProcCPUStats) {
	var processInfo syscall.Rusage
	syscall.GetProcessTimes(handle, &processInfo.CreationTime, &processInfo.ExitTime, &processInfo.KernelTime, &processInfo.UserTime)
	s.Time = time.Now()
	s.User = float64(processInfo.UserTime.Nanoseconds())/100000000 + float64(processInfo.UserTime.Nanoseconds())/100000000
	s.System = float64(processInfo.KernelTime.Nanoseconds())/100000000 + float64(processInfo.KernelTime.Nanoseconds())/100000000
	s.Total = s.User + s.System
	return s
}

func usageNow(first ProcCPUStats, second ProcCPUStats) float64 {
	dT := second.Time.Sub(first.Time).Seconds()
	return 100 * (second.Total - first.Total) / dT
}

var (
	millicores  = flag.Int("millicores", 0, "millicores number")
	durationSec = flag.Int("duration-sec", 0, "duration time in seconds")
)

func main() {
	//lsd := syswin.NewLazySystemDLL("kernel32.dll")
	phandle, err := syswin.GetCurrentProcess()
	if err != nil {
		fmt.Println("Got err: ", err)
		return
	}
	handle := syscall.Handle(phandle)
	flag.Parse()
	// convert millicores to percentage
	millicoresPct := float64(*millicores) / float64(10)
	duration := time.Duration(*durationSec) * time.Second
	start := time.Now()
	first := statsNow(handle)

	for time.Now().Sub(start) < duration {
		cpu := usageNow(first, statsNow(handle))
		fmt.Println("cpu: ", cpu)
		if cpu < millicoresPct {
			doSomething()
		} else {
			time.Sleep(sleep)
		}
	}
}
