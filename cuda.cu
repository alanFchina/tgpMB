// -*- C++ -*-


/*
 *  Cheng Ling
 *  s0897918@gmail.com 
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>
#include <stdarg.h>
#define cutilSafeCall(x) x
void cutilCheckMsg(const char * x){/*nothing*/}

#include "mb.h"
#include "gpu_mrbayes.h"


__constant__ int protein_hash_table[400] =
  {
    0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300, 320, 340, 360, 380,
    1, 21, 41, 61, 81, 101, 121, 141, 161, 181, 201, 221, 241, 261, 281, 301, 321, 341, 361, 381,
    2, 22, 42, 62, 82, 102, 122, 142, 162, 182, 202, 222, 242, 262, 282, 302, 322, 342, 362, 382,
    3, 23, 43, 63, 83, 103, 123, 143, 163, 183, 203, 223, 243, 263, 283, 303, 323, 343, 363, 383,
    4, 24, 44, 64, 84, 104, 124, 144, 164, 184, 204, 224, 244, 264, 284, 304, 324, 344, 364, 384,
    5, 25, 45, 65, 85, 105, 125, 145, 165, 185, 205, 225, 245, 265, 285, 305, 325, 345, 365, 385,
    6, 26, 46, 66, 86, 106, 126, 146, 166, 186, 206, 226, 246, 266, 286, 306, 326, 346, 366, 386,
    7, 27, 47, 67, 87, 107, 127, 147, 167, 187, 207, 227, 247, 267, 287, 307, 327, 347, 367, 387,
    8, 28, 48, 68, 88, 108, 128, 148, 168, 188, 208, 228, 248, 268, 288, 308, 328, 348, 368, 388,
    9, 29, 49, 69, 89, 109, 129, 149, 169, 189, 209, 229, 249, 269, 289, 309, 329, 349, 369, 389,
    10, 30, 50, 70, 90, 110, 130, 150, 170, 190, 210, 230, 250, 270, 290, 310, 330, 350, 370, 390,
    11, 31, 51, 71, 91, 111, 131, 151, 171, 191, 211, 231, 251, 271, 291, 311, 331, 351, 371, 391,
    12, 32, 52, 72, 92, 112, 132, 152, 172, 192, 212, 232, 252, 272, 292, 312, 332, 352, 372, 392,
    13, 33, 53, 73, 93, 113, 133, 153, 173, 193, 213, 233, 253, 273, 293, 313, 333, 353, 373, 393,
    14, 34, 54, 74, 94, 114, 134, 154, 174, 194, 214, 234, 254, 274, 294, 314, 334, 354, 374, 394,
    15, 35, 55, 75, 95, 115, 135, 155, 175, 195, 215, 235, 255, 275, 295, 315, 335, 355, 375, 395,
    16, 36, 56, 76, 96, 116, 136, 156, 176, 196, 216, 236, 256, 276, 296, 316, 336, 356, 376, 396,
    17, 37, 57, 77, 97, 117, 137, 157, 177, 197, 217, 237, 257, 277, 297, 317, 337, 357, 377, 397,
    18, 38, 58, 78, 98, 118, 138, 158, 178, 198, 218, 238, 258, 278, 298, 318, 338, 358, 378, 398,
    19, 39, 59, 79, 99, 119, 139, 159, 179, 199, 219, 239, 259, 279, 299, 319, 339, 359, 379, 399,
  };

/******************************/

#define MAX_GPU_COUNT      4
#ifdef MPI
extern int	proc_id;
#endif

#define USE_CHECK 0
//#define GC 4
//#define GC_LOADS (GC/4)

MrBFlt *rep_invCondLikes;
extern ModelInfo modelSettings[MAX_NUM_DIVS];

extern "C" void cudaStreamSync (int chain)
{
  
  cutilSafeCall(cudaStreamSynchronize(stream[chain]));
  cutilCheckMsg("cudaStreamSynchronize failed");
    
  if (cudaStreamQuery(stream[chain]) != cudaSuccess)
    {
      fprintf(stderr, "All operations in stream %d have not completed.\n", chain);
    }
}


extern "C" void cudaCheck(CLFlt *host, CLFlt *device, int chain)
{
  
  long i, k, a;
  MrBFlt result[4] = {0.0, 0.0, 0.0, 0.0};
  
  cutilSafeCall(cudaMemcpy((void *)host, (const void *)device, globaldevCondLikeRowSize* sizeof(CLFlt), cudaMemcpyDeviceToHost));
  cudaStreamSync(chain);


  for (a=0; a<globaldevChars; a++)
    {
      for (k=0; k<4; k++)
	{
	  for (i=0; i<20; i++)
	    {
	      if (a < numCompressedChars)
		{
		  result[k] += host[globaldevChars*(globalnumModelStates*k + i) + a];
		}
	    }
	}
    }
  printf("device: \n");
  for (k=0; k<4; k++)
    {
      printf("%lf ", result[k]);
    }

  printf("\n");
}


extern "C" int InitCUDAEnvironment (void)
{
  int dev, devCount;

  cutilSafeCall(cudaGetDeviceCount(&devCount));

  devCount = min(devCount, MAX_GPU_COUNT);
  
  if (devCount == 0)
    {
      printf("no CUDA-capable devices found.\n");
      return ERROR;
    }

  for (dev = 0; dev < devCount; ++dev) 
    {
      cudaDeviceProp deviceProp;
      cudaGetDeviceProperties(&deviceProp, dev);

      if (dev == 0)
	{
	  if (deviceProp.major == 9999 && deviceProp.minor == 9999)
	    printf("There is no device supporting CUDA.\n");
	  else if (devCount == 1)
	    {
#ifdef MPI
	    if (proc_id == 0)
	      printf("There is 1 device supporting CUDA\n");
#else
	    printf("There is 1 device supporting CUDA\n");
#endif
	    }
	  else
	    {
#ifdef MPI
	    if (proc_id == 0)
	      printf("There are %d devices supporting CUDA\n", devCount);
#else
	    printf("There are %d devices supporting CUDA\n", devCount);
#endif
	    }
        }
    }

#ifndef MPI

  cutilSafeCall(cudaSetDevice(0));

#else

  cutilSafeCall(cudaSetDevice(proc_id % devCount));

  printf("Process %d is using device %d.\n", proc_id, proc_id % devCount);
#endif

  cutilCheckMsg("cudaSetDevice failed");	

  return NO_ERROR;
}

__device__ void gpu_scale_clP(CLFlt *clP, int clp_idx, CLFlt scaler, int numChars)
{
  CLFlt r_scaler;
  int idx;
  #pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
    }
}

__global__ void gpu_scaler_3_gammaCats_4(CLFlt *clP, CLFlt *lnScaler, CLFlt *scPOld, CLFlt *scPNew/*, int numChars*/)
{
  int gammaCat, tid_y, modelStat, tid, char_offset, char_idx, clp_idx, temp, idx;
  CLFlt treeScaler, nodeScalerOld, scaler=0.0, r_scaler; 

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  char_offset = 64*blockIdx.x;
  clp_idx = temp = char_idx = char_offset + tid;

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler) 
	scaler = r_scaler;

      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler)
	scaler = r_scaler;

      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler)
	scaler = r_scaler;

      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler)
	scaler = r_scaler;
    }

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

    }

  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  treeScaler -= nodeScalerOld;
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 
}

extern "C" void scaler_3 (int offset_clP, int offset_lnScaler, int offset_scPOld, int offset_scPNew, int modelnumChars, int modelnumGammaCats, int chain)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_scaler_3_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes + offset_clP, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld, devnodeScalerSpace+offset_scPNew);
}

