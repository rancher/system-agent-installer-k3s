FROM scratch

ARG K3S_DATA_DIR
ENV K3S_DATA_DIR=${K3S_DATA_DIR}

COPY package/run.sh /run.sh
COPY artifacts/* /