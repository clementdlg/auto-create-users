FROM debian:12

RUN apt-get update && apt-get install -y vim sudo man manpages less

WORKDIR /root

# ----- USERS PART ------
COPY auto-create-users.sh .
COPY users.txt .
RUN chmod 700 auto-create-users.sh

# debug 
# RUN ./auto-create-users.sh users.txt

# ----- SUDO PART ------
COPY configure-sudoers.sh .
COPY sudoers.txt .
RUN chmod 700 configure-sudoers.sh

# ----- SUID PART ------
COPY suid-sgid-ctl.sh .
RUN chmod 700 suid-sgid-ctl.sh

ENTRYPOINT [ "bash" ]