extern "C" int cudaMallocAll_protein (int numCharsperBlock)
{
  ModelInfo *m ;
  m = &modelSettings[0];

  int fix=8;
  if (numCharsperBlock % fix)
    {
      printf("numCharsperBlock should be a multiple of %d;\n", fix);
      return ERROR;
    }

  int i, j, g, k, numResidues=0, numDummyChars=0;
  if (numCompressedChars <= 0)
    {
      printf("error: numCompressedChars: %d\n", numCompressedChars);
      return ERROR;
    }
  else
    {
      numResidues = numCompressedChars % numCharsperBlock;
      numDummyChars = numCharsperBlock - numResidues;
      if (numDummyChars == numCharsperBlock)
	numDummyChars = 0;
      
      globaldevChars = numCompressedChars+numDummyChars;
      if (globaldevChars % numCharsperBlock)
	{
	  fprintf(stderr, "devicenumChars: %d numCharsperBlock: %d\n", globaldevChars, numCharsperBlock);
	  return ERROR;
	}
    }
  
  if (globalnumGammaCats != 4)
    {
      fprintf(stderr, "tgMC++.g4 only supports modelnumGammaCats=4, please try other versions. exit;\n");
      return ERROR;
    }

  blockDim_z = numCharsperBlock;
  if (numCharsperBlock != 64)
    {
      fprintf(stderr, "numCharsperBlock != 64\n");
      return ERROR;
    }

  gridDim_x = globaldevChars/blockDim_z;
  if (globaldevChars % blockDim_z)
    {
      fprintf(stderr, "error: globaldevChars;\n");
      return ERROR;
    }

  if (globaldevChars < numCompressedChars)
    {
      fprintf(stderr, "error: globaldevChars < numCompressedChars\n");
      return ERROR;
    }

  globaldevCondLikeRowSize = globaldevChars*globalnumGammaCats*globalnumModelStates;
  globaldevCondLikeLength = globaldevCondLikeRowSize*2;

  /* CL for testing*/
  cutilSafeCall(cudaMalloc((void **)&devCL, globaldevCondLikeRowSize * sizeof(CLFlt)));
  hostCL = (CLFlt *)calloc (globaldevCondLikeRowSize, sizeof(CLFlt));

    /* conditional likelihoods */
  cutilSafeCall(cudaMalloc((void **)&devCondLikes, numCondLikes * globaldevCondLikeLength * sizeof(CLFlt)));

  //printf("numCondLikes: %d\n", numCondLikes);
  
  if (numDummyChars)
    {
      CLFlt *rep_condLikes = NULL;
      for (i=0; i<numCondLikes; i++)
	{
	  rep_condLikes = (CLFlt *)calloc (globaldevCondLikeRowSize, sizeof(CLFlt));
	  for(j=0; j<numCompressedChars; j++)
	    {
	      for (g=0; g<globalnumGammaCats; g++)
		{
		  for (k=0; k<globalnumModelStates; k++)
		    {
		      rep_condLikes[globaldevChars*(globalnumModelStates*g + k) + j] =
			condLikes[i][globalnumModelStates*globalnumGammaCats*j + globalnumModelStates*g + k];
		    }
		}
	    }

	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength+0*globaldevCondLikeRowSize), 
				   (const void *)rep_condLikes,
				   globaldevCondLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));
	  free(rep_condLikes);

	  rep_condLikes = (CLFlt *)calloc (globaldevCondLikeRowSize, sizeof(CLFlt));
	  CLFlt *p_condLikes = condLikes[i] + condLikeRowSize;
	  for(j=0; j<numCompressedChars; j++)
	    {
	      for (g=0; g<globalnumGammaCats; g++)
		{
		  for (k=0; k<globalnumModelStates; k++)
		    {
		      rep_condLikes[globaldevChars*(globalnumModelStates*g + k) + j] =
			p_condLikes[globalnumModelStates*globalnumGammaCats*j + globalnumModelStates*g + k];
		    }
		  
		  /*
		  rep_condLikes[globaldevChars*(4*g + 0) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 0];
		  
		  rep_condLikes[globaldevChars*(4*g + 1) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 1];

		  rep_condLikes[globaldevChars*(4*g + 2) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 2];

		  rep_condLikes[globaldevChars*(4*g + 3) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 3];
		  */
		}
	    }
	    
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength+1*globaldevCondLikeRowSize), 
				   (const void *)rep_condLikes,
				   globaldevCondLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));
	    
	  free(rep_condLikes);	  
	  /*
	  // 1st segment 
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength), 
				   (const void *)condLikes[i],
				   condLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));

	  // 2nd segment
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength+globaldevCondLikeRowSize), 
				   (const void *)(condLikes[i] + condLikeRowSize),
				   condLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));
	  */
	}

    }
  else
    {
      printf("!numDummyChars\n"); exit(1);
    }

  /* terminal states */
  cutilSafeCall(cudaMalloc((void **)&devtermState, numLocalTaxa*globaldevChars*sizeof(int)));
  if (numDummyChars)
    {
      int *temp = (int *)calloc (numDummyChars, sizeof(int));
      for (i=0; i<numLocalTaxa; i++)
	{
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devtermState+i*globaldevChars),
				   (const void *)(termState+i*numCompressedChars),
				   numCompressedChars*sizeof(int), 
				   cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy(
				   (void *)(devtermState+i*globaldevChars+numCompressedChars),
				   (const void *)temp,
				   numDummyChars*sizeof(int), 
				   cudaMemcpyHostToDevice));
	  
	}
      free (temp);
    }
  else
    {
      printf("!numDummyChars\n"); exit(1);      
    }

  /* tiProbs */
  cutilSafeCall(cudaMalloc((void **)&devtiProbSpace, numLocalChains*globalnNodes*2*tiProbRowSize *sizeof(CLFlt)));


  if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devnodeScalerSpace, numLocalChains*globalnScalerNodes*2*globaldevChars*sizeof(CLFlt)));
      
      CLFlt *ptr_dev=NULL, *ptr_host=NULL;
      CLFlt *temp = (CLFlt *) calloc (numDummyChars, sizeof (CLFlt));
      for (i=0; i<numLocalChains; i++)
	{
	  ptr_dev = devnodeScalerSpace+i*globalnScalerNodes*2*globaldevChars;
	  ptr_host= nodeScalerSpace+i*globalnScalerNodes*2*numCompressedChars;
	  for (j=0; j<globalnScalerNodes; j++)
	    {
	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+j*2*globaldevChars),
				       (const void *)(ptr_host+j*2*numCompressedChars),
				       numCompressedChars*sizeof(CLFlt),
				       cudaMemcpyHostToDevice));

	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+(j*2+1)*globaldevChars),
				       (const void *)(ptr_host+(j*2+1)*numCompressedChars),
				       numCompressedChars*sizeof(CLFlt),
				       cudaMemcpyHostToDevice));

	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+j*2*globaldevChars+numCompressedChars),
				       (const void *)temp,
				       numDummyChars*sizeof(CLFlt),
				       cudaMemcpyHostToDevice));

	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+(j*2+1)*globaldevChars+numCompressedChars),
				       (const void *)temp,
				       numDummyChars*sizeof(CLFlt),
				       cudaMemcpyHostToDevice));
	    }
	}
      free (temp);

    }
  else 
    {

      printf("!numDummyChars\n"); exit(1);
      /*
      cutilSafeCall(cudaMalloc((void **)&devnodeScalerSpace, numLocalChains*globalnScalerNodes*2*numCompressedChars*sizeof(CLFlt)));

      cutilSafeCall(cudaMemcpy((void *)devnodeScalerSpace, (const void *)nodeScalerSpace, numLocalChains*globalnScalerNodes*2*numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
      */
    }


    if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devtreeScalerSpace, numLocalChains*2*globaldevChars*sizeof(CLFlt)));

      CLFlt *ptr_dev=NULL, *ptr_host=NULL;
      CLFlt *temp = (CLFlt *) calloc (numDummyChars, sizeof (CLFlt));

      for (i=0; i<numLocalChains; i++)
	{
	  ptr_dev = devtreeScalerSpace+i*2*globaldevChars; 
	  ptr_host= treeScalerSpace+i*2*numCompressedChars;
	  cutilSafeCall(cudaMemcpy((void *)ptr_dev, (const void *)ptr_host, numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy((void *)(ptr_dev+globaldevChars), (const void *)(ptr_host+numCompressedChars), numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy((void *)(ptr_dev+numCompressedChars), (const void *)temp, numDummyChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy((void *)(ptr_dev+globaldevChars+numCompressedChars), (const void *)temp, numDummyChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
	}
      free (temp);
      
    }
  else 
    {
  cutilSafeCall(cudaMalloc((void **)&devtreeScalerSpace, numLocalChains*2*numCompressedChars*sizeof(CLFlt)));
	cutilSafeCall(cudaMemcpy((void *)devtreeScalerSpace, (const void *)treeScalerSpace, numLocalChains*2*numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
    }	    


  /* invariable sites */
  if (numDummyChars)
    {
      if (m->pInvar != NULL)
	{

      globaldevInvCondLikeSize = globaldevChars*globalnumModelStates;
      cutilSafeCall(cudaMalloc((void **)&devinvCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt)));

      rep_invCondLikes = (MrBFlt *)calloc (globaldevInvCondLikeSize-(numCompressedChars*globalnumModelStates), sizeof(MrBFlt));
      
	/*
      for (i=0; i<globalnumModelStates; i++)
	{
	  for (j=0; j<globaldevChars; j++)
	    {
	      if (j< numCompressedChars)
		rep_invCondLikes[globaldevChars*i + j] = invCondLikes[4*j + i];
	      else
		rep_invCondLikes[globaldevChars*i + j] = 0.0;
	    }
	}
	*/
      cutilSafeCall(cudaMemcpy((void *)devinvCondLikes, (const void *)invCondLikes, (numCompressedChars*globalnumModelStates)*sizeof(MrBFlt), cudaMemcpyHostToDevice));

      cutilSafeCall(cudaMemcpy((void *)(devinvCondLikes+numCompressedChars*globalnumModelStates),
			       (const void *)rep_invCondLikes,
			       (globaldevInvCondLikeSize - numCompressedChars*globalnumModelStates)*sizeof(MrBFlt),
			       cudaMemcpyHostToDevice));
      
      free (rep_invCondLikes);
	}
    }
  else
    {
      printf("numDummyChars\n"); exit(1);
      
      if (m->pInvar != NULL)
	{
	  /*
      globaldevInvCondLikeSize = globaldevChars*globalnumModelStates;
      cutilSafeCall(cudaMalloc((void **)&devinvCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt)));

      rep_invCondLikes = (MrBFlt *)calloc (globaldevInvCondLikeSize, sizeof (MrBFlt));
      
      for (i=0; i<globalnumModelStates; i++)
	{
	  for (j=0; j<globaldevChars; j++)
	    {
	      if (j< numCompressedChars)
		rep_invCondLikes[globaldevChars*i + j] = invCondLikes[4*j + i];
	      else
		rep_invCondLikes[globaldevChars*i + j] = 0.0;
	    }
	}

      cutilSafeCall(cudaMemcpy((void *)devinvCondLikes, (const void *)rep_invCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt), cudaMemcpyHostToDevice));
      free (rep_invCondLikes);
	  */
	}
    }

    /* devlnL */
    if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devlnL, numLocalChains * globaldevChars * sizeof(MrBFlt)));
      cutilSafeCall(cudaMallocHost((void **)&globallnL, numLocalChains * globaldevChars * sizeof(MrBFlt)));
    }
  else
    {
      cutilSafeCall(cudaMalloc((void **)&devlnL, numLocalChains * numCompressedChars* sizeof(MrBFlt)));
      cutilSafeCall(cudaMallocHost((void **)&globallnL, numLocalChains * numCompressedChars * sizeof(MrBFlt)));
    }


   /* numSitesOfPat*/
  if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devnumSitesOfPat, globaldevChars*chainParams.numChains*sizeof(MrBFlt)));

      MrBFlt *temp = (MrBFlt *) calloc (globaldevChars-numCompressedChars, sizeof(MrBFlt));
      CLFlt *ptr_dev=NULL, *ptr_host=NULL;
      for (i=0; i<chainParams.numChains; i++)
	{
	  ptr_dev = devnumSitesOfPat+i*globaldevChars;
	  ptr_host= numSitesOfPat+i*numCompressedChars;
      cutilSafeCall(cudaMemcpy((void *)ptr_dev, (const void *)ptr_host, numCompressedChars*sizeof(MrBFlt), cudaMemcpyHostToDevice));

      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+numCompressedChars), (const void *)temp, (globaldevChars-numCompressedChars)*sizeof(MrBFlt), cudaMemcpyHostToDevice));
	}


    }
  else
    {
      cutilSafeCall(cudaMalloc((void **)&devnumSitesOfPat, numCompressedChars*chainParams.numChains*sizeof(MrBFlt)));
      cutilSafeCall(cudaMemcpy((void *)devnumSitesOfPat, (const void *)numSitesOfPat, numCompressedChars*chainParams.numChains*sizeof(MrBFlt), cudaMemcpyHostToDevice));
    }


  /* device baseFreqSpace */
  cutilSafeCall(cudaMalloc((void **)&devBaseFreq, globalnumModelStates * numLocalChains * sizeof(MrBFlt)));
  
  
    
  /* streams */
  stream = (cudaStream_t *) calloc (numLocalChains, sizeof(cudaStream_t));

  for (i=0; i<numLocalChains; i++)
    {
      cutilSafeCall(cudaStreamCreate(&stream[i]));
      cutilCheckMsg("cudaStreamCreate failed");
    }
  return NO_ERROR;

  
}

