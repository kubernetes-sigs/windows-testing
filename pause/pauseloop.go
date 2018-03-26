package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	sigCh := make(chan os.Signal)
	done := make(chan int, 1)
	signal.Notify(sigCh, syscall.SIGINT)
	signal.Notify(sigCh, syscall.SIGTERM)
	signal.Notify(sigCh, syscall.SIGKILL)
	go func() {
		sig := <-sigCh
		switch sig {
		case syscall.SIGINT:
			done <- 1
			os.Exit(1)
		case syscall.SIGTERM:
			done <- 2
			os.Exit(2)
		case syscall.SIGKILL:
			done <- 0
			os.Exit(0)
		}
	}()
	result := <-done
	fmt.Printf("exiting %d \n", result)
}
