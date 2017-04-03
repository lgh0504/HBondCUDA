#define _USE_MATH_DEFINES
//#define BENCHMARK_TIMING

#include <stdio.h>
#include <iostream>
#include <math.h>
#include <float.h>
#include <algorithm>

#include "kernel.cuh"

using namespace std;

__global__ void waterFilterKernel(char *out, const GPUAtom *inWaters, const float centx, const float centy, const float centz, const float maxdist, const size_t nWaters)
{
    //Find where we are in the GPU
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    //Make sure we aren't trying to access outside our pre-definied dimensions
    if (i < nWaters)
    {
        //Get the distance between the water and the center of geometry
        float distx = inWaters[i].x - centx;
        float disty = inWaters[i].y - centy;
        float distz = inWaters[i].z - centz;
        float dist = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
        //Flag if it is within the proper distance or not
        out[i] = (dist < maxdist);
    }
}

__global__ void bondDistKernel(char *out, const GPUAtom *inProtein, const GPUAtom *inWaters, const size_t nProteins, const size_t nWaters)
{
    //Find where we are in the GPU
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;

    //Make sure we aren't trying to access outside our pre-definied dimensions
    if (i < nWaters && j < nProteins)
    {
        //out[(j * nWaters) + i] = 'n';  //Set default to "No bond"
        if (i % 3 == 0) //Only look for oxygen atoms, which should be every third atom starting at atom index 0
        {
            //Get the distance between the heavy atoms
            float distx = inWaters[i].x - inProtein[j].x;
            float disty = inWaters[i].y - inProtein[j].y;
            float distz = inWaters[i].z - inProtein[j].z;
            float dist = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            out[(j * nWaters) + i] = (dist < 3.5f);
        }
    }
}

__global__ void waterToAcceptorKernel(char *out, const GPUAtom *inAcceptor, const GPUAtom *inWater, const size_t nAcceptors, const size_t nWaters)
{
    //Find where we are in the GPU
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;

    //Make sure we aren't trying to access outside our pre-definied dimensions
    if (i < nWaters && j < nAcceptors)
    {
        if (out[(j * nWaters) + i] == true) //Make sure we are in bonding distance from before
        {
            //Find which hydrogen is between the acceptor and the oxygen
            float distx = inWater[i + 1].x - inAcceptor[j].x;
            float disty = inWater[i + 1].y - inAcceptor[j].y;
            float distz = inWater[i + 1].z - inAcceptor[j].z;
            float dist1 = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            distx = inWater[i + 2].x - inAcceptor[j].x;
            disty = inWater[i + 2].y - inAcceptor[j].y;
            distz = inWater[i + 2].z - inAcceptor[j].z;
            float dist2 = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            int closestindex = -1;
            if (dist1 < dist2)
            {
                closestindex = i + 1;
            }
            else
            {
                closestindex = i + 2;
            }
            //Calculate the angle parameters
            distx = inWater[i].x - inAcceptor[j].x;
            disty = inWater[i].y - inAcceptor[j].y;
            distz = inWater[i].z - inAcceptor[j].z;
            float a = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            distx = inWater[i].x - inWater[closestindex].x;
            disty = inWater[i].y - inWater[closestindex].y;
            distz = inWater[i].z - inWater[closestindex].z;
            float b = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            distx = inWater[closestindex].x - inAcceptor[j].x;
            disty = inWater[closestindex].y - inAcceptor[j].y;
            distz = inWater[closestindex].z - inAcceptor[j].z;
            float c = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            float theta = (acosf(((a * a) + (b*b) - (c*c)) / (2 * a * b))) * (180.0f / M_PI);
            if (theta > 30.0f) //If the angle is too large, change the bond to not a bond
            {
                out[(j * nWaters) + i] = false;
            }
        }
    }
}