extern "C" int cudaMallocAll (int numCharsperBlock)
{
  ModelInfo *m ;
  m = &modelSettings[0];

  int fix=8;
  if (numCharsperBlock % fix)
    {
      printf("numCharsperBlock should be a multiple of %d;\n", fix);
      return ERROR;
    }

  int i, j, g, numResidues=0, numDummyChars=0;
  if (numCompressedChars <= 0)
    {
      printf("error: numCompressedChars: %d\n", numCompressedChars);
      return ERROR;
    }
  else
    {
      numResidues = numCompressedChars % numCharsperBlock;
      numDummyChars = numCharsperBlock - numResidues;
      if (numDummyChars == numCharsperBlock)
	numDummyChars = 0;
      
      globaldevChars = numCompressedChars+numDummyChars;
      if (globaldevChars % numCharsperBlock)
	{
	  fprintf(stderr, "devicenumChars: %d numCharsperBlock: %d\n", globaldevChars, numCharsperBlock);
	  return ERROR;
	}
    }
  
  if (globalnumGammaCats != 4)
    {
      fprintf(stderr, "tgMC++.g4 only supports modelnumGammaCats=4, please try other versions. exit;\n");
      return ERROR;
    }

  blockDim_z = numCharsperBlock;
  if (numCharsperBlock != 64)
    {
      fprintf(stderr, "numCharsperBlock != 64\n");
      return ERROR;
    }

  gridDim_x = globaldevChars/blockDim_z;
  if (globaldevChars % blockDim_z)
    {
      fprintf(stderr, "error: globaldevChars;\n");
      return ERROR;
    }

  if (globaldevChars < numCompressedChars)
    {
      fprintf(stderr, "error: globaldevChars < numCompressedChars\n");
      return ERROR;
    }

  globaldevCondLikeRowSize = globaldevChars*globalnumGammaCats*globalnumModelStates;
  globaldevCondLikeLength = globaldevCondLikeRowSize*2;




#if 1

  printf("globaldevCondLikeRowSize: %d globaldevChars: %d globalnumModelStates: %d \n",
	 globaldevCondLikeRowSize, globaldevChars, globalnumModelStates);
  
#endif
  
  
  /* conditional likelihoods */
  cutilSafeCall(cudaMalloc((void **)&devCondLikes, numCondLikes * globaldevCondLikeLength * sizeof(CLFlt)));
  if (numDummyChars)
    {
      CLFlt *rep_condLikes = NULL;
      for (i=0; i<numCondLikes; i++)
	{
	  rep_condLikes = (CLFlt *)calloc (globaldevCondLikeRowSize, sizeof(CLFlt));
	  for(j=0; j<numCompressedChars; j++)
	    {
	      for (g=0; g<globalnumGammaCats; g++)
		{
		  rep_condLikes[globaldevChars*(4*g + 0) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 0];
		  
		  rep_condLikes[globaldevChars*(4*g + 1) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 1];

		  rep_condLikes[globaldevChars*(4*g + 2) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 2];

		  rep_condLikes[globaldevChars*(4*g + 3) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 3];
		}
	    }

	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength+0*globaldevCondLikeRowSize), 
				   (const void *)rep_condLikes,
				   globaldevCondLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));
	  free(rep_condLikes);

	  rep_condLikes = (CLFlt *)calloc (globaldevCondLikeRowSize, sizeof(CLFlt));
	  CLFlt *p_condLikes = condLikes[i] + condLikeRowSize;
	  for(j=0; j<numCompressedChars; j++)
	    {
	      for (g=0; g<globalnumGammaCats; g++)
		{
		  rep_condLikes[globaldevChars*(4*g + 0) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 0];
		  
		  rep_condLikes[globaldevChars*(4*g + 1) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 1];

		  rep_condLikes[globaldevChars*(4*g + 2) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 2];

		  rep_condLikes[globaldevChars*(4*g + 3) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 3];
		}
	    }
	    
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength+1*globaldevCondLikeRowSize), 
				   (const void *)rep_condLikes,
				   globaldevCondLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));
	    
	  free(rep_condLikes);
	  


	}

      
    }
  else
    {
      CLFlt *rep_condLikes=NULL;
      for (i=0; i<numCondLikes; i++)
	{
	  rep_condLikes = (CLFlt *)calloc (condLikeRowSize, sizeof(CLFlt));

	  for(j=0; j<numCompressedChars; j++)
	    {
	      for (g=0; g<globalnumGammaCats; g++)
		{
		  rep_condLikes[globaldevChars*(4*g + 0) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 0];
		  
		  rep_condLikes[globaldevChars*(4*g + 1) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 1];

		  rep_condLikes[globaldevChars*(4*g + 2) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 2];

		  rep_condLikes[globaldevChars*(4*g + 3) + j] = 
		    condLikes[i][4*globalnumGammaCats*j + 4*g + 3];
		}
	    }


	  cutilSafeCall(cudaMemcpy((void *)(devCondLikes+i*condLikeLength), 
				   (const void *)rep_condLikes,
				   condLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));

	  free (rep_condLikes);

	  rep_condLikes = (CLFlt *)calloc (condLikeRowSize, sizeof(CLFlt));
	  CLFlt *p_condLikes = condLikes[i] + condLikeRowSize;
	  for(j=0; j<numCompressedChars; j++)
	    {
	      for (g=0; g<globalnumGammaCats; g++)
		{
		  rep_condLikes[globaldevChars*(4*g + 0) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 0];
		  
		  rep_condLikes[globaldevChars*(4*g + 1) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 1];

		  rep_condLikes[globaldevChars*(4*g + 2) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 2];

		  rep_condLikes[globaldevChars*(4*g + 3) + j] = 
		    p_condLikes[4*globalnumGammaCats*j + 4*g + 3];
		}
	    }
	    
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devCondLikes+i*globaldevCondLikeLength+1*globaldevCondLikeRowSize), 
				   (const void *)rep_condLikes,
				   condLikeRowSize*sizeof(CLFlt), 
				   cudaMemcpyHostToDevice));
	    
	  free(rep_condLikes);

	}		
    }

  printf("numLocalTaxa: %d\n", numLocalTaxa);
  /* terminal states */
  cutilSafeCall(cudaMalloc((void **)&devtermState, numLocalTaxa*globaldevChars*sizeof(int)));
  if (numDummyChars)
    {
      int *temp = (int *)calloc (numDummyChars, sizeof(int));
      for (i=0; i<numLocalTaxa; i++)
	{
	  cutilSafeCall(cudaMemcpy(
				   (void *)(devtermState+i*globaldevChars),
				   (const void *)(termState+i*numCompressedChars),
				   numCompressedChars*sizeof(int), 
				   cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy(
				   (void *)(devtermState+i*globaldevChars+numCompressedChars),
				   (const void *)temp,
				   numDummyChars*sizeof(int), 
				   cudaMemcpyHostToDevice));
	  
	}
      free (temp);
    }
  else
    {
  cutilSafeCall(cudaMemcpy((void *)devtermState, (const void *)termState, numLocalTaxa*numCompressedChars*sizeof(int), cudaMemcpyHostToDevice));
    }

  cutilSafeCall(cudaMalloc((void **)&devtiProbSpace, numLocalChains*globalnNodes*2*tiProbRowSize *sizeof(CLFlt)));

  if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devnodeScalerSpace, numLocalChains*globalnScalerNodes*2*globaldevChars*sizeof(CLFlt)));

      CLFlt *ptr_dev=NULL, *ptr_host=NULL;
      CLFlt *temp = (CLFlt *) calloc (numDummyChars, sizeof (CLFlt));
      for (i=0; i<numLocalChains; i++)
	{
	  ptr_dev = devnodeScalerSpace+i*globalnScalerNodes*2*globaldevChars;
	  ptr_host= nodeScalerSpace+i*globalnScalerNodes*2*numCompressedChars;
	  for (j=0; j<globalnScalerNodes; j++)
	    {
	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+j*2*globaldevChars), (const void *)(ptr_host+j*2*numCompressedChars), numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+(j*2+1)*globaldevChars), (const void *)(ptr_host+(j*2+1)*numCompressedChars), numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+j*2*globaldevChars+numCompressedChars), (const void *)temp, numDummyChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+(j*2+1)*globaldevChars+numCompressedChars), (const void *)temp, numDummyChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
	    }
	}
      free (temp);

    }
  else 
    {   
      cutilSafeCall(cudaMalloc((void **)&devnodeScalerSpace, numLocalChains*globalnScalerNodes*2*numCompressedChars*sizeof(CLFlt)));

      cutilSafeCall(cudaMemcpy((void *)devnodeScalerSpace, (const void *)nodeScalerSpace, numLocalChains*globalnScalerNodes*2*numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
    }

  if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devtreeScalerSpace, numLocalChains*2*globaldevChars*sizeof(CLFlt)));

      CLFlt *ptr_dev=NULL, *ptr_host=NULL;
      CLFlt *temp = (CLFlt *) calloc (numDummyChars, sizeof (CLFlt));

      for (i=0; i<numLocalChains; i++)
	{
	  ptr_dev = devtreeScalerSpace+i*2*globaldevChars; 
	  ptr_host= treeScalerSpace+i*2*numCompressedChars;
	  cutilSafeCall(cudaMemcpy((void *)ptr_dev, (const void *)ptr_host, numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy((void *)(ptr_dev+globaldevChars), (const void *)(ptr_host+numCompressedChars), numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy((void *)(ptr_dev+numCompressedChars), (const void *)temp, numDummyChars*sizeof(CLFlt), cudaMemcpyHostToDevice));

	  cutilSafeCall(cudaMemcpy((void *)(ptr_dev+globaldevChars+numCompressedChars), (const void *)temp, numDummyChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
	}
      free (temp);
      
    }
  else 
    {
  cutilSafeCall(cudaMalloc((void **)&devtreeScalerSpace, numLocalChains*2*numCompressedChars*sizeof(CLFlt)));
	cutilSafeCall(cudaMemcpy((void *)devtreeScalerSpace, (const void *)treeScalerSpace, numLocalChains*2*numCompressedChars*sizeof(CLFlt), cudaMemcpyHostToDevice));
    }	    

  /* invariable sites */
  if (numDummyChars)
    {
      if (m->pInvar != NULL)
	{

      globaldevInvCondLikeSize = globaldevChars*globalnumModelStates;
      cutilSafeCall(cudaMalloc((void **)&devinvCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt)));

      rep_invCondLikes = (MrBFlt *)calloc (globaldevInvCondLikeSize, sizeof (MrBFlt));
      
      for (i=0; i<globalnumModelStates; i++)
	{
	  for (j=0; j<globaldevChars; j++)
	    {
	      if (j< numCompressedChars)
		rep_invCondLikes[globaldevChars*i + j] = invCondLikes[4*j + i];
	      else
		rep_invCondLikes[globaldevChars*i + j] = 0.0;
	    }
	}

      cutilSafeCall(cudaMemcpy((void *)devinvCondLikes, (const void *)rep_invCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt), cudaMemcpyHostToDevice));
      free (rep_invCondLikes);
	}
    }
  else
    {

      if (m->pInvar != NULL)
	{

      globaldevInvCondLikeSize = globaldevChars*globalnumModelStates;
      cutilSafeCall(cudaMalloc((void **)&devinvCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt)));

      rep_invCondLikes = (MrBFlt *)calloc (globaldevInvCondLikeSize, sizeof (MrBFlt));
      
      for (i=0; i<globalnumModelStates; i++)
	{
	  for (j=0; j<globaldevChars; j++)
	    {
	      if (j< numCompressedChars)
		rep_invCondLikes[globaldevChars*i + j] = invCondLikes[4*j + i];
	      else
		rep_invCondLikes[globaldevChars*i + j] = 0.0;
	    }
	}

      cutilSafeCall(cudaMemcpy((void *)devinvCondLikes, (const void *)rep_invCondLikes, globaldevInvCondLikeSize*sizeof(MrBFlt), cudaMemcpyHostToDevice));
      free (rep_invCondLikes);
	}

    }

  if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devlnL, numLocalChains * globaldevChars * sizeof(MrBFlt)));
      cutilSafeCall(cudaMallocHost((void **)&globallnL, numLocalChains * globaldevChars * sizeof(MrBFlt)));
    }
  else
    {
      cutilSafeCall(cudaMalloc((void **)&devlnL, numLocalChains * numCompressedChars* sizeof(MrBFlt)));
      cutilSafeCall(cudaMallocHost((void **)&globallnL, numLocalChains * numCompressedChars * sizeof(MrBFlt)));
    }

  if (numDummyChars)
    {
      cutilSafeCall(cudaMalloc((void **)&devnumSitesOfPat, globaldevChars*chainParams.numChains*sizeof(MrBFlt)));

      MrBFlt *temp = (MrBFlt *) calloc (globaldevChars-numCompressedChars, sizeof(MrBFlt));
      CLFlt *ptr_dev=NULL, *ptr_host=NULL;
      for (i=0; i<chainParams.numChains; i++)
	{
	  ptr_dev = devnumSitesOfPat+i*globaldevChars;
	  ptr_host= numSitesOfPat+i*numCompressedChars;
      cutilSafeCall(cudaMemcpy((void *)ptr_dev, (const void *)ptr_host, numCompressedChars*sizeof(MrBFlt), cudaMemcpyHostToDevice));

      cutilSafeCall(cudaMemcpy((void *)(ptr_dev+numCompressedChars), (const void *)temp, (globaldevChars-numCompressedChars)*sizeof(MrBFlt), cudaMemcpyHostToDevice));
	}


    }
  else
    {
      cutilSafeCall(cudaMalloc((void **)&devnumSitesOfPat, numCompressedChars*chainParams.numChains*sizeof(MrBFlt)));
      cutilSafeCall(cudaMemcpy((void *)devnumSitesOfPat, (const void *)numSitesOfPat, numCompressedChars*chainParams.numChains*sizeof(MrBFlt), cudaMemcpyHostToDevice));
    }
  //stream = (cudaStream_t *) calloc (numLocalChains, sizeof(cudaStream_t));

  stream = (cudaStream_t *) calloc (numLocalChains, sizeof(cudaStream_t));

  for (i=0; i<numLocalChains; i++)
    {
      cutilSafeCall(cudaStreamCreate(&stream[i]));
      cutilCheckMsg("cudaStreamCreate failed");
    }
  return NO_ERROR;
}


extern "C" void cudaMemcpyAsyncBaseFreqSpace (MrBFlt *bs, int bs_length, int chain)
{
  cutilSafeCall(cudaMemcpyAsync((void *)(devBaseFreq + chain * bs_length), (const void *)(bs), bs_length * sizeof(MrBFlt), cudaMemcpyHostToDevice, stream[chain]));

}

extern "C" void cudaMemcpyAsyncgloballnL (int chain)
{
  cutilSafeCall(cudaMemcpyAsync((void *)(globallnL + chain * globaldevChars), (const void *)(devlnL + chain * globaldevChars), globaldevChars* sizeof(MrBFlt), cudaMemcpyDeviceToHost, stream[chain]));
}

extern "C" void cudaMemcpyAsynctiProbSpace (int chain)
{
  cutilSafeCall(cudaMemcpyAsync((void *)(devtiProbSpace+chain*globalnNodes*2*tiProbRowSize), (const void *)(tiProbSpace+chain*globalnNodes*2*tiProbRowSize), globalnNodes*2*tiProbRowSize*sizeof(CLFlt), cudaMemcpyHostToDevice, stream[chain]));
}

extern "C" void cudaMemcpyAsynctreeScalerSpace (int offset_fromState, int offset_toState, int chain)
{
  cutilSafeCall(cudaMemcpyAsync((void *)(devtreeScalerSpace + offset_toState), (const void *)(devtreeScalerSpace + offset_fromState), globaldevChars*sizeof(CLFlt), cudaMemcpyDeviceToDevice, stream[chain]));
}

extern "C" void cudaHostAllocWriteCombinedtiProbSpace (size_t size)
{
  cutilSafeCall(cudaHostAlloc((void **)&tiProbSpace, size, cudaHostAllocWriteCombined));

  if(!tiProbSpace)
    printf("error gpu\n");
}



__global__ void gpu_root_0_gammaCats_4 (CLFlt *clP, CLFlt *clL, CLFlt *clR, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, idx, clp_idx, temp, state_idx, ai;
  CLFlt *m_preLikeA, *m_tiPL, *m_tiPR, la, lc, lg, lt, ra, rc, rg, rt, xa, xc, xg, xt;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat;
  clp_idx = 64*blockIdx.x + tid;
  temp = clp_idx;
  state_idx = clp_idx;

  ai = aState[state_idx];

  __shared__ CLFlt s_tiPL[64];
  __shared__ CLFlt s_tiPR[64];
  s_tiPL[tid] = tiPL[tid];
  s_tiPR[tid] = tiPR[tid];
  
  __shared__ CLFlt s_preLikeA[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeA[spreLike_idx] = tiPA[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeA[spreLike_idx] = 1.0f;
    }
  
  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;
  
  __syncthreads();
  
#pragma unroll 

  for (idx=0; idx<numGammaCats; idx++)
    {
      m_preLikeA = &s_preLikeA[20*idx + ai];
      m_tiPL = &s_tiPL[16*idx];
      m_tiPR = &s_tiPR[16*idx];

      la = clL[temp]; 
      ra = clR[temp]; 
      temp += numChars;

      lc = clL[temp];
      rc = clR[temp];
      temp += numChars;

      lg = clL[temp];
      rg = clR[temp];
      temp += numChars;

      lt = clL[temp];
      rt = clR[temp];
      temp += numChars;

      xa = (ra*m_tiPR[0] + rc*m_tiPR[1] + rg*m_tiPR[2] + rt*m_tiPR[3])*m_preLikeA[0];
      xc = (ra*m_tiPR[4] + rc*m_tiPR[5] + rg*m_tiPR[6] + rt*m_tiPR[7])*m_preLikeA[1];
      xg = (ra*m_tiPR[8] + rc*m_tiPR[9] + rg*m_tiPR[10] + rt*m_tiPR[11])*m_preLikeA[2];
      xt = (ra*m_tiPR[12] + rc*m_tiPR[13] + rg*m_tiPR[14] + rt*m_tiPR[15])*m_preLikeA[3];

      clP[clp_idx] = (la*m_tiPL[0] + lc*m_tiPL[1] + lg*m_tiPL[2] + lt*m_tiPL[3]) * xa;
      clp_idx += numChars;

      clP[clp_idx] = (la*m_tiPL[4] + lc*m_tiPL[5] + lg*m_tiPL[6] + lt*m_tiPL[7]) * xc;
      clp_idx += numChars;

      clP[clp_idx] = (la*m_tiPL[8] + lc*m_tiPL[9] + lg*m_tiPL[10] + lt*m_tiPL[11]) * xg;
      clp_idx += numChars;

      clP[clp_idx] = (la*m_tiPL[12] + lc*m_tiPL[13] + lg*m_tiPL[14] + lt*m_tiPL[15]) * xt;
      clp_idx += numChars;
    }
}

extern "C" void root_0(int offset_clP, int offset_clL, int offset_clR, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_root_0_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA);
}


