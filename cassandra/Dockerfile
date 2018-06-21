ARG BASE_IMAGE=e2eteam/java:openjdk-8-jre
FROM $BASE_IMAGE

# install CassandraDB.
ENV CASSANDRA_VERSION 3.11.2
RUN mkdir C:\cassandra_data
ADD run.sh /run.sh
ADD ready-probe.sh /ready-probe.sh
ADD http://apache.mirror.anlx.net/cassandra/$CASSANDRA_VERSION/apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz /apache-cassandra-bin.tar.gz
ADD https://github.com/samsung-cnct/cassandra-container/raw/master/kubernetes/cassandra/kubernetes-cassandra.jar /kubernetes-cassandra.jar
RUN tar -xzf C:/apache-cassandra-bin.tar.gz -C C:/ && \
move C:\apache-cassandra-3.11.2 C:\cassandra && \
mkdir C:\cassandra\logs && \
del C:\apache-cassandra-bin.tar.gz

# set Cassandra related env variables.
ENV CASSANDRA_HOME C:/cassandra/
ENV CASSANDRA_DATA C:/cassandra_data
USER ContainerAdministrator
RUN setx /M PATH "C:\cassandra\bin;%PATH%"

ADD bat_wrapper.exe C:/cassandra/bin/bin_wrapper.exe
# create .exe files which will redirect to their .bat equivalents.
# bat files cannot be call
# dir /B only prints the file names, and in this case, only .bat files names.
# %~ni will only refer to the file name without the extension.
RUN FOR /f "tokens=*" %i IN ('dir /B C:\cassandra\bin\*.bat') DO mklink C:\cassandra\bin\%~ni.exe C:\cassandra\bin\bin_wrapper.exe

USER ContainerUser

# expose ports for Cassandra.
EXPOSE 7000/tcp 7001/tcp 7199/tcp 9042/tcp 9160/tcp

ENTRYPOINT ["/bin/bash"]
CMD ["/run.sh"]
