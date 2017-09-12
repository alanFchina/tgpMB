extern int globalnumGammaCats;
extern int globalnumModelStates;
extern int condLikeRowSize;

extern int	numCondLikes;
extern int 	condLikeLength;
extern CLFlt 	**condLikes;
extern MrBFlt	*globallnL;
extern MrBFlt	*invCondLikes;
extern CLFlt	*nodeScalerSpace;
extern int	numCompressedChars;
extern int	numCurrentDivisions;
extern int	numLocalChains;
extern int	numLocalTaxa;
extern CLFlt	*numSitesOfPat;
extern CLFlt	*termCondLikes;
extern int	*termState;
extern int	tiProbRowSize;
extern CLFlt	*tiProbSpace;
extern CLFlt	*treeScalerSpace;
extern int 	globalinvCondLikeSize;
extern int 	globalnScalerNodes;
extern int 	globalnNodes;
extern Chain	chainParams;


static int blockDim_z;
static int gridDim_x;
static CLFlt 	*devCondLikes;
static MrBFlt	*devinvCondLikes;
static MrBFlt	*devlnL;
static CLFlt	*devnodeScalerSpace;
static CLFlt	*devnumSitesOfPat;
static int	*devtermState;
static CLFlt	*devtiProbSpace;
static CLFlt	*devtreeScalerSpace;

/*CL for testing*/
static CLFlt  	*devCL;
CLFlt *hostCL;



cudaStream_t	*stream;
int globaldevChars;
int      globaldevCondLikeLength;
int globaldevCondLikeRowSize;
int globaldevInvCondLikeSize;
MrBFlt *devBaseFreq;