__global__ void donorToWaterKernel(char *out, const GPUAtom *inDonor, const GPUAtom *inLinker, const GPUAtom *inWater, const size_t nDonors, const size_t nLinkers, const size_t nWaters)
{
    //Find where we are in the GPU
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;

    //Make sure we aren't trying to access outside our pre-definied dimensions
    if (i < nWaters && j < nDonors)
    {
        if (out[(j * nWaters) + i] == true) //Make sure we are in bonding distance from before
        {
            int closestindex = -1;
            float mindist = FLT_MAX;  //Equivalent to "c"
            //Find the bridging linker hydrogen in the residue
            for (int k = 0; k < nLinkers; k++)
            {
                if (inLinker[k].resid == inDonor[j].resid) //Hydrogen belongs to same residue
                {
                    float distx = inLinker[k].x - inWater[i].x;
                    float disty = inLinker[k].y - inWater[i].y;
                    float distz = inLinker[k].z - inWater[i].z;
                    float dist = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
                    if (dist < mindist)
                    {
                        mindist = dist;
                        closestindex = k;
                    }
                    else if (inDonor[j].resid < inLinker[k].resid)
                    {
                        break;
                    }
                }
            }
            //Calculate the angle parameter
            float distx = inLinker[closestindex].x - inDonor[j].x;
            float disty = inLinker[closestindex].y - inDonor[j].y;
            float distz = inLinker[closestindex].z - inDonor[j].z;
            float a = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            distx = inWater[i].x - inDonor[j].x;
            disty = inWater[i].y - inDonor[j].y;
            distz = inWater[i].z - inDonor[j].z;
            float b = sqrtf((distx * distx) + (disty * disty) + (distz * distz));
            float theta = (acosf(((a * a) + (b*b) - (mindist*mindist)) / (2 * a * b))) * (180.0f / M_PI);
            if (theta > 30.0f) //If the angle is too large, change the bond to not a bond
            {
                out[(j * nWaters) + i] = false;
            }
        }
    }
}

__global__ void timelineMapKernel2D(char * outMap, int * timeline, int * tllookup, int * boundAAs, int * boundwaters, const int window, const int threshold, const int nframes, const int nAAs, const int nwaters)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x; //Frame
    int j = blockIdx.y * blockDim.y + threadIdx.y; //AA

    if (i < (nframes * nwaters) && j < nAAs)
    {
        int currwater = i / nframes;
        int currframe = i % nframes;

        int boundframes = 0;
        if (currframe < (nframes - window))
        {
            for (int currwindow = 0; currwindow < window; currwindow++)
            {
                
                for (int currsearch = tllookup[currframe + currwindow]; currsearch < tllookup[currframe + currwindow + 1]; currsearch += 2)
                {
                    if ((timeline[currsearch] == boundAAs[j]) && (timeline[currsearch + 1] == boundwaters[currwater]))
                    {
                        boundframes++;
                    }
                }
            }
        }
        outMap[(j * nframes) + i] = (boundframes >= threshold);
    }
}

__global__ void timelineMapKernel1D(char * outMap, int * timeline, int * tllookup, const int window, const int threshold, const int offset, const int nframes, const int nAAs, const int nwaters)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < ((nframes - window) * nwaters * nAAs))
    {
        int frame = i / (nwaters * nAAs);
        int water = (i % (nwaters * nAAs)) / nwaters;
        int AA = (i % (nwaters * nAAs)) % nwaters;
        int boundframes = 0;
        for (int currwindow = 0; currwindow < window; currwindow++)
        {
            int searchb = tllookup[frame + currwindow + 1];
            for (int currsearch = tllookup[frame + currwindow]; currsearch < searchb; currsearch += 2)
            {
                if ((timeline[currsearch] == AA) && (timeline[currsearch + 1] == (water + offset)))
                {
                    boundframes++;
                }
            }
        }
        __syncthreads();
        outMap[i] = (boundframes >= threshold) ? 1 : 0 ;
    }
}


__global__ void visitAndBridgerAnalysisKernel1D(char * outbridger, char * outvisitlist, int * outframesbound, const char * timelinemap, const int nframes, const int nAAs, const int nwaters)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    if (i < (nframes * nwaters))
    {
        int frame = i / (nwaters * nAAs);
        int water = (i % (nwaters * nAAs)) / nwaters;

        int boundcount = 0;
        for (int j = 0; j < nAAs; ++j)
        {
            if (timelinemap[(j + nwaters * (water + nframes * frame))] == 1)
            {
                boundcount++;
                outvisitlist[(water * nAAs) + j] = 1;  //Might be unsafe
            }
        }
        outframesbound[(water * nframes) + frame] = boundcount;
        outbridger[(water * nframes) + frame] = (boundcount > 1) ? 1 : 0 ;
    }
}