__global__ void gpu_root_4_gen (CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *clA, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;  
  int gamma = threadIdx.y;  
  int state_idx = 64 * gid + tid;
  int h, i, j;

  CLFlt likeL, likeR, likeA;

  i = (20*numChars)*gamma + state_idx;
  CLFlt *p_clL = clL + i;
  CLFlt *p_clR = clR + i;
  CLFlt *p_clA = clA + i;
  CLFlt *p_clP = clP + i;    

  __shared__ CLFlt s_tiPL[4*400];
  __shared__ CLFlt s_tiPR[4*400];
  __shared__ CLFlt s_tiPA[4*400]; 

  i = gamma*400;
  CLFlt *p_s_tiPL = s_tiPL + i;
  CLFlt *p_s_tiPR = s_tiPR + i;
  CLFlt *p_s_tiPA = s_tiPA + i;
  
  CLFlt *p_tiPL = tiPL + i;
  CLFlt *p_tiPR = tiPR + i;
  CLFlt *p_tiPA = tiPA + i;    
  
  for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      p_s_tiPL[h] = p_tiPL[h];
      p_s_tiPR[h] = p_tiPR[h];
      p_s_tiPA[h] = p_tiPA[h];                  
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      p_s_tiPL[h] = p_tiPL[h];      
      p_s_tiPR[h] = p_tiPR[h];
      p_s_tiPA[h] = p_tiPA[h];                        
    }
  
  __syncthreads();

  for (i=0; i<20; i++)
    {
      likeR = 0.0;
      likeL = 0.0;
      likeA = 0.0;
      
      for (j=0; j<20; j++)
	{
	  likeL += p_s_tiPL[h] * p_clL[j*numChars];
	  likeR += p_s_tiPR[h] * p_clR[j*numChars];
	  likeA += p_s_tiPA[h] * p_clA[j*numChars];
	  h ++;
	}
      
      p_clP[i*numChars] = likeR * likeL * likeA;
    }
}


extern "C" void root_4_gen(int offset_clP, int offset_clL, int offset_clR, int offset_clA, int offset_pL, int offset_pR, int offset_pA, int chain,int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(64, 4);

  gpu_root_4_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devCondLikes+offset_clA, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA, globaldevChars);
}

__global__ void gpu_root_3_gen (CLFlt *clP, int *lState, int *rState, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;  
  int gamma = threadIdx.y;
  int h, i, j;
  int state_idx = 64 * gid + tid;  
  int a = aState[state_idx];
  int l = lState[state_idx];
  int r = rState[state_idx];

  i = (20*numChars)*gamma + state_idx;
  CLFlt *p_clP = clP + i;

  __shared__ CLFlt s_tiPL[4*420];
  __shared__ CLFlt s_tiPR[4*420];
  __shared__ CLFlt s_tiPA[4*420];

  i = gamma*420;
  j = gamma*400;
  
  CLFlt *p_s_tiPR = s_tiPR + i;
  CLFlt *p_s_tiPL = s_tiPL + i;
  CLFlt *p_s_tiPA = s_tiPA + i;
  
  CLFlt *p_tiPA = tiPA + j;  
  CLFlt *p_tiPL = tiPL + j;
  CLFlt *p_tiPR = tiPR + j;
  
  for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      j = protein_hash_table[h];
      p_s_tiPR[h] = p_tiPR[j];
      p_s_tiPL[h] = p_tiPL[j];
      p_s_tiPA[h] = p_tiPA[j];      
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      j = protein_hash_table[h];
      p_s_tiPR[h] = p_tiPR[j];
      p_s_tiPL[h] = p_tiPL[j];
      p_s_tiPA[h] = p_tiPA[j];      
    }
  else if (h<420)
    {
      p_s_tiPR[h] = 1.0;
      p_s_tiPL[h] = 1.0;
      p_s_tiPA[h] = 1.0;      
    }

  __syncthreads();

  h = 0;
  for (i=0; i<20; i++)
    {
      p_clP[i*numChars] = p_s_tiPL[l++] * p_s_tiPR[r++] * p_s_tiPA[a++];
    }
}


extern "C" void root_3_gen(int offset_clP, int offset_lState, int offset_rState, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(64, 4);

  gpu_root_3_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA, globaldevChars);
}

__global__ void gpu_root_2_gen (CLFlt *clP, CLFlt *clL, int *rState, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;  
  int gamma = threadIdx.y;  
  int state_idx = 64 * gid + tid;
  int h, i, j;
  int a = aState[state_idx];
  int r = rState[state_idx];

  CLFlt likeL;

  i = (20*numChars)*gamma + state_idx; 
  CLFlt *p_clL = clL + i;
  CLFlt *p_clP = clP + i;  

  __shared__ CLFlt s_tiPR[4*420];
  __shared__ CLFlt s_tiPA[4*420];
  __shared__ CLFlt s_tiPL[4*400];

  i = gamma*420;
  j = gamma*400;

  CLFlt *p_s_tiPA = s_tiPA + i;
  CLFlt *p_s_tiPR = s_tiPR + i;
  CLFlt *p_s_tiPL = s_tiPL + j;

  CLFlt *p_tiPA = tiPA + j;
  CLFlt *p_tiPL = tiPL + j;
  CLFlt *p_tiPR = tiPR + j;

    for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      j = protein_hash_table[h];
      p_s_tiPA[h] = p_tiPA[j];
      p_s_tiPR[h] = p_tiPR[j];
      p_s_tiPL[h] = p_tiPL[h];            
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      j = protein_hash_table[h];        
      p_s_tiPA[h] = p_tiPA[j];
      p_s_tiPR[h] = p_tiPR[j];
      p_s_tiPL[h] = p_tiPL[h];            
    }
  else if (h<420)
    {
      p_s_tiPA[h] = 1.0;
      p_s_tiPR[h] = 1.0;      
    }
  
  __syncthreads();

  h = 0;
  for (i=0; i<20; i++)
    {
      likeL = 0.0;
      
      for (j=0; j<20; j++)
	{
	  likeL += p_s_tiPL[h] * p_clL[j*numChars];
	  h ++;
	}
      
      p_clP[i*numChars] = likeL * p_s_tiPR[r++] * p_s_tiPA[a++];
    }
}


extern "C" void root_2_gen(int offset_clP, int offset_clL, int offset_rState, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(64, 4);

  gpu_root_2_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devtermState+offset_rState, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA, globaldevChars);
}


__global__ void gpu_root_1_gen (CLFlt *clP, CLFlt *clR, int *lState, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;  
  int gamma = threadIdx.y;  
  int state_idx = 64 * gid + tid;
  int h, i, j;
  int a = aState[state_idx];
  int l = lState[state_idx];
  
  CLFlt likeR;

  i = (20*numChars)*gamma + state_idx;  
  CLFlt *p_clR = clR + i;
  CLFlt *p_clP = clP + i;  

  __shared__ CLFlt s_tiPL[4*420];
  __shared__ CLFlt s_tiPA[4*420];
  __shared__ CLFlt s_tiPR[4*400];

  i = gamma*420;
  j = gamma*400;

  CLFlt *p_s_tiPA = s_tiPA + i;
  CLFlt *p_s_tiPL = s_tiPL + i;
  CLFlt *p_s_tiPR = s_tiPR + j;

  CLFlt *p_tiPA = tiPA + j;
  CLFlt *p_tiPL = tiPL + j;
  CLFlt *p_tiPR = tiPR + j;

    for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      j = protein_hash_table[h];
      p_s_tiPA[h] = p_tiPA[j];
      p_s_tiPL[h] = p_tiPL[j];
      p_s_tiPR[h] = p_tiPR[h];            
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      j = protein_hash_table[h];        
      p_s_tiPA[h] = p_tiPA[j];
      p_s_tiPL[h] = p_tiPL[j];
      p_s_tiPR[h] = p_tiPR[h];            
    }
  else if (h<420)
    {
      p_s_tiPA[h] = 1.0;
      p_s_tiPL[h] = 1.0;      
    }
  
  __syncthreads();

  h = 0;
  for (i=0; i<20; i++)
    {
      likeR = 0.0;
      
      for (j=0; j<20; j++)
	{
	  likeR += p_s_tiPR[h] * p_clR[j*numChars];
	  h ++;
	}
      
      p_clP[i*numChars] = likeR * p_s_tiPL[l++] * p_s_tiPA[a++];
    }
}


extern "C" void root_1_gen(int offset_clP, int offset_lState, int offset_clR, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(64, 4);

  gpu_root_1_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clR, devtermState+offset_lState, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA, globaldevChars);
}


__global__ void gpu_root_0_gen (CLFlt *clP, CLFlt *clL, CLFlt *clR, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;
  int gamma = threadIdx.y;  
  int state_idx = 64 * gid + tid;
  int h, i, j;
  int a = aState[state_idx];  

  CLFlt likeL, likeR;

  i = (20*numChars)*gamma + state_idx;
  CLFlt *p_clL = clL + i;
  CLFlt *p_clR = clR + i;
  CLFlt *p_clP = clP + i;  

  __shared__ CLFlt smem_tiPA[4*420];
  __shared__ CLFlt smem_tiPL[4*400];
  __shared__ CLFlt smem_tiPR[4*400];

  i = gamma*420;
  j = gamma*400;
  
  CLFlt *p_smem_tiPA = smem_tiPA + i;
  CLFlt *p_smem_tiPL = smem_tiPL + j;
  CLFlt *p_smem_tiPR = smem_tiPR + j;

  CLFlt *p_tiPA = tiPA + j;
  CLFlt *p_tiPL = tiPL + j;
  CLFlt *p_tiPR = tiPR + j;

    for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      p_smem_tiPA[h] = p_tiPA[protein_hash_table[h]];
      p_smem_tiPL[h] = p_tiPL[h];
      p_smem_tiPR[h] = p_tiPR[h];            
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      p_smem_tiPA[h] = p_tiPA[protein_hash_table[h]];
      p_smem_tiPL[h] = p_tiPL[h];
      p_smem_tiPR[h] = p_tiPR[h];            
    }
  else if (h<420)
    {
      p_smem_tiPA[h] = 1.0;
    }

  
  __syncthreads();


  h = 0;
  for (i=0; i<20; i++)
    {
      likeR = 0.0;
      likeL = 0.0;
      
      for (j=0; j<20; j++)
	{
	  likeL += p_smem_tiPL[h] * p_clL[j*numChars];
	  likeR += p_smem_tiPR[h] * p_clR[j*numChars];
	  h ++;
	}
      
      p_clP[i*numChars] = likeR * likeL * p_smem_tiPA[a++];
    }
}


extern "C" void root_0_gen(int offset_clP, int offset_clL, int offset_clR, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(64, 4);

  gpu_root_0_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA, globaldevChars);
}


__global__ void gpu_root_1_gammaCats_4(CLFlt *clP, CLFlt *clR, int *lState, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, idx, clp_idx, temp, state_idx, li, ai;
  CLFlt *m_preLikeA, *m_preLikeL, *m_tiPX, xa, xc, xg, xt, la,lc,lg,lt;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat;
  clp_idx  = 64*blockIdx.x + tid;
  temp = clp_idx;
  state_idx = clp_idx;

  li = lState[state_idx];
  ai = aState[state_idx];

  __shared__ CLFlt s_tiPX[64];
  s_tiPX[tid] = tiPR[tid];

  __shared__ CLFlt s_preLikeL[80];
  __shared__ CLFlt s_preLikeA[80];
  spreLike_idx = 20*gammaCat+4*tid_y+modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeL[spreLike_idx] = tiPL[tip_idx];
  s_preLikeA[spreLike_idx] = tiPA[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeL[spreLike_idx] = 1.0f;
      s_preLikeA[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;

  __syncthreads();

#pragma unroll

  for (idx=0; idx<numGammaCats; idx++)
    {
      m_preLikeL = &s_preLikeL[20*idx + li];
      m_preLikeA = &s_preLikeA[20*idx + ai];
      m_tiPX = &s_tiPX[16*idx];

      xa = clR[temp]; 
      temp += numChars;

      xc = clR[temp];
      temp += numChars;

      xg = clR[temp];
      temp += numChars;

      xt = clR[temp];
      temp += numChars;
      
      la = m_preLikeL[0] * m_preLikeA[0];
      lc = m_preLikeL[1] * m_preLikeA[1];
      lg = m_preLikeL[2] * m_preLikeA[2];
      lt = m_preLikeL[3] * m_preLikeA[3];

      clP[clp_idx] = (xa*m_tiPX[0] + xc*m_tiPX[1] + xg*m_tiPX[2] + xt*m_tiPX[3]) * la;
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[4] + xc*m_tiPX[5] + xg*m_tiPX[6] + xt*m_tiPX[7]) * lc;
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[8] + xc*m_tiPX[9] + xg*m_tiPX[10] + xt*m_tiPX[11]) * lg;
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[12] + xc*m_tiPX[13] + xg*m_tiPX[14] + xt*m_tiPX[15]) * lt;
      clp_idx += numChars;      
    }
}

extern "C" void root_1(int offset_clP, int offset_lState, int offset_clR, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_root_1_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clR, devtermState+offset_lState, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA);
}

