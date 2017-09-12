CUDA_INSTALL_PATH = /usr/local/cuda
SDK_INSTALL_PATH = /home/ling/NVIDIA_CUDA-7.5_Samples

CUDA_ARCH   	=   sm_35
NVCC		=	$(CUDA_INSTALL_PATH)/bin/nvcc   --compiler-options -fno-strict-aliasing -arch=$(CUDA_ARCH)  -I. -I$(CUDA_INSTALL_PATH)/include -I$(SDK_INSTALL_PATH)/common/inc -D_FORCE_INLINES

NVLIBS		=	-lcuda -lcudart -lGL -L/usr/local/cuda/lib64

ARCHITECTURE	?=	unix

CUDA		?= 	yes

MPI		?=	no

GPROF		?=	no

DEBUG		?=	no

OPTFLAGS	?=	-O3

CC		=	gcc

ifeq ($(strip $(ARCHITECTURE)), unix)
	USEREADLINE	?=	yes
else
	USEREADLINE	?=	no
endif

ifeq ($(strip $(ARCHITECTURE)), unix)
	CFLAGS	+=	-DUNIX_VERSION
endif

ifeq ($(strip $(USEREADLINE)), yes)
	CFLAGS	+=	-DUSE_READLINE
	LIBS	+=	-lncurses -lreadline
endif

ifeq ($(strip $(CUDA)), yes)
	CFLAGS	+=	-DCUDA
	LDFLAGS	+=	-fPIC
	LIBS	+=	$(NVLIBS)
	OBJECTS	+=	cuda.o
	CUFILES	+=	cuda.cu mb.h
	GPROF	=	no
endif

ifeq ($(strip $(MPI)), yes)
	CFLAGS	+=	-DMPI_ENABLED
	CUFLAGS	+=	-DMPI
	CC	=	mpicc
endif

ifeq ($(strip $(GPROF)), yes)
	CFLAGS	+=	-pg
	LIBS	+=	-pg
endif

ifeq ($(strip $(DEBUG)), yes)
	CFLAGS	+=	-ggdb
else
	CFLAGS	+=	$(OPTFLAGS)
	CUFLAGS	+=	$(OPTFLAGS)
endif

CFLAGS	+=	-Wall -Wno-unused-but-set-variable -Wno-unused-result

LIBS	+=	-lm

LDFLAGS	+=	$(CFLAGS)
LDLIBS	=	$(LIBS)

OBJECTS	+= mb.o bayes.o command.o mbmath.o mcmc.o model.o plot.o sump.o sumt.o 

mb : $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) $(LDLIBS) -o mb
ifeq ($(strip $(CUDA)), yes)
cuda.o : $(CUFILES)
	$(NVCC) $(CUFLAGS) -c cuda.cu
endif
mb.o : mb.c mb.h globals.h
	$(CC) $(CFLAGS) -c mb.c
bayes.o : bayes.c mb.h globals.h bayes.h command.h mcmc.o
	$(CC) $(CFLAGS) -c bayes.c
command.o : command.c mb.h globals.h command.h bayes.h model.h mcmc.h plot.h sump.h sumt.h
	$(CC) $(CFLAGS) -c command.c
mbmath.o : mbmath.c mb.h globals.h mbmath.h bayes.h
	$(CC) $(CFLAGS) -c mbmath.c
mcmc.o : mcmc.c mb.h globals.h bayes.h mcmc.h model.h command.h mbmath.h sump.h sumt.h plot.h
	$(CC) $(CFLAGS) -c mcmc.c
model.o : model.c mb.h globals.h bayes.h model.h command.h
	$(CC) $(CFLAGS) -c model.c
plot.o : plot.c mb.h globals.h command.h bayes.h plot.h sump.h
	$(CC) $(CFLAGS) -c plot.c
sump.o : sump.c mb.h globals.h command.h bayes.h sump.h mcmc.h
	$(CC) $(CFLAGS) -c sump.c
sumt.o : sumt.c mb.h globals.h command.h bayes.h mbmath.h sumt.h mcmc.h
	$(CC) $(CFLAGS) -c sumt.c

.PHONY : clean
clean :
	-rm -f mb $(OBJECTS) *.*~ *~