cudaError_t waterFilterCuda(char *out, const GPUAtom *inWater, const float centx, const float centy, const float centz, const float maxdist, const size_t nWaters, cudaDeviceProp &deviceProp)
{
    // the device arrays
    GPUAtom *dev_inWater = 0;
    char *dev_out = 0;
    cudaError_t cudaStatus;

    // use div because it's more accurrate than the rounding BS
    auto gridDiv = div(nWaters, deviceProp.maxThreadsPerBlock);
    auto gridY = gridDiv.quot;

    // ass backwards way of rounding up (maybe use the same trick as above? It might be "faster")
    if (gridDiv.rem != 0)
        gridY++;

    // find the block and grid size
    auto blockSize = deviceProp.maxThreadsPerBlock;
    int gridSize = min(16 * deviceProp.multiProcessorCount, gridY);

    // Allocate GPU buffers for vectors
    cudaStatus = cudaMalloc((void**)&dev_out, nWaters * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_inWater, nWaters * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_inWater, inWater, nWaters * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU.
    waterFilterKernel << <gridSize, blockSize >> > (dev_out, dev_inWater, centx, centy, centz, maxdist, nWaters);

    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "dielectric kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching density kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(out, dev_out, nWaters * sizeof(char), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // delete all our device arrays
Error:
    cudaFree(dev_inWater);
    cudaFree(dev_out);

    return cudaStatus;
}

cudaError_t bondDistCuda(char *out, const GPUAtom *inProteins, const GPUAtom *inWaters, const size_t nProteins, const size_t nWaters, cudaDeviceProp &deviceProp)
{
    // define device arrays
    GPUAtom *dev_protein = 0;
    GPUAtom *dev_water = 0;
    char *dev_out = 0;
    cudaError_t cudaStatus;

    // Setup the kernel dimensions
    int blockDim = sqrt(deviceProp.maxThreadsPerBlock);
    auto blockSize = dim3(blockDim, blockDim);
    //Waters are chosen for x dimension, since CUDA can handle MUCH more data along the x dimension than y.
    auto gridSize = dim3(round((blockDim - 1 + nWaters) / blockDim), round((blockDim - 1 + nProteins) / blockDim));

    // Allocate GPU buffers for vectors.
    cudaStatus = cudaMalloc((void**)&dev_out, nProteins * nWaters * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_protein, nProteins * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_water, nWaters * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_protein, inProteins, nProteins * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_water, inWaters, nWaters * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU.
    bondDistKernel << <gridSize, blockSize >> > (dev_out, dev_protein, dev_water, nProteins, nWaters);

    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "Distance kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching hbond distance kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(out, dev_out, nProteins * nWaters * sizeof(char), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // clear all our device arrays
Error:
    cudaFree(dev_protein);
    cudaFree(dev_water);
    cudaFree(dev_out);

    return cudaStatus;
}

cudaError_t waterToAcceptorCuda(char *out, const GPUAtom *inAcceptor, const GPUAtom *inWater, const size_t nAcceptors, const size_t nWaters, cudaDeviceProp &deviceProp)
{
    // define device arrays
    GPUAtom *dev_acceptor = 0;
    GPUAtom *dev_water = 0;
    char *dev_out = 0;
    cudaError_t cudaStatus;

    // Setup the kernel dimensions
    int blockDim = sqrt(deviceProp.maxThreadsPerBlock);
    auto blockSize = dim3(blockDim, blockDim);
    //Waters are chosen for x dimension, since CUDA can handle MUCH more data along the x dimension than y.
    auto gridSize = dim3(round((blockDim - 1 + nWaters) / blockDim), round((blockDim - 1 + nAcceptors) / blockDim));

    // Allocate GPU buffers for vectors.
    cudaStatus = cudaMalloc((void**)&dev_out, nAcceptors * nWaters * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_acceptor, nAcceptors * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_water, nWaters * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_out, out, nAcceptors * nWaters * sizeof(char), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_acceptor, inAcceptor, nAcceptors * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_water, inWater, nWaters * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU.
    waterToAcceptorKernel << <gridSize, blockSize >> > (dev_out, dev_acceptor, dev_water, nAcceptors, nWaters);

    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "Donor to water angle kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching donor to water angle kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(out, dev_out, nAcceptors * nWaters * sizeof(char), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // clear all our device arrays
Error:
    cudaFree(dev_acceptor);
    cudaFree(dev_water);
    cudaFree(dev_out);

    return cudaStatus;
}

cudaError_t donorToWaterCuda(char *out, const GPUAtom *inDonor, const GPUAtom *inLinker, const GPUAtom *inWater, const size_t nDonors, const size_t nLinkers, const size_t nWaters, cudaDeviceProp &deviceProp)
{
    // define device arrays
    GPUAtom *dev_donor = 0;
    GPUAtom *dev_linker = 0;
    GPUAtom *dev_water = 0;
    char *dev_out = 0;
    cudaError_t cudaStatus;

    // Setup the kernel dimensions
    int blockDim = sqrt(deviceProp.maxThreadsPerBlock);
    auto blockSize = dim3(blockDim, blockDim);
    //Waters are chosen for x dimension, since CUDA can handle MUCH more data along the x dimension than y.
    auto gridSize = dim3(round((blockDim - 1 + nWaters) / blockDim), round((blockDim - 1 + nDonors) / blockDim));

    // Allocate GPU buffers for vectors.
    cudaStatus = cudaMalloc((void**)&dev_out, nDonors * nWaters * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_donor, nDonors * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_linker, nLinkers * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_water, nWaters * sizeof(GPUAtom));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_out, out, nDonors * nWaters * sizeof(char), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_donor, inDonor, nDonors * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_linker, inLinker, nLinkers * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_water, inWater, nWaters * sizeof(GPUAtom), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU.
    donorToWaterKernel << <gridSize, blockSize >> > (dev_out, dev_donor, dev_linker, dev_water, nDonors, nLinkers, nWaters);

    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "Water to acceptor angle kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching water to acceptor angle kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(out, dev_out, nDonors * nWaters * sizeof(char), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // clear all our device arrays
Error:
    cudaFree(dev_donor);
    cudaFree(dev_linker);
    cudaFree(dev_water);
    cudaFree(dev_out);

    return cudaStatus;
}

//--------------------------------------------------------------------REFACTORED KERNELS-----------------------------------------------------------------

__global__ void timelineWindowKernel(char * outTimeline, int * inFlatTimeline, int * inTLLookup, const int window, const int threshold, const int currWater, const int numAAs, const int numFrames)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x; //frames
    int j = blockIdx.y * blockDim.y + threadIdx.y; //AAs
    //Make sure we don't go beyond the scope of the analysis arrays
    if (i < numFrames && j < numAAs)
    {
        int boundframes = 0;
        for (int currWindow = 0; currWindow < window; ++currWindow)
        {
            int searchEnd = inTLLookup[i + currWindow + 1];
            for (int searchPos = inTLLookup[i + currWindow]; searchPos < searchEnd; searchPos += 2)
            {
                if (inFlatTimeline[searchPos] == j && inFlatTimeline[searchPos + 1] == currWater)
                {
                    boundframes++;
                }
            }
            //__syncthreads(); //Maybe this needs to go outside of the loop?
        }
        if (boundframes >= threshold)
        {
            outTimeline[(i * numAAs) + j] = 1;
        }
        else
        {
            outTimeline[(i * numAAs) + j] = 0;
        }
    }
}

cudaError_t timelineWindowCUDA(char * out, int * inFlatTimeline, int * inTLLookup, const int window, const int threshold, const int currWater, const int numAAs, 
    const int numframes, const int numTimeline, const int numTLLookup, cudaDeviceProp &deviceProp)
{
    // define device arrays
    int *dev_inFlatTimeline = 0;
    int *dev_inTLLookup = 0;
    char *dev_out = 0;
    cudaError_t cudaStatus;

    // Setup the kernel dimensions
    int blockDim = sqrt(deviceProp.maxThreadsPerBlock);
    auto blockSize = dim3(blockDim, blockDim);
    //Waters are chosen for x dimension, since CUDA can handle MUCH more data along the x dimension than y.
    auto gridSize = dim3(round((blockDim - 1 + numframes) / blockDim), round((blockDim - 1 + numAAs) / blockDim));

    // Allocate GPU buffers for vectors.
    cudaStatus = cudaMalloc((void**)&dev_out, numframes * numAAs * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_inFlatTimeline, numTimeline * sizeof(int));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_inTLLookup, numTLLookup * sizeof(int));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_inFlatTimeline, inFlatTimeline, numTimeline * sizeof(int), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_inTLLookup, inTLLookup, numTLLookup * sizeof(int), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU.
    //__global__ void timelineWindowKernel(char * outTimeline, int * inFlatTimeline, int * inTLLookup, const int window, const int threshold, const int currWater, const int numAAs, const int numFrames)
    timelineWindowKernel << <gridSize, blockSize >> > (dev_out, dev_inFlatTimeline, dev_inTLLookup, window, threshold, currWater, numAAs, numframes);

    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "Distance kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching hbond distance kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(out, dev_out, numframes * numAAs * sizeof(char), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // clear all our device arrays
Error:
    cudaFree(dev_inFlatTimeline);
    cudaFree(dev_inTLLookup);
    cudaFree(dev_out);

    return cudaStatus;
}

__global__ void visitListKernel(char * outVisitList, char * inTimeline, const int numAAs, const int numFrames)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < numAAs)
    {
        outVisitList[i] = 0;
        for (int currFrame = 0; currFrame < numFrames; ++currFrame)
        {
            if (inTimeline[(currFrame * numAAs) + i] == 1)
            {
                outVisitList[i] = 1;
            }
        }
    }
}

