package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
)

func GetOutboundIP() net.IP {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	localAddr := conn.LocalAddr().(*net.UDPAddr)

	return localAddr.IP
}

func main() {
	flagIP := flag.Bool("i", false, "a string")
	flag.Parse()
	if *flagIP {
		ip := GetOutboundIP()
		fmt.Printf(ip.String())
	} else {
		hostname, err := os.Hostname()
		if err != nil {
			log.Fatal(err)
		}
		fmt.Printf(hostname)
	}
}
