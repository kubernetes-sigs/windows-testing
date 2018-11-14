ARG BASE_IMAGE=e2eteam/busybox:1.29
FROM $BASE_IMAGE
ADD https://github.com/diegocr/netcat/raw/master/nc.exe /bin/nc.exe
ENTRYPOINT ["cmd.exe", "/s", "/c", "sleep", "3600"]