cudaError_t visitListCUDA(char * outVisitList, char * inTimeline, const int numAAs, const int numFrames, cudaDeviceProp &deviceProp)
{
    // the device arrays
    char * dev_outVisitList = 0;
    char * dev_inTimeline = 0;

    cudaError_t cudaStatus;

    // use div because it's more accurrate than the rounding BS
    auto gridDiv = div(numAAs, deviceProp.maxThreadsPerBlock);
    auto gridY = gridDiv.quot;

    // ass backwards way of rounding up (maybe use the same trick as above? It might be "faster")
    if (gridDiv.rem != 0)
        gridY++;

    // find the block and grid size
    auto blockSize = deviceProp.maxThreadsPerBlock;
    int gridSize = min(16 * deviceProp.multiProcessorCount, gridY);

    // Allocate GPU buffers for vectors
    cudaStatus = cudaMalloc((void**)&dev_outVisitList, numAAs * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_inTimeline, numFrames * numAAs * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_inTimeline, inTimeline, numFrames * numAAs * sizeof(char), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU. 
    //__global__ void visitListKernel(char * outVisitList, char * inTimeline, const int numAAs, const int numFrames)
    visitListKernel << <gridSize, blockSize >> > (dev_outVisitList, dev_inTimeline, numAAs, numFrames);
    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "Visit and bridger analysis kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching visit and bridger analysis kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }
    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(outVisitList, dev_outVisitList, numAAs * sizeof(char), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // delete all our device arrays
Error:
    cudaFree(dev_outVisitList);
    cudaFree(dev_inTimeline);

    return cudaStatus;
}

__global__ void eventListKernel(int * outTempEventList, char * inTimeline, const int numAAs, const int numFrames)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < numFrames)
    {
        int value = 0;
        for (int currAA = 0; currAA < numAAs; ++currAA)
        {
            if (inTimeline[(i * numAAs) + currAA] == 1)
            {
                ++value;
            }
        }
        outTempEventList[i] = value;
    }
}