__global__ void gpu_root_2_gammaCats_4 (CLFlt *clP, CLFlt *clL, int *rState, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, idx, clp_idx, temp, state_idx, ri, ai;
  CLFlt *m_preLikeA, *m_preLikeR, *m_tiPX, xa, xc, xg, xt, la, lc, lg, lt;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat;
  clp_idx  = 64*blockIdx.x + tid;
  temp = clp_idx;
  state_idx = clp_idx;

  ri = rState[state_idx];
  ai = aState[state_idx];

  __shared__ CLFlt s_tiPX[64];
  s_tiPX[tid] = tiPL[tid];

  __shared__ CLFlt s_preLikeR[80];
  __shared__ CLFlt s_preLikeA[80];
  spreLike_idx = 20*gammaCat+4*tid_y+modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeR[spreLike_idx] = tiPR[tip_idx];
  s_preLikeA[spreLike_idx] = tiPA[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeR[spreLike_idx] = 1.0f;
      s_preLikeA[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;

  __syncthreads();

#pragma unroll

  for (idx=0; idx<numGammaCats; idx++)
    {
      m_preLikeR = &s_preLikeR[20*idx + ri];
      m_preLikeA = &s_preLikeA[20*idx + ai];
      m_tiPX = &s_tiPX[16*idx];

      xa = clL[temp]; 
      temp += numChars;

      xc = clL[temp];
      temp += numChars;

      xg = clL[temp];
      temp += numChars;

      xt = clL[temp];
      temp += numChars;
      
      la = m_preLikeR[0] * m_preLikeA[0];
      lc = m_preLikeR[1] * m_preLikeA[1];
      lg = m_preLikeR[2] * m_preLikeA[2];
      lt = m_preLikeR[3] * m_preLikeA[3];
      
      clP[clp_idx] = (xa*m_tiPX[0] + xc*m_tiPX[1] + xg*m_tiPX[2] + xt*m_tiPX[3]) * la;
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[4] + xc*m_tiPX[5] + xg*m_tiPX[6] + xt*m_tiPX[7]) * lc;
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[8] + xc*m_tiPX[9] + xg*m_tiPX[10] + xt*m_tiPX[11]) * lg;
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[12] + xc*m_tiPX[13] + xg*m_tiPX[14] + xt*m_tiPX[15]) * lt;
      clp_idx += numChars;

    }
}

extern "C" void root_2(int offset_clP, int offset_clL, int offset_rState, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_root_2_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devtermState+offset_rState, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA);
}

__global__ void gpu_root_3_gammaCats_4 (CLFlt *clP, int *lState, int *rState, int *aState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, idx, clp_idx, state_idx, li, ri, ai;
  CLFlt *m_preLikeA, *m_preLikeL, *m_preLikeR, r_a, r_c, r_g, r_t;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat;
  clp_idx  = 64*blockIdx.x + tid;
  state_idx = clp_idx;

  li = lState[state_idx];
  ri = rState[state_idx];
  ai = aState[state_idx];

  __shared__ CLFlt s_preLikeL[80];
  __shared__ CLFlt s_preLikeR[80];
  __shared__ CLFlt s_preLikeA[80];
  spreLike_idx = 20*gammaCat+4*tid_y+modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeL[spreLike_idx] = tiPL[tip_idx];
  s_preLikeR[spreLike_idx] = tiPR[tip_idx];
  s_preLikeA[spreLike_idx] = tiPA[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeL[spreLike_idx] = 1.0f;
      s_preLikeR[spreLike_idx] = 1.0f;
      s_preLikeA[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;

  __syncthreads();
  
#pragma unroll
  for (idx=0; idx<numGammaCats; idx++)
    {
      m_preLikeL = &s_preLikeL[20*idx+li];
      m_preLikeR = &s_preLikeR[20*idx+ri];
      m_preLikeA = &s_preLikeA[20*idx+ai];

      r_a =m_preLikeL[0]*m_preLikeR[0];
      r_c = m_preLikeL[1]*m_preLikeR[1];
      r_g = m_preLikeL[2]*m_preLikeR[2];
      r_t = m_preLikeL[3]*m_preLikeR[3];

      clP[clp_idx] = m_preLikeA[0]*r_a;
      clp_idx += numChars;
      clP[clp_idx] = m_preLikeA[1]*r_c;
      clp_idx += numChars;
      clP[clp_idx] = m_preLikeA[2]*r_g;
      clp_idx += numChars;
      clP[clp_idx] = m_preLikeA[3]*r_t;
      clp_idx += numChars;
    }
}

extern "C" void root_3(int offset_clP, int offset_lState, int offset_rState, int offset_aState, int offset_pL, int offset_pR, int offset_pA, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_root_3_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtermState+offset_aState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA);
}

__global__ void gpu_root_4_gammaCats_4 (CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *clA, CLFlt *tiPL, CLFlt *tiPR, CLFlt *tiPA)
{
  int modelStat, gammaCat, tid_y, tid, idx, clp_idx, temp;
  CLFlt *m_tiPL, *m_tiPR, *m_tiPA, la, lc, lg, lt, ra, rc, rg, rt, aa, ac, ag, at;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat;
  clp_idx  = 64*blockIdx.x + tid;
  temp = clp_idx;

  __shared__ CLFlt s_tiPL[64];
  __shared__ CLFlt s_tiPR[64];
  __shared__ CLFlt s_tiPA[64];
  s_tiPL[tid] = tiPL[tid];
  s_tiPR[tid] = tiPR[tid];
  s_tiPA[tid] = tiPA[tid];

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;

  __syncthreads();

#pragma unroll
  for (idx=0; idx<numGammaCats; idx++)
    {
      m_tiPL = &s_tiPL[16*idx];
      m_tiPR = &s_tiPR[16*idx];
      m_tiPA = &s_tiPA[16*idx];

      la = clL[temp]; 
      ra = clR[temp]; 
      aa = clA[temp]; 
      temp += numChars;

      lc = clL[temp];
      rc = clR[temp];
      ac = clA[temp]; 
      temp += numChars;

      lg = clL[temp];
      rg = clR[temp];
      ag = clA[temp]; 
      temp += numChars;

      lt = clL[temp];
      rt = clR[temp];
      at = clA[temp]; 
      temp += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[0] + lc*m_tiPL[1] + lg*m_tiPL[2] + lt*m_tiPL[3]) * 
	(ra*m_tiPR[0] + rc*m_tiPR[1] + rg*m_tiPR[2] + rt*m_tiPR[3]) * 
	(aa*m_tiPA[0] + ac*m_tiPA[1] + ag*m_tiPA[2] + at*m_tiPA[3]);

      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[4] + lc*m_tiPL[5] + lg*m_tiPL[6] + lt*m_tiPL[7]) * 
	(ra*m_tiPR[4] + rc*m_tiPR[5] + rg*m_tiPR[6] + rt*m_tiPR[7]) * 
	(aa*m_tiPA[4] + ac*m_tiPA[5] + ag*m_tiPA[6] + at*m_tiPA[7]);

      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[8] + lc*m_tiPL[9] + lg*m_tiPL[10] + lt*m_tiPL[11]) * 
	(ra*m_tiPR[8] + rc*m_tiPR[9] + rg*m_tiPR[10] + rt*m_tiPR[11]) * 
	(aa*m_tiPA[8] + ac*m_tiPA[9] + ag*m_tiPA[10] + at*m_tiPA[11]);

      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[12] + lc*m_tiPL[13] + lg*m_tiPL[14] + lt*m_tiPL[15]) * 
	(ra*m_tiPR[12] + rc*m_tiPR[13] + rg*m_tiPR[14] + rt*m_tiPR[15]) * 
	(aa*m_tiPA[12] + ac*m_tiPA[13] + ag*m_tiPA[14] + at*m_tiPA[15]);

      clp_idx += numChars;
    }
}

extern "C" void root_4(int offset_clP, int offset_clL, int offset_clR, int offset_clA, int offset_pL, int offset_pR, int offset_pA, int chain,int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_root_4_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devCondLikes+offset_clA, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtiProbSpace+offset_pA);
}

__global__ void gpu_down_3_gammaCats_4_s3 (CLFlt *clP, int *lState, int *rState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *lnScaler, CLFlt *scPOld, CLFlt *scPNew)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, clp_idx, state_idx, li, ri, idx, char_idx;
  CLFlt *m_preLikeL, *m_preLikeR;
  CLFlt treeScaler, nodeScalerOld, scaler=0.0, r_scaler;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  char_idx = clp_idx;
  state_idx = clp_idx;
  
  li = lState[state_idx];
  ri = rState[state_idx];

  __shared__ CLFlt s_preLikeL[80]; 
  __shared__ CLFlt s_preLikeR[80]; 

  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeL[spreLike_idx] = tiPL[tip_idx];
  s_preLikeR[spreLike_idx] = tiPR[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeL[spreLike_idx] = 1.0f;
      s_preLikeR[spreLike_idx] = 1.0f;
    } 

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;
  
  __syncthreads();

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      m_preLikeL = &s_preLikeL[20*idx+li];
      m_preLikeR = &s_preLikeR[20*idx+ri];

      r_scaler = m_preLikeL[0]*m_preLikeR[0]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
      r_scaler = m_preLikeL[1]*m_preLikeR[1]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
      r_scaler = m_preLikeL[2]*m_preLikeR[2]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
      r_scaler = m_preLikeL[3]*m_preLikeR[3]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
    }

  clp_idx = 64*blockIdx.x + tid;
  gpu_scale_clP(clP, clp_idx, scaler, numChars);
  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  treeScaler -= nodeScalerOld;
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 

}

__global__ void gpu_down_3_gammaCats_4_s2 (CLFlt *clP, int *lState, int *rState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *lnScaler, CLFlt *scPNew)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, clp_idx, state_idx, li, ri, idx, char_idx;
  CLFlt *m_preLikeL, *m_preLikeR;
  CLFlt treeScaler, scaler=0.0, r_scaler;
  
  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  char_idx = clp_idx;
  state_idx = clp_idx;

  li = lState[state_idx];
  ri = rState[state_idx];

  __shared__ CLFlt s_preLikeL[80];
  __shared__ CLFlt s_preLikeR[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeL[spreLike_idx] = tiPL[tip_idx];
  s_preLikeR[spreLike_idx] = tiPR[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeL[spreLike_idx] = 1.0f;
      s_preLikeR[spreLike_idx] = 1.0f;
    } 

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;
  
  __syncthreads();

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      m_preLikeL = &s_preLikeL[20*idx+li];
      m_preLikeR = &s_preLikeR[20*idx+ri];

      r_scaler = m_preLikeL[0]*m_preLikeR[0]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
      r_scaler = m_preLikeL[1]*m_preLikeR[1]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
      r_scaler = m_preLikeL[2]*m_preLikeR[2]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
      r_scaler = m_preLikeL[3]*m_preLikeR[3]; 
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
    }

  clp_idx = 64*blockIdx.x + tid;
  gpu_scale_clP(clP, clp_idx, scaler, numChars);
  treeScaler = lnScaler[char_idx];
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 
}

__global__ void gpu_down_3_gammaCats_4_s1(CLFlt *clP, int *lState, int *rState, CLFlt *tiPL, CLFlt *tiPR, CLFlt *lnScaler, CLFlt *scPOld)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, clp_idx, state_idx, li, ri, idx, char_idx;
  CLFlt *m_preLikeL, *m_preLikeR;
  CLFlt treeScaler, nodeScalerOld;
  
  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  char_idx = clp_idx;
  state_idx = clp_idx;

  li = lState[state_idx];
  ri = rState[state_idx];

  __shared__ CLFlt s_preLikeL[80];
  __shared__ CLFlt s_preLikeR[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeL[spreLike_idx] = tiPL[tip_idx];
  s_preLikeR[spreLike_idx] = tiPR[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeL[spreLike_idx] = 1.0f;
      s_preLikeR[spreLike_idx] = 1.0f;
    } 

  __shared__ int numChars; 
  numChars = 64 * gridDim.x;
  
  __syncthreads();

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      m_preLikeL = &s_preLikeL[20*idx+li];
      m_preLikeR = &s_preLikeR[20*idx+ri];

      clP[clp_idx] = m_preLikeL[0]*m_preLikeR[0]; 
      clp_idx += numChars;

      clP[clp_idx] = m_preLikeL[1]*m_preLikeR[1]; 
      clp_idx += numChars;

      clP[clp_idx] = m_preLikeL[2]*m_preLikeR[2]; 
      clp_idx += numChars;

      clP[clp_idx] = m_preLikeL[3]*m_preLikeR[3]; 
      clp_idx += numChars;
    }

  clp_idx = 64*blockIdx.x + tid;
  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  lnScaler[char_idx] = treeScaler - nodeScalerOld; 
}


__global__ void gpu_down_3_gammaCats_4 (CLFlt *clP, int *lState, int *rState, CLFlt *tiPL, CLFlt *tiPR)
{
  int modelStat, gammaCat, tid_y, tid, spreLike_idx, tip_idx, clp_idx, state_idx, li, ri, idx;
  CLFlt *m_preLikeL, *m_preLikeR;
  
  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  state_idx = clp_idx;

  li = lState[state_idx];
  ri = rState[state_idx];

  __shared__ CLFlt s_preLikeL[80];
  __shared__ CLFlt s_preLikeR[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeL[spreLike_idx] = tiPL[tip_idx];
  s_preLikeR[spreLike_idx] = tiPR[tip_idx];
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeL[spreLike_idx] = 1.0f;
      s_preLikeR[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars;
  numChars = 64 * gridDim.x;
  
  __syncthreads();

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      m_preLikeL = &s_preLikeL[20*idx+li];
      m_preLikeR = &s_preLikeR[20*idx+ri];

      clP[clp_idx] = m_preLikeL[0]*m_preLikeR[0]; 
      clp_idx += numChars;
      clP[clp_idx] = m_preLikeL[1]*m_preLikeR[1]; 
      clp_idx += numChars;
      clP[clp_idx] = m_preLikeL[2]*m_preLikeR[2]; 
      clp_idx += numChars;
      clP[clp_idx] = m_preLikeL[3]*m_preLikeR[3]; 
      clp_idx += numChars;
    }
}

extern "C" void down_3(int offset_clP, int offset_lState, int offset_rState, int offset_pL, int offset_pR, int modelnumChars, int modelnumGammaCats, int chain, int offset_lnScaler, int offset_scPOld, int offset_scPNew, int scaler_shortcut)
{
      dim3	dimGrid(globaldevChars/64, 1, 1);
      dim3	dimBlock(4, 4, 4);

      if (scaler_shortcut==3)
	{
	gpu_down_3_gammaCats_4_s3<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld, devnodeScalerSpace+offset_scPNew);	
	}
      else if (scaler_shortcut==2)
	{
	gpu_down_3_gammaCats_4_s2<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPNew);	
	}
      else if (scaler_shortcut==1)
	{
	gpu_down_3_gammaCats_4_s1<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld);	
	}
      else
	{
	gpu_down_3_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR);
	//exit(1);
	}
}

