#pragma once
#pragma once
// 2018/04/09 apply GPU acceleration
#ifndef __TEST_H__
#define __TEST_H__
#include <mex.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
// lab computer
//#include "G:\CUDA\Development\include\cuda_runtime.h"
//#include "G:\CUDA\Development\include\device_launch_parameters.h"
// server2(maybe has changed)
#include "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v10.0\include\cuda_runtime.h"
#include "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v10.0\include\device_launch_parameters.h"
//  Maximum threads of each dimension of a block: 1024 x 1024 x 64
// Maximum threads of each dimension of a grid: 2147483647 x 65535 x 65535
// Maximum threads of each dimension of a grid: 2097152(1024*2048) x 64 x 1024
using namespace std;

#define threadX 256
#define blockX 256
#define Filterlengthlimit 2048

#define MIN(x,y) x<y?x:y
#define MAX(x,y) x>y?x:y

cudaError_t FDKpro(float *Display, const float *R);

#endif