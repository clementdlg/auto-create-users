FROM debian:12

RUN apt-get update && apt-get install -y vim sudo man manpages less

WORKDIR /root

COPY auto-create-users.sh .
COPY users.txt .

COPY configure-sudoers.sh .
COPY sudoers.txt .

RUN chmod 700 auto-create-users.sh
RUN chmod 700 configure-sudoers.sh

ENTRYPOINT [ "bash" ]