__global__ void gpu_likelihood_hasNoPInvar(CLFlt *clP, CLFlt *lnScaler, CLFlt *numSitesOfPat, MrBFlt freq, MrBFlt b_A, MrBFlt b_C, MrBFlt b_G, MrBFlt b_T, MrBFlt *siteLikes)
{
  int modelStat, tid_y, gammaCat, tid, clp_idx, char_idx, idx;
  MrBFlt likeA=0.0, likeC=0.0, likeG=0.0, likeT=0.0, likeSum;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64 * blockIdx.x + tid;
  char_idx = clp_idx;
  
  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;

#pragma unroll  

  for(idx=0; idx<numGammaCats; idx++)
    {
      likeA += clP[clp_idx];
      clp_idx += numChars;
      likeC += clP[clp_idx];
      clp_idx += numChars;
      likeG += clP[clp_idx];
      clp_idx += numChars;
      likeT += clP[clp_idx];
      clp_idx += numChars;
    }
  
  likeSum = likeA*b_A + likeC*b_C + likeG*b_G + likeT*b_T;
  likeSum *= freq;

  /*  
  if (lnScaler[char_idx] < -200)
    {
      if(likeI > 1E-70)
	{
	  likeSum = likeI;
	}
    }
  else
    {
      if(likeI != 0.0)
	{
	  if(exp (lnScaler[char_idx]) > 0.0)
	    likeSum = likeSum + (likeI / exp (lnScaler[char_idx]));	
	}
    }
  */

  siteLikes[char_idx] = (lnScaler[char_idx] + log(likeSum)) * numSitesOfPat[char_idx];
}

extern "C" void cuda_likelihood_hasNoPInvar(int offset_clP, int offset_lnScalers, int offset_sitesOfPat, MrBFlt freq, MrBFlt b_A, MrBFlt b_C, MrBFlt b_G, MrBFlt b_T, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_likelihood_hasNoPInvar <<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtreeScalerSpace+offset_lnScalers, devnumSitesOfPat+offset_sitesOfPat, freq, b_A, b_C, b_G, b_T, devlnL + chain*globaldevChars);
}

__global__ void gpu_likelihood_hasPInvar(CLFlt *clP, CLFlt *lnScaler, CLFlt *numSitesOfPat, MrBFlt *clI, MrBFlt pInvar, MrBFlt freq, MrBFlt b_A, MrBFlt b_C, MrBFlt b_G, MrBFlt b_T, MrBFlt *siteLikes)
{
  int modelStat, tid_y, gammaCat, tid, clp_idx, clI_idx, char_idx, idx;
  MrBFlt likeA=0.0, likeC=0.0, likeG=0.0, likeT=0.0, likeI, likeSum;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64 * blockIdx.x + tid;
  char_idx = clp_idx;
  clI_idx = clp_idx;
  
  __shared__ int numChars; 
  numChars = 64 * gridDim.x;

  __shared__ int numGammaCats;
  numGammaCats = blockDim.z;

#pragma unroll  

  for(idx=0; idx<numGammaCats; idx++)
    {
      likeA += clP[clp_idx];
      clp_idx += numChars;
      likeC += clP[clp_idx];
      clp_idx += numChars;
      likeG += clP[clp_idx];
      clp_idx += numChars;
      likeT += clP[clp_idx];
      clp_idx += numChars;
    }
  
  likeSum = likeA*b_A + likeC*b_C + likeG*b_G + likeT*b_T;
  likeSum *= freq;

  likeI = (clI[clI_idx]*b_A + clI[clI_idx+1*numChars]*b_C + clI[clI_idx+2*numChars]*b_G + clI[clI_idx+3*numChars]*b_T) * pInvar;
  
  if (lnScaler[char_idx] < -200)
    {
      if(likeI > 1E-70)
	{
	  likeSum = likeI;
	}
    }
  else
    {
      if(likeI != 0.0)
	{
	  if(exp (lnScaler[char_idx]) > 0.0)
	    likeSum = likeSum + (likeI / exp (lnScaler[char_idx]));	
	}
    }

  siteLikes[char_idx] = (lnScaler[char_idx] + log(likeSum)) * numSitesOfPat[char_idx];
}

extern "C" void cuda_likelihood_hasPInvar(int offset_clP, int offset_lnScalers, int offset_sitesOfPat, MrBFlt pInvar, MrBFlt freq, MrBFlt b_A, MrBFlt b_C, MrBFlt b_G, MrBFlt b_T, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_likelihood_hasPInvar <<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtreeScalerSpace+offset_lnScalers, devnumSitesOfPat+offset_sitesOfPat, devinvCondLikes, pInvar, freq, b_A, b_C, b_G, b_T, devlnL + chain*globaldevChars);
}


__global__ void gpu_likelihood_hasPInvar_gen(CLFlt *clP, CLFlt *lnScaler, CLFlt *numSitesOfPat, MrBFlt *clI, MrBFlt *bs, MrBFlt pInvar, MrBFlt freq,  MrBFlt *siteLikes)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;
  int gamma = threadIdx.y;  
  int state_idx = 64 * gid + 16 * gamma + tid;
  int clI_idx = 20 * state_idx;
  int numChars = 64 * gridDim.x;
  CLFlt *p_clP = clP + state_idx;
  MrBFlt like = 0.0, likeI = 0.0;

  int k, i;
  for (k=0; k<4; k++)
    {
      for (i=0; i<20; i++)
	{
	  like += p_clP[i*numChars] * bs[i];
	}
      p_clP += 20*numChars;
    }

  like *= freq;
  
  for (i=0; i<20; i++)
    {
      likeI += clI[clI_idx++] * bs[i];
    }

  likeI *= pInvar;

  if (lnScaler[state_idx] < -200)
    {
      if(likeI > 1E-70)
	{
	  like = likeI;
	}
    }
  else
    {
      if(likeI != 0.0)
	{
	  if(exp (lnScaler[state_idx]) > 0.0)
	    like = like + (likeI / exp (lnScaler[state_idx]));	
	}
    }
  
  siteLikes[state_idx] = (lnScaler[state_idx] + log(like)) * numSitesOfPat[state_idx];
  //siteLikes[state_idx] = (lnScaler[state_idx] + log(like));// * numSitesOfPat[state_idx];
  //siteLikes[state_idx] =  like;
}

extern "C" void cuda_likelihood_hasPInvar_gen(int offset_clP, int offset_lnScalers, int offset_sitesOfPat, MrBFlt pInvar, MrBFlt freq, int chain, int modelnumChars, int modelnumGammaCats)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(16, 4);

  gpu_likelihood_hasPInvar_gen <<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtreeScalerSpace+offset_lnScalers, devnumSitesOfPat+offset_sitesOfPat, devinvCondLikes, devBaseFreq + chain*20, pInvar, freq, devlnL + chain*globaldevChars);

#if 0
  cutilSafeCall(cudaMemcpy((void *)(globallnL + chain*globaldevChars), (const void *)(devlnL + chain*globaldevChars), globaldevChars * sizeof(MrBFlt), cudaMemcpyDeviceToHost));
  cudaStreamSync(chain);

  int i;
  MrBFlt result = 0.0, *ptr = globallnL+chain*globaldevChars;
  
  for (i=0; i<globaldevChars; i++)
    {
      if (i<numCompressedChars)
	result += ptr[i];
    }
  printf("device: %lf\n", result);
#endif  
}

__global__ void gpu_down_12_gammaCats_4_s3(CLFlt *clP, CLFlt *clX, CLFlt *tiPX, int *xState,  CLFlt *ti_preLikeX, CLFlt *lnScaler, CLFlt *scPOld, CLFlt *scPNew)
{
  int modelStat, gammaCat, tid_y, tip_idx, tid, clp_idx, temp, idx, xi;
  int spreLike_idx, state_idx, char_idx;
  CLFlt *m_tiPX, *m_preLikeX, xa, xc, xg, xt;
  CLFlt treeScaler, nodeScalerOld, r_scaler, scaler=0.0;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  temp = clp_idx;
  char_idx = clp_idx;
  state_idx = clp_idx;

  xi = xState[state_idx];

  __shared__ CLFlt s_tiPX[64];
  s_tiPX[tid] = tiPX[tid];

  __shared__ CLFlt s_preLikeX[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeX[spreLike_idx] = ti_preLikeX[tip_idx];  
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeX[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      m_preLikeX = &s_preLikeX[20*idx + xi];
      m_tiPX = &s_tiPX[16*idx];

      xa = clX[temp]; 
      temp += numChars;

      xc = clX[temp];
      temp += numChars;

      xg = clX[temp];
      temp += numChars;

      xt = clX[temp];
      temp += numChars;

      r_scaler = (xa*m_tiPX[0] + xc*m_tiPX[1] + xg*m_tiPX[2] + xt*m_tiPX[3]) * m_preLikeX[0];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;
      
      r_scaler = (xa*m_tiPX[4] + xc*m_tiPX[5] + xg*m_tiPX[6] + xt*m_tiPX[7]) * m_preLikeX[1];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = (xa*m_tiPX[8] + xc*m_tiPX[9] + xg*m_tiPX[10] + xt*m_tiPX[11]) * m_preLikeX[2];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = (xa*m_tiPX[12] + xc*m_tiPX[13] + xg*m_tiPX[14] + xt*m_tiPX[15]) * m_preLikeX[3];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
    }

  clp_idx = 64*blockIdx.x + tid;  
  gpu_scale_clP(clP, clp_idx, scaler, numChars);
  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  treeScaler -= nodeScalerOld;
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 
}

__global__ void gpu_down_12_gammaCats_4_s1(CLFlt *clP, CLFlt *clX, CLFlt *tiPX, int *xState,  CLFlt *ti_preLikeX, CLFlt *lnScaler, CLFlt *scPOld)
{
  int modelStat, gammaCat, tid_y, tip_idx, tid, clp_idx, temp, idx, xi;
  int spreLike_idx, state_idx, char_idx;
  CLFlt *m_tiPX, *m_preLikeX, xa, xc, xg, xt;
  CLFlt treeScaler, nodeScalerOld;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  temp = clp_idx;
  char_idx = clp_idx;
  state_idx = clp_idx;

  xi = xState[state_idx];

  __shared__ CLFlt s_tiPX[64];
  s_tiPX[tid] = tiPX[tid];

  __shared__ CLFlt s_preLikeX[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeX[spreLike_idx] = ti_preLikeX[tip_idx];  
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeX[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4
  for (idx=0; idx<4; idx++)
    {
      m_preLikeX = &s_preLikeX[20*idx + xi];
      m_tiPX = &s_tiPX[16*idx];

      xa = clX[temp]; 
      temp += numChars;

      xc = clX[temp];
      temp += numChars;

      xg = clX[temp];
      temp += numChars;

      xt = clX[temp];
      temp += numChars;

      clP[clp_idx] = (xa*m_tiPX[0] + xc*m_tiPX[1] + xg*m_tiPX[2] + xt*m_tiPX[3]) * m_preLikeX[0];
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[4] + xc*m_tiPX[5] + xg*m_tiPX[6] + xt*m_tiPX[7]) * m_preLikeX[1];
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[8] + xc*m_tiPX[9] + xg*m_tiPX[10] + xt*m_tiPX[11]) * m_preLikeX[2];
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[12] + xc*m_tiPX[13] + xg*m_tiPX[14] + xt*m_tiPX[15]) * m_preLikeX[3];
      clp_idx += numChars;
    }

  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  lnScaler[char_idx] = treeScaler - nodeScalerOld; 
}

