#FROM fedora:32
#FROM fedora:38
FROM public.ecr.aws/docker/library/fedora:38

# Metadata
LABEL author="Charles Shih"
LABEL maintainer="cheshi@redhat.com"
LABEL version="2.0"
LABEL description="This image provdes environment for aliyun_performance_validation project."

# Keeps Python from generating .pyc files in the container
ENV PYTHONDONTWRITEBYTECODE 1

# Turns off buffering for easier container logging
ENV PYTHONUNBUFFERED 1

# Configure application
WORKDIR /app

# Install software packages
RUN dnf install -y jq psmisc findutils \
    which ncurses tree procps-ng shyaml bc \
    pip diffutils less openssh-clients

# Install pip requirements
ADD ./requirements.txt /tmp/requirements.txt
RUN python3 -m pip install -r /tmp/requirements.txt

# Create mount point
RUN mkdir -p /app 

# Export volumes
VOLUME [ "/app" ]

# During debugging, this entry point will be overridden.
CMD ["/bin/bash"]

