cmake_minimum_required(VERSION 3.21)
project(matmul_demo HIP CXX)
set(CMAKE_CXX_STANDARD 17)

find_package(hip REQUIRED CONFIG)
find_package(hipblas REQUIRED CONFIG)

add_executable(a.out matrix_mul.cpp)
target_link_libraries(a.out PRIVATE hip::host hipblas)