__global__ void gpu_down_12_gammaCats_4_s2(CLFlt *clP, CLFlt *clX, CLFlt *tiPX, int *xState,  CLFlt *ti_preLikeX, CLFlt *lnScaler, CLFlt *scPNew)
{
  int modelStat, gammaCat, tid_y, tip_idx, tid, clp_idx, temp, idx, xi;
  int spreLike_idx, state_idx, char_idx;
  CLFlt *m_tiPX, *m_preLikeX, xa, xc, xg, xt;
  CLFlt treeScaler, r_scaler, scaler=0.0;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  temp = clp_idx;
  char_idx = clp_idx;
  state_idx = clp_idx;

  xi = xState[state_idx];

  __shared__ CLFlt s_tiPX[64];
  s_tiPX[tid] = tiPX[tid];

  __shared__ CLFlt s_preLikeX[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeX[spreLike_idx] = ti_preLikeX[tip_idx];  
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeX[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      m_preLikeX = &s_preLikeX[20*idx + xi];
      m_tiPX = &s_tiPX[16*idx];

      xa = clX[temp]; 
      temp += numChars;

      xc = clX[temp];
      temp += numChars;

      xg = clX[temp];
      temp += numChars;

      xt = clX[temp];
      temp += numChars;

      r_scaler = (xa*m_tiPX[0] + xc*m_tiPX[1] + xg*m_tiPX[2] + xt*m_tiPX[3]) * m_preLikeX[0];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;
      
      r_scaler = (xa*m_tiPX[4] + xc*m_tiPX[5] + xg*m_tiPX[6] + xt*m_tiPX[7]) * m_preLikeX[1];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = (xa*m_tiPX[8] + xc*m_tiPX[9] + xg*m_tiPX[10] + xt*m_tiPX[11]) * m_preLikeX[2];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = (xa*m_tiPX[12] + xc*m_tiPX[13] + xg*m_tiPX[14] + xt*m_tiPX[15]) * m_preLikeX[3];
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
      if (r_scaler > scaler) scaler = r_scaler;
    }

  clp_idx = 64*blockIdx.x + tid;  
  gpu_scale_clP(clP, clp_idx, scaler, numChars);
  treeScaler = lnScaler[char_idx];
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 
}

__global__ void gpu_down_1_gen(CLFlt *clP, CLFlt *clR, CLFlt *tiPR, int *lState,  CLFlt *tiPL, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;
  int gamma = threadIdx.y;
  int h, i, j;
  int state_idx = 64 * gid + tid;
  int a = lState[state_idx];
  
  CLFlt likeR;
  i = (20*numChars)*gamma + state_idx;
  CLFlt *p_clR = clR + i;
  CLFlt *p_clP = clP + i;

  __shared__ CLFlt s_tiPL[4*420];
  __shared__ CLFlt s_tiPR[4*400];

  i = gamma*420;
  j = gamma*400;
  CLFlt *p_s_tiPL = s_tiPL + i;
  CLFlt *p_s_tiPR = s_tiPR + j;
  CLFlt *p_tiPL = tiPL + j;  
  CLFlt *p_tiPR = tiPR + j;

  for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      p_s_tiPL[h] = p_tiPL[protein_hash_table[h]];
      p_s_tiPR[h] = p_tiPR[h];      
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      p_s_tiPL[h] = p_tiPL[protein_hash_table[h]];
      p_s_tiPR[h] = p_tiPR[h];      
    }
  else if (h < 420)
    {
      p_s_tiPL[h] = 1.0;
    }
    
  __syncthreads();


  h = 0;
  for (i = 0; i < 20; i++)
    {
      likeR = 0.0;
      
      for (j=0; j<20; j++)
	{
	  likeR += p_s_tiPR[h] * p_clR[j*numChars];
	  h++;
	}
      
      p_clP[i*numChars] =  likeR * p_s_tiPL[a++];
    }
}


extern "C" void down_1_gen(int offset_clP, int offset_clR, int offset_pR, int offset_lState, int offset_pL, int modelnumChars, int modelnumGammaCats, int chain)
{
  dim3 dimGrid(globaldevChars/64, 1);
  dim3 dimBlock(64, 4);
  
  gpu_down_1_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clR, devtiProbSpace+offset_pR, devtermState+offset_lState, devtiProbSpace+offset_pL, globaldevChars);
}


__global__ void gpu_down_0_gen(CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *tiPL, CLFlt *tiPR, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;
  int state_idx = 64 * gid + tid;  
  int gamma = threadIdx.y;  
  int i, j, h;

  CLFlt likeL;
  CLFlt likeR;
  i = (20*numChars)*gamma + state_idx;;
  CLFlt *p_clL = clL + i;
  CLFlt *p_clR = clR + i;
  CLFlt *p_clP = clP + i;
  
  __shared__ CLFlt s_tiPL[4*400];
  __shared__ CLFlt s_tiPR[4*400];

  i = gamma*400;
  CLFlt *p_s_tiPL = s_tiPL + i;
  CLFlt *p_s_tiPR = s_tiPR + i;    
  CLFlt *p_tiPL = tiPL + i;
  CLFlt *p_tiPR = tiPR + i;  

  for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      p_s_tiPL[h] = p_tiPL[h];
      p_s_tiPR[h] = p_tiPR[h];            
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      p_s_tiPL[h] = p_tiPL[h];      
      p_s_tiPR[h] = p_tiPR[h];      
    }
  
  __syncthreads();

  h = 0;
  for (i=0; i<20; i++)
    {
      likeL = likeR = 0.0;
      for (j=0; j<20; j++)
	{
	  likeL += p_s_tiPL[h] * p_clL[j*numChars];
	  likeR += p_s_tiPR[h] * p_clR[j*numChars];
	  h++;
	}
      p_clP[i*numChars] = likeL * likeR;
    }
}


extern "C" void down_0_gen(int offset_clP, int offset_clL, int offset_clR, int offset_pL, int offset_pR, int modelnumChars, int modelnumGammaCats, int chain)
{
  dim3 dimGrid(globaldevChars/64, 1);
  dim3 dimBlock(64, 4);
  
  gpu_down_0_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, globaldevChars);
}


__global__ void gpu_down_2_gen(CLFlt *clP, CLFlt *clL, CLFlt *tiPL, int *rState,  CLFlt *tiPR, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;
  int gamma = threadIdx.y;    
  int state_idx = 64 * gid + tid;
  int h, i, j;
  int a = rState[state_idx];

  CLFlt likeL;
  
  i = (20*numChars)*gamma + state_idx;  
  CLFlt *p_clL = clL + i;
  CLFlt *p_clP = clP + i;
  
  __shared__ CLFlt s_tiPR[4*420];
  __shared__ CLFlt s_tiPL[4*400];

  i = gamma*420;
  j = gamma*400;
  
  CLFlt *p_s_tiPR = s_tiPR + i;
  CLFlt *p_s_tiPL = s_tiPL + j;  

  CLFlt *p_tiPR = tiPR + j;
  CLFlt *p_tiPL = tiPL + j;
  
  for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      p_s_tiPR[h] = p_tiPR[protein_hash_table[h]];
      p_s_tiPL[h] = p_tiPL[h];      
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      p_s_tiPR[h] = p_tiPR[protein_hash_table[h]];
      p_s_tiPL[h] = p_tiPL[h];      
    }
  else if (h<420)
    {
      p_s_tiPR[h] = 1.0;
    }

  __syncthreads();
  
  h = 0;
  for (i=0; i<20; i++)
    {
      likeL = 0.0;

      for (j=0; j<20; j++)
	{
	  likeL += p_s_tiPL[h++] * p_clL[j*numChars];
	}
      p_clP[i*numChars] = likeL * p_s_tiPR[a++];
    }
}


extern "C" void down_2_gen(int offset_clP, int offset_clL, int offset_pL, int offset_rState, int offset_pR, int modelnumChars, int modelnumGammaCats, int chain)

{
  dim3 dimGrid(globaldevChars/64, 1);
  dim3 dimBlock(64, 4);
  
  gpu_down_2_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devtiProbSpace+offset_pL, devtermState+offset_rState, devtiProbSpace+offset_pR, globaldevChars);
}


__global__ void gpu_down_3_gen(CLFlt *clP, int *lState, int *rState, CLFlt *tiPL, CLFlt *tiPR, int numChars)
{
  int gid = blockIdx.x;
  int tid = threadIdx.x;
  int gamma = threadIdx.y;  
  int h, i, j;
  int state_idx = 64 * gid + tid;    
  int l = lState[state_idx];
  int r = rState[state_idx];

  i = (20*numChars)*gamma + state_idx;
  CLFlt *p_clP = clP + i;

  __shared__ CLFlt s_tiPR[4*420];
  __shared__ CLFlt s_tiPL[4*420];

  i = gamma*420;
  j = gamma*400;
  CLFlt *p_s_tiPR = s_tiPR + i;
  CLFlt *p_s_tiPL = s_tiPL + i;
  CLFlt *p_tiPL = tiPL + j;
  CLFlt *p_tiPR = tiPR + j;
  
  for (i=0; i<6; i++)
    {
      h = 64*i + tid;
      j = protein_hash_table[h];
      p_s_tiPR[h] = p_tiPR[j];
      p_s_tiPL[h] = p_tiPL[j];
    }
  
  h = 64*6 + tid;
  if (h < 400)
    {
      j = protein_hash_table[h];
      p_s_tiPR[h] = p_tiPR[j];
      p_s_tiPL[h] = p_tiPL[j];      
    }
  else if (h<420)
    {
      p_s_tiPR[h] = 1.0;
      p_s_tiPL[h] = 1.0;
    }
  
  __syncthreads();

  h = 0;
  for (i=0; i<20; i++)
    {
      p_clP[i*numChars] = p_s_tiPL[l++] * p_s_tiPR[r++];
    }
}

extern "C" void down_3_gen(int offset_clP, int offset_lState, int offset_rState, int offset_pL, int offset_pR, int modelnumChars, int modelnumGammaCats, int chain)

{
  dim3 dimGrid(globaldevChars/64, 1);
  dim3 dimBlock(64, 4);
  
  gpu_down_3_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtermState+offset_lState, devtermState+offset_rState, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, globaldevChars);
}


__global__ void gpu_down_12_gammaCats_4(CLFlt *clP, CLFlt *clX, CLFlt *tiPX, int *xState,  CLFlt *ti_preLikeX)
{
  int modelStat, gammaCat, tid_y, tip_idx, tid, clp_idx, temp, idx, xi;
  int spreLike_idx, state_idx;
  CLFlt *m_tiPX, *m_preLikeX, xa, xc, xg, xt;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  temp = clp_idx;
  state_idx = clp_idx;

  xi = xState[state_idx];

  __shared__ CLFlt s_tiPX[64];
  s_tiPX[tid] = tiPX[tid];

  __shared__ CLFlt s_preLikeX[80];
  spreLike_idx = 20*gammaCat + 4*tid_y + modelStat;
  tip_idx = 16*gammaCat + tid_y + 4*modelStat;
  s_preLikeX[spreLike_idx] = ti_preLikeX[tip_idx];  
  if (tid_y == 3)
    {
      spreLike_idx += 4;
      s_preLikeX[spreLike_idx] = 1.0f;
    }

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      m_preLikeX = &s_preLikeX[20*idx + xi];
      m_tiPX = &s_tiPX[16*idx];

      xa = clX[temp]; 
      temp += numChars;

      xc = clX[temp];
      temp += numChars;

      xg = clX[temp];
      temp += numChars;

      xt = clX[temp];
      temp += numChars;

      clP[clp_idx] = (xa*m_tiPX[0] + xc*m_tiPX[1] + xg*m_tiPX[2] + xt*m_tiPX[3]) * m_preLikeX[0];
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[4] + xc*m_tiPX[5] + xg*m_tiPX[6] + xt*m_tiPX[7]) * m_preLikeX[1];
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[8] + xc*m_tiPX[9] + xg*m_tiPX[10] + xt*m_tiPX[11]) * m_preLikeX[2];
      clp_idx += numChars;

      clP[clp_idx] = (xa*m_tiPX[12] + xc*m_tiPX[13] + xg*m_tiPX[14] + xt*m_tiPX[15]) * m_preLikeX[3];
      clp_idx += numChars;
    }
}




extern "C" void down_12(int offset_clP, int offset_clx, int offset_px, int offset_xState, int offset_px_preLike, int modelnumChars, int modelnumGammaCats, int chain, int offset_lnScaler, int offset_scPOld, int offset_scPNew, int scaler_shortcut)

{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

    if (scaler_shortcut == 3)
      {
	gpu_down_12_gammaCats_4_s3<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clx, devtiProbSpace+offset_px, devtermState+offset_xState, devtiProbSpace+offset_px_preLike, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld, devnodeScalerSpace+offset_scPNew);
      }
    else if (scaler_shortcut == 2)
      {
	gpu_down_12_gammaCats_4_s2<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clx, devtiProbSpace+offset_px, devtermState+offset_xState, devtiProbSpace+offset_px_preLike, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPNew);
	
      }
    else if (scaler_shortcut == 1)
      {
	gpu_down_12_gammaCats_4_s1<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clx, devtiProbSpace+offset_px, devtermState+offset_xState, devtiProbSpace+offset_px_preLike, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld);
      }
    else
      gpu_down_12_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clx, devtiProbSpace+offset_px, devtermState+offset_xState, devtiProbSpace+offset_px_preLike);

}

