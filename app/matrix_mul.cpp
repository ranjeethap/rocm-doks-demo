#include <hip/hip_runtime.h>
#include <hipblas/hipblas.h>
#include <cstdio>
#include <vector>
#include <random>
#include <chrono>

int main() {
  const int N = 1024;
  const float alpha = 1.0f;
  const float beta  = 0.0f;

  hipError_t hip_status = hipSetDevice(0);
  if (hip_status != hipSuccess) {
    printf("HIP device not available, exiting with CPU fallback message.\n");
    return 0; // allow container to keep working in CPU-only mode
  }

  hipblasHandle_t handle;
  hipblasCreate(&handle);

  size_t bytes = N * N * sizeof(float);
  float *dA, *dB, *dC;
  hipMalloc(&dA, bytes);
  hipMalloc(&dB, bytes);
  hipMalloc(&dC, bytes);

  std::vector<float> hA(N*N), hB(N*N);
  std::mt19937 gen(42);
  std::uniform_real_distribution<float> dist(0.0f, 1.0f);
  for (int i=0;i<N*N;i++) { hA[i] = dist(gen); hB[i] = dist(gen); }

  hipMemcpy(dA, hA.data(), bytes, hipMemcpyHostToDevice);
  hipMemcpy(dB, hB.data(), bytes, hipMemcpyHostToDevice);

  auto t0 = std::chrono::high_resolution_clock::now();
  hipblasSgemm(handle, HIPBLAS_OP_N, HIPBLAS_OP_N, N, N, N, &alpha,
               dA, N, dB, N, &beta, dC, N);
  hipDeviceSynchronize();
  auto t1 = std::chrono::high_resolution_clock::now();
  double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

  printf("hipBLAS SGEMM %dx%d completed in %.3f ms\n", N, N, ms);

  hipFree(dA); hipFree(dB); hipFree(dC);
  hipblasDestroy(handle);
  return 0;
}
