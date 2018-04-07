#
# BUILD CONFIGURATION VARIABLES
#

# Set to 1 or ON to build with NVTX support
USENVTX=0

# By default 0 means Release, set to "Debug" if you want to compile sources with debug flags
CMAKE_BUILD_TYPE=0

$(warning USENVTX is $(USENVTX))
$(warning CMAKE_BUILD_TYPE is $(CMAKE_BUILD_TYPE))

#
# PROJECT DEPENDENCY RELATED VARIABLES
#

# Location of local directory with dependencies
DEPS_DIR = deps

# NCCL support in XGBoost. To turn off set USENCCL=0 during build
USENCCL=1

# By default build both CPU and GPU variant
USECUDA=1

ifeq ($(USECUDA), 0)
    $(warning Building with only CPU support ON.)
    XGBOOST_TARGET=libxgboost-cpu
else
    ifeq ($(USENCCL), 0)
        $(warning XGBoost NCCL support is OFF.)
        XGBOOST_TARGET=libxgboost2
    else
        $(warning XGBoost NCCL support is ON.)
        XGBOOST_TARGET=libxgboost
    endif
    CUDA_LIB=$(CUDA_HOME)/lib64
    CUDA_VERSION ?= $(shell ls $(CUDA_LIB)/libcudart.so.* | head -1 | rev | cut -d "." -f -2 | rev)
    CUDA_MAJOR_VERSION = $(shell echo $(CUDA_VERSION) | cut -d "." -f 1)
endif

# PyDataTable version. Currently not used in the code.
#PYDATATABLE_VERSION = 0.1.0+master.97

#
# TEST DATA VARIABLES
#

# Location of datasets
SMALLDATA_BUCKET = s3://h2o-public-test-data/smalldata

# Location of other datasets that we add for h2o4gpu testing (ipums, bnp, etc)
DATA_BUCKET = s3://h2o-datasets/h2o4gpu/data

# Location of local directory with data
DATA_DIR = data

# Location of open data
OPEN_DATA_BUCKET = s3://h2o-public-test-data/h2o4gpu/open_data

# Location of local directory with open data
OPEN_DATA_DIR = open_data

#
# R PACKAGE CONFIGURATIONS
#
INSTALL_R = 1
R_VERSION = 3.1.0

#
# VARIABLES USED DURING BUILD - YOU PROBABLY DON'T WANT TO CHANGE THESE
#

# Build version
MAJOR_MINOR=$(shell echo $(BASE_VERSION) | sed 's/.*\(^[0-9][0-9]*\.[0-9][0-9]*\).*/\1/g' )

# OS info for Python
# Python has crazy ideas about os names
OS := $(shell uname)
ifeq ($(OS), Darwin)
    PY_OS ?= "macosx"
else
	PY_OS ?= $(OS)
endif

PYTHON ?= python

# UUID for logs
RANDOM := $(shell bash -c 'echo $$RANDOM')
LOGEXT=$(RANDOM)$(shell date +'_%Y.%m.%d-%H:%M:%S')

# Utilize all procs in certain tasks
NUMPROCS := $(shell cat /proc/cpuinfo|grep processor|wc -l)

# Docker image tagging
DOCKER_VERSION_TAG ?= "latest"

# BUILD_INFO setup
H2O4GPU_COMMIT ?= $(shell git rev-parse HEAD)
H2O4GPU_BUILD_DATE := $(shell date)
H2O4GPU_BUILD ?= "LOCAL BUILD @ $(shell git rev-parse --short HEAD) build at $(H2O4GPU_BUILD_DATE)"
H2O4GPU_SUFFIX ?= "+local_$(shell git describe --always --dirty)"

# Setup S3 access credentials
S3_CMD_LINE := aws s3

DIST_DIR = dist

ARCH := $(shell arch)
ifdef CUDA_MAJOR_VERSION
    PLATFORM = $(ARCH)-centos7-cuda$(CUDA_MAJOR_VERSION)
else
    PLATFORM = $(ARCH)-centos7-cpu
endif

#
# Find NVML library
#
ARCH_LONG       := $(shell getconf LONG_BIT)
OS         := $(shell cat /etc/issue)
RHEL_OS    := $(shell cat /etc/redhat-release)

# Gets Driver Branch
DRIVER_BRANCH := $(shell nvidia-smi | grep Driver | cut -f 3 -d' ' | cut -f 1 -d '.')

ifeq (${ARCH_LONG},$(filter ${ARCH_LONG},32 64))
    # If correct architecture and libnvidia-ml library is not found
    # within the environment, build using the stub library

    ifneq (,$(findstring Ubuntu,$(OS)))
        DEB := $(shell dpkg -l | grep cuda)
        ifneq (,$(findstring cuda, $(DEB)))
            NVML_LIB := /usr/lib/nvidia-$(DRIVER_BRANCH)
        else
            NVML_LIB := /lib${ARCH_LONG}
        endif
    endif

    ifneq (,$(findstring SUSE,$(OS)))
        RPM := $(shell rpm -qa cuda*)
        ifneq (,$(findstring cuda, $(RPM)))
            NVML_LIB := /usr/lib${ARCH_LONG}
        else
            NVML_LIB := /lib${ARCH_LONG}
        endif
    endif

    ifneq (,$(findstring CentOS,$(RHEL_OS)))
        RPM := $(shell rpm -qa cuda*)
        ifneq (,$(findstring cuda, $(RPM)))
            NVML_LIB := /usr/lib${ARCH_LONG}/nvidia
        else
            NVML_LIB := /lib${ARCH_LONG}
        endif
    endif

    ifneq (,$(findstring Red Hat,$(RHEL_OS)))
        RPM := $(shell rpm -qa cuda*)
        ifneq (,$(findstring cuda, $(RPM)))
            NVML_LIB := /usr/lib${ARCH_LONG}/nvidia
        else
            NVML_LIB := /lib${ARCH_LONG}
        endif
    endif

    ifneq (,$(findstring Fedora,$(RHEL_OS)))
        RPM := $(shell rpm -qa cuda*)
        ifneq (,$(findstring cuda, $(RPM)))
            NVML_LIB := /usr/lib${ARCH_LONG}/nvidia
        else
            NVML_LIB := /lib${ARCH_LONG}
        endif
    endif

else
    NVML_LIB := ../../lib${ARCH_LONG}/stubs/
    $(info "libnvidia-ml.so.1" not found, using stub library.)
endif

ifneq (${ARCH_LONG},$(filter ${ARCH_LONG},32 64))
	$(error Unknown architecture!)
endif

$(warning Compiling with ARCH_LONG=$(ARCH_LONG))
$(warning Compiling with OS=$(OS))
$(warning Compiling with RHEL_OS=$(RHEL_OS))
$(warning Compiling with NVML_LIB=$(NVML_LIB))