__global__ void gpu_down_0_gammaCats_4_s3(CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *tiPL, CLFlt *tiPR, CLFlt *lnScaler, CLFlt *scPOld, CLFlt *scPNew)
{
  int modelStat, gammaCat, tid_y, tid, clp_idx, temp, idx, char_idx;
  CLFlt la, lc, lg, lt, ra, rc, rg, rt;
  CLFlt *m_tiPL, *m_tiPR;
  CLFlt treeScaler, nodeScalerOld, scaler=0.0, r_scaler;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  char_idx = clp_idx;
  temp = clp_idx;

  __shared__ CLFlt s_tiPL[64];
  __shared__ CLFlt s_tiPR[64];
  s_tiPL[tid] = tiPL[tid];
  s_tiPR[tid] = tiPR[tid];

  __shared__ int numChars;
  numChars = 64*gridDim.x;

  __syncthreads();

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      m_tiPL = &s_tiPL[16*idx];
      m_tiPR = &s_tiPR[16*idx];

      la = clL[temp]; 
      ra = clR[temp]; 
      temp += numChars;

      lc = clL[temp];
      rc = clR[temp];
      temp += numChars;

      lg = clL[temp];
      rg = clR[temp];
      temp += numChars;

      lt = clL[temp];
      rt = clR[temp];
      temp += numChars;
      

      r_scaler = 
	(la*m_tiPL[0] + lc*m_tiPL[1] + lg*m_tiPL[2] + lt*m_tiPL[3]) * 
	(ra*m_tiPR[0] + rc*m_tiPR[1] + rg*m_tiPR[2] + rt*m_tiPR[3]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = 
	(la*m_tiPL[4] + lc*m_tiPL[5] + lg*m_tiPL[6] + lt*m_tiPL[7]) * 
	(ra*m_tiPR[4] + rc*m_tiPR[5] + rg*m_tiPR[6] + rt*m_tiPR[7]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = 
	(la*m_tiPL[8] + lc*m_tiPL[9] + lg*m_tiPL[10] + lt*m_tiPL[11]) * 
	(ra*m_tiPR[8] + rc*m_tiPR[9] + rg*m_tiPR[10] + rt*m_tiPR[11]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = 
	(la*m_tiPL[12] + lc*m_tiPL[13] + lg*m_tiPL[14] + lt*m_tiPL[15]) * 
	(ra*m_tiPR[12] + rc*m_tiPR[13] + rg*m_tiPR[14] + rt*m_tiPR[15]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;
    }

  clp_idx = 64*blockIdx.x + tid;
  gpu_scale_clP(clP, clp_idx, scaler, numChars);
  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  treeScaler -= nodeScalerOld;
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 

}


__global__ void gpu_down_0_gammaCats_4_s1(CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *tiPL, CLFlt *tiPR, CLFlt *lnScaler, CLFlt *scPOld)
{
  int modelStat, gammaCat, tid_y, tid, clp_idx, temp, idx, char_idx;
  CLFlt la, lc, lg, lt, ra, rc, rg, rt;
  CLFlt *m_tiPL, *m_tiPR;
  CLFlt treeScaler, nodeScalerOld;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  char_idx = clp_idx;
  temp = clp_idx;

  __shared__ CLFlt s_tiPL[64];
  __shared__ CLFlt s_tiPR[64];
  s_tiPL[tid] = tiPL[tid];
  s_tiPR[tid] = tiPR[tid];

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      m_tiPL = &s_tiPL[16*idx];
      m_tiPR = &s_tiPR[16*idx];

      la = clL[temp]; 
      ra = clR[temp]; 
      temp += numChars;

      lc = clL[temp];
      rc = clR[temp];
      temp += numChars;

      lg = clL[temp];
      rg = clR[temp];
      temp += numChars;

      lt = clL[temp];
      rt = clR[temp];
      temp += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[0] + lc*m_tiPL[1] + lg*m_tiPL[2] + lt*m_tiPL[3]) * 
	(ra*m_tiPR[0] + rc*m_tiPR[1] + rg*m_tiPR[2] + rt*m_tiPR[3]);
      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[4] + lc*m_tiPL[5] + lg*m_tiPL[6] + lt*m_tiPL[7]) * 
	(ra*m_tiPR[4] + rc*m_tiPR[5] + rg*m_tiPR[6] + rt*m_tiPR[7]);
      clp_idx += numChars;

      clP[clp_idx] =
	(la*m_tiPL[8] + lc*m_tiPL[9] + lg*m_tiPL[10] + lt*m_tiPL[11]) * 
	(ra*m_tiPR[8] + rc*m_tiPR[9] + rg*m_tiPR[10] + rt*m_tiPR[11]);
      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[12] + lc*m_tiPL[13] + lg*m_tiPL[14] + lt*m_tiPL[15]) * 
	(ra*m_tiPR[12] + rc*m_tiPR[13] + rg*m_tiPR[14] + rt*m_tiPR[15]);
      clp_idx += numChars;
    }

  clp_idx = 64*blockIdx.x + tid;
  treeScaler = lnScaler[char_idx];
  nodeScalerOld = scPOld[char_idx];
  lnScaler[char_idx] = treeScaler - nodeScalerOld; 
}

__global__ void gpu_down_0_gammaCats_4_s2(CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *tiPL, CLFlt *tiPR, CLFlt *lnScaler, CLFlt *scPNew)
{
  int modelStat, gammaCat, tid_y, tid, clp_idx, temp, idx, char_idx;
  CLFlt la, lc, lg, lt, ra, rc, rg, rt;
  CLFlt *m_tiPL, *m_tiPR;
  CLFlt treeScaler, scaler=0.0, r_scaler;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  char_idx = clp_idx;
  temp = clp_idx;

  __shared__ CLFlt s_tiPL[64];
  __shared__ CLFlt s_tiPR[64];
  s_tiPL[tid] = tiPL[tid];
  s_tiPR[tid] = tiPR[tid];

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      m_tiPL = &s_tiPL[16*idx];
      m_tiPR = &s_tiPR[16*idx];

      la = clL[temp]; 
      ra = clR[temp]; 
      temp += numChars;

      lc = clL[temp];
      rc = clR[temp];
      temp += numChars;

      lg = clL[temp];
      rg = clR[temp];
      temp += numChars;

      lt = clL[temp];
      rt = clR[temp];
      temp += numChars;
      

      r_scaler = 
	(la*m_tiPL[0] + lc*m_tiPL[1] + lg*m_tiPL[2] + lt*m_tiPL[3]) * 
	(ra*m_tiPR[0] + rc*m_tiPR[1] + rg*m_tiPR[2] + rt*m_tiPR[3]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = 
	(la*m_tiPL[4] + lc*m_tiPL[5] + lg*m_tiPL[6] + lt*m_tiPL[7]) * 
	(ra*m_tiPR[4] + rc*m_tiPR[5] + rg*m_tiPR[6] + rt*m_tiPR[7]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = 
	(la*m_tiPL[8] + lc*m_tiPL[9] + lg*m_tiPL[10] + lt*m_tiPL[11]) * 
	(ra*m_tiPR[8] + rc*m_tiPR[9] + rg*m_tiPR[10] + rt*m_tiPR[11]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;

      r_scaler = 
	(la*m_tiPL[12] + lc*m_tiPL[13] + lg*m_tiPL[14] + lt*m_tiPL[15]) * 
	(ra*m_tiPR[12] + rc*m_tiPR[13] + rg*m_tiPR[14] + rt*m_tiPR[15]);
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      if (r_scaler > scaler) scaler = r_scaler;
    }

  clp_idx = 64*blockIdx.x + tid;
  gpu_scale_clP(clP, clp_idx, scaler, numChars);
  treeScaler = lnScaler[char_idx];
  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] = treeScaler + r_scaler; 
}


__global__ void gpu_down_0_gammaCats_4(CLFlt *clP, CLFlt *clL, CLFlt *clR, CLFlt *tiPL, CLFlt *tiPR)
{
  int modelStat, gammaCat, tid_y, tid, clp_idx, temp, idx;
  CLFlt la, lc, lg, lt, ra, rc, rg, rt;
  CLFlt *m_tiPL, *m_tiPR;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  clp_idx = 64*blockIdx.x + tid;
  temp = clp_idx;

  __shared__ CLFlt s_tiPL[64];
  __shared__ CLFlt s_tiPR[64];
  s_tiPL[tid] = tiPL[tid];
  s_tiPR[tid] = tiPR[tid];

  __shared__ int numChars;
  numChars = 64 * gridDim.x;

  __syncthreads();

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      m_tiPL = &s_tiPL[16*idx];
      m_tiPR = &s_tiPR[16*idx];

      la = clL[temp]; 
      ra = clR[temp]; 
      temp += numChars;

      lc = clL[temp];
      rc = clR[temp];
      temp += numChars;

      lg = clL[temp];
      rg = clR[temp];
      temp += numChars;

      lt = clL[temp];
      rt = clR[temp];
      temp += numChars;
      
      clP[clp_idx] = 
	(la*m_tiPL[0] + lc*m_tiPL[1] + lg*m_tiPL[2] + lt*m_tiPL[3]) * 
	(ra*m_tiPR[0] + rc*m_tiPR[1] + rg*m_tiPR[2] + rt*m_tiPR[3]);

      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[4] + lc*m_tiPL[5] + lg*m_tiPL[6] + lt*m_tiPL[7]) * 
	(ra*m_tiPR[4] + rc*m_tiPR[5] + rg*m_tiPR[6] + rt*m_tiPR[7]);

      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[8] + lc*m_tiPL[9] + lg*m_tiPL[10] + lt*m_tiPL[11]) * 
	(ra*m_tiPR[8] + rc*m_tiPR[9] + rg*m_tiPR[10] + rt*m_tiPR[11]);

      clp_idx += numChars;

      clP[clp_idx] = 
	(la*m_tiPL[12] + lc*m_tiPL[13] + lg*m_tiPL[14] + lt*m_tiPL[15]) * 
	(ra*m_tiPR[12] + rc*m_tiPR[13] + rg*m_tiPR[14] + rt*m_tiPR[15]);

      clp_idx += numChars;
    }

}

extern "C" void down_0(int offset_clP, int offset_clL, int offset_clR, int offset_pL, int offset_pR, int modelnumChars, int modelnumGammaCats, int chain, int offset_lnScaler, int offset_scPOld, int offset_scPNew, int scaler_shortcut)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, 4);

  if (scaler_shortcut == 3)
    {
      gpu_down_0_gammaCats_4_s3<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld, devnodeScalerSpace+offset_scPNew);
    }
  else if (scaler_shortcut == 2)
    {
      gpu_down_0_gammaCats_4_s2<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPNew);
      
    }
  else if (scaler_shortcut == 1)
    {
      gpu_down_0_gammaCats_4_s1<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld);
    }
  else
    gpu_down_0_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devCondLikes+offset_clL, devCondLikes+offset_clR, devtiProbSpace+offset_pL, devtiProbSpace+offset_pR);
}


__global__ void gpu_scaler_2_gen(CLFlt *clP, CLFlt *lnScaler, CLFlt *scPNew) 
{
  int gid = blockIdx.x;
  int gamma = threadIdx.y;  
  int state_idx = 64 * gid + 16 * gamma + threadIdx.x;
  int numChars = 64 * gridDim.x;
  int i, k;
  CLFlt scaler = 0.0, r_scaler;
  CLFlt *p_clP = clP + state_idx;
  
  for (k=0; k<4; k++)
    {
      for (i=0; i<20; i++)
	{
	  r_scaler = p_clP[i*numChars];
	  if (r_scaler > scaler) 
	    scaler = r_scaler;
	}
      p_clP += 20*numChars;
    }

  p_clP = clP + state_idx;
  for (k=0; k<4; k++)
    {
      for (i=0; i<20; i++)
	{
	  r_scaler = p_clP[i*numChars];
	  r_scaler /= scaler;
	  p_clP[i*numChars] = r_scaler;
	}
      p_clP += 20*numChars;
    }

  r_scaler = (CLFlt)log(scaler);
  scPNew[state_idx] = r_scaler;
  lnScaler[state_idx] += r_scaler; 
}

extern "C" void scaler_2_gen (int offset_clP, int offset_lnScaler, int offset_scPNew, int modelnumChars, int modelnumGammaCats, int chain)
{
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(16, 4);

  gpu_scaler_2_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPNew);
}


__global__ void gpu_scaler_1_gen(CLFlt *lnScaler, CLFlt *scPOld)
{
  int tid = 16*threadIdx.y + threadIdx.x;
  int char_idx = 64*blockIdx.x + tid;
  lnScaler[char_idx] -= scPOld[char_idx];
}

extern "C" void scaler_1_gen (int offset_lnScaler, int offset_scPOld, int modelnumChars, int chain)
{
  //printf("scaler1\n");
  dim3	dimGrid(globaldevChars/64, 1);
  dim3	dimBlock(16, 4);

  gpu_scaler_1_gen<<<dimGrid, dimBlock, 0, stream[chain]>>>(devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld);
}

__global__ void gpu_scaler_1(CLFlt *lnScaler, CLFlt *scPOld)
{
  int tid = 16*threadIdx.z + 4*threadIdx.y + threadIdx.x;
  int char_idx = 64*blockIdx.x + tid;
  lnScaler[char_idx] -= scPOld[char_idx];
}

extern "C" void scaler_1 (int offset_lnScaler, int offset_scPOld, int modelnumChars, int chain)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, 4);

  gpu_scaler_1<<<dimGrid, dimBlock, 0, stream[chain]>>>(devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPOld);
}

__global__ void gpu_scaler_2_gammaCats_4(CLFlt *clP, CLFlt *lnScaler, CLFlt *scPNew) 
{
  int gammaCat, tid_y, modelStat, tid, char_offset, char_idx, clp_idx, temp, idx;
  CLFlt scaler=0.0, r_scaler;

  modelStat = threadIdx.x;
  tid_y = threadIdx.y;
  gammaCat = threadIdx.z;
  tid = 16*gammaCat + 4*tid_y + modelStat; 
  char_offset = 64*blockIdx.x;
  clp_idx = temp = char_idx = char_offset + tid;
  
  __shared__ int numChars;
  numChars = 64 * gridDim.x;

#pragma unroll 4
  
  for (idx=0; idx<4; idx++)
    {
      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler) 
	scaler = r_scaler;

      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler)
	scaler = r_scaler;

      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler)
	scaler = r_scaler;

      r_scaler = clP[temp];
      temp += numChars;
      if (r_scaler > scaler)
	scaler = r_scaler;
    }

#pragma unroll 4

  for (idx=0; idx<4; idx++)
    {
      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;

      r_scaler = clP[clp_idx];
      r_scaler /= scaler;
      clP[clp_idx] = r_scaler;
      clp_idx += numChars;
    }

  r_scaler = (CLFlt)log(scaler);
  scPNew[char_idx] = r_scaler;
  lnScaler[char_idx] += r_scaler; 
}


extern "C" void scaler_2 (int offset_clP, int offset_lnScaler, int offset_scPNew, int modelnumChars, int modelnumGammaCats, int chain)
{
  dim3	dimGrid(globaldevChars/64, 1, 1);
  dim3	dimBlock(4, 4, modelnumGammaCats);

  gpu_scaler_2_gammaCats_4<<<dimGrid, dimBlock, 0, stream[chain]>>>(devCondLikes+offset_clP, devtreeScalerSpace+offset_lnScaler, devnodeScalerSpace+offset_scPNew);
}