cudaError_t eventListCUDA(int * outTempEventList, char * inTimeline, const int numAAs, const int numFrames, cudaDeviceProp &deviceProp)
{
    // the device arrays
    int * dev_outTempEventList = 0;
    char * dev_inTimeline = 0;

    cudaError_t cudaStatus;

    // use div because it's more accurrate than the rounding BS
    auto gridDiv = div(numFrames, deviceProp.maxThreadsPerBlock);
    auto gridY = gridDiv.quot;

    // ass backwards way of rounding up (maybe use the same trick as above? It might be "faster")
    if (gridDiv.rem != 0)
        gridY++;

    // find the block and grid size
    auto blockSize = deviceProp.maxThreadsPerBlock;
    int gridSize = min(16 * deviceProp.multiProcessorCount, gridY);

    // Allocate GPU buffers for vectors
    cudaStatus = cudaMalloc((void**)&dev_outTempEventList, numFrames * sizeof(int));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_inTimeline, numFrames * numAAs * sizeof(char));
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMalloc failed!" << endl;
        goto Error;
    }

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_inTimeline, inTimeline, numFrames * numAAs * sizeof(char), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // Launch a kernel on the GPU. 
    //__global__ void eventListKernel(int * outTempEventList, char * inTimeline, const int numAAs, const int numFrames)
    eventListKernel << <gridSize, blockSize >> > (dev_outTempEventList, dev_inTimeline, numAAs, numFrames);
    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        cerr << "Visit and bridger analysis kernel launch failed: " << cudaGetErrorString(cudaStatus) << endl;
        goto Error;
    }

    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaDeviceSynchronize returned error code " << cudaStatus << " after launching visit and bridger analysis kernel!" << endl;
        cout << "Cuda failure " << __FILE__ << ":" << __LINE__ << " '" << cudaGetErrorString(cudaStatus);
        goto Error;
    }
    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(outTempEventList, dev_outTempEventList, numFrames * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        cerr << "cudaMemcpy failed!" << endl;
        goto Error;
    }

    // delete all our device arrays
Error:
    cudaFree(dev_outTempEventList);
    cudaFree(dev_inTimeline);

    return cudaStatus;
}