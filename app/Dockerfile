# ROCm base with HIP/hipBLAS toolchain
FROM rocm/dev-ubuntu-22.04:latest

# System deps
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential cmake git wget curl ca-certificates python3 python3-pip \
    hip-runtime-amd hipblas-dev rocblas-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy code
COPY matrix_mul.cpp /app/matrix_mul.cpp
COPY app.py /app/app.py
COPY requirements.txt /app/requirements.txt

# Build demo GEMM binary
RUN /opt/rocm/bin/hipconfig || true && \
    cmake -S . -B build && \
    cmake --build build -j && \
    mv build/a.out /usr/local/bin/matmul_demo || true

# Python deps
RUN pip3 install --no-cache-dir -r requirements.txt

ENV PYTHONUNBUFFERED=1 \
    FLASK_APP=app.py \
    FLASK_RUN_PORT=8080

EXPOSE 8080

CMD ["python3", "app.py"]
