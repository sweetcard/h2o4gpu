include make/Makefile_header.mk

include make/version.mk
include make/config.mk

help:
	$(call inform, " -------- Test data sync ---------")
	$(call inform, "make sync_open_data  Downloads the test data.")
	$(call inform, "make sync_small_data Downloads the small test data.")
	$(call inform, " -------- Build and Install ---------")
	$(call inform, "make clean           Clean all build files.")
	$(call inform, "make                 fullinstall")
	$(call inform, "make fullinstall     Clean everything then compile and install everything (for cuda9 with nccl in xgboost).")
	$(call inform, "make build           Just Build the whole project.")
	$(call inform, " -------- Test ---------")
	$(call inform, "make test            Run tests.")
	$(call inform, "make testbig         Run tests for big data.")
	$(call inform, "make testperf        Run performance and accuracy tests.")
	$(call inform, "make testbigperf     Run performance and accuracy tests for big data.")
	$(call inform, " -------- Docker ---------")
	$(call inform, "make docker-build    Build inside docker and save wheel to src/interface_py/dist?/ (for cuda9 with nccl in xgboost).")
	$(call inform, "make docker-runtime  Build runtime docker and save to local path (for cuda9 with nccl in xgboost).")
	$(call inform, "make get_docker      Download runtime docker (e.g. instead of building it)")
	$(call inform, "make load_docker     Load runtime docker image")
	$(call inform, "make run_in_docker   Run jupyter notebook demo using runtime docker image already present")
	$(call inform, "make docker-runtests Run tests in docker")
	$(call inform, " -------- Pycharm Help ---------")
	$(call inform, "Example Pycharm environment flags: PYTHONPATH=/home/jon/h2o4gpu/src/interface_py:/home/jon/h2o4gpu;PYTHONUNBUFFERED=1;LD_LIBRARY_PATH=/opt/clang+llvm-4.0.0-x86_64-linux-gnu-ubuntu-16.04//lib/:/home/jon/lib:/opt/rstudio-1.0.136/bin/:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64::/home/jon/lib/:$LD_LIBRARY_PATH;LLVM4=/opt/clang+llvm-4.0.0-x86_64-linux-gnu-ubuntu-16.04/")
	$(call inform, "Example Pycharm working directory: /home/jon/h2o4gpu/")

default: fullinstall

#########################################
# DATA TARGETS
#########################################

sync_small_data:
	@echo "---- Synchronizing test data ----"
	mkdir -p $(DATA_DIR)
	$(S3_CMD_LINE) sync --no-sign-request "$(SMALLDATA_BUCKET)" "$(DATA_DIR)"

sync_other_data:
	@echo "---- Synchronizing data dir in test/ ----"
	mkdir -p $(DATA_DIR) && $(S3_CMD_LINE) sync "$(DATA_BUCKET)" "$(DATA_DIR)"

sync_open_data:
	@echo "---- Synchronizing sklearn and other open data in home directory ----"
	mkdir -p $(OPEN_DATA_DIR)
	$(S3_CMD_LINE) sync --no-sign-request "$(OPEN_DATA_BUCKET)" "$(OPEN_DATA_DIR)"

#########################################
# DEPENDENCY MANAGEMENT TARGETS
#########################################

alldeps-install: deps_install fullinstall-xgboost libsklearn

alldeps: deps_fetch alldeps-install

deps_fetch:
	@echo "---- Fetch dependencies ---- "
	bash scripts/gitshallow_submodules.sh
	git submodule update

deps_install:
	@echo "---- Install dependencies ----"
	#-xargs -a requirements.txt -n 1 -P 1 $(PYTHON) -m pip install
	easy_install pip
	easy_install setuptools
	cat src/interface_py/requirements_buildonly.txt src/interface_py/requirements_runtime.txt > requirements.txt
	$(PYTHON) -m pip install -r requirements.txt
	rm -rf requirements.txt
	bash scripts/install_r_deps.sh

#########################################
# SUBMODULE BUILD TARGETS
#########################################

update_submodule:
	echo ADD UPDATE SUBMODULE HERE

cpp:
	mkdir -p build && \
	cd build && \
	cmake -DDEV_BUILD=${DEV_BUILD} -DNVML_LIB=$(NVML_LIB)/libnvidia-ml.so ../ && \
	make -j && \
	cp _ch2o4gpu_*pu.so ../src/interface_c/ && \
	cp ch2o4gpu_*pu.py ../src/interface_py/h2o4gpu/libs;

py: apply-sklearn_simple build/VERSION.txt
	$(MAKE) -j all -C src/interface_py

.PHONY: xgboost
xgboost:
	@echo "----- Building XGboost target $(XGBOOST_TARGET) -----"
	cd xgboost ; make -f Makefile2 $(XGBOOST_TARGET)

fullinstall-xgboost: xgboost install_xgboost

#########################################
# SOURCE QUALITY CHECK TARGETS
#########################################

pylint:
	$(MAKE) pylint -C src/interface_py

#########################################
# PROJECT BUILD TARGETS
#########################################

build: update_submodule build_quick

build_quick: cpp py

build_py: update_submodule clean_py py # avoid cpp

#########################################
# INSTALL TARGETS
#########################################

install_xgboost:
	@echo "----- pip install xgboost built locally -----"
	cd xgboost/python-package/dist && $(PYTHON) -m pip install xgboost-0.71-py3-none-any.whl --target ../

install_py:
	$(MAKE) -j install -C src/interface_py

install: install_py

#########################################
# CLEANING TARGETS
#########################################

clean: clean_py3nvml clean_xgboost clean_deps clean_py  clean_cpp
	-rm -rf ./build
	-rm -rf ./results/ ./tmp/

clean_cpp:
	rm -rf src/interface_c/_ch2o4gpu_*pu.so
	rm -rf src/interface_py/h2o4gpu/libs/ch2o4gpu_*pu.py

clean_py:
	$(MAKE) -j clean -C src/interface_py

clean_xgboost:
	-$(PYTHON) -m pip uninstall -y xgboost
	rm -rf xgboost/build/

clean_py3nvml:
	-$(PYTHON) -m pip uninstall -y py3nvml

clean_deps:
	@echo "----- Cleaning dependencies -----"
	rm -rf "$(DEPS_DIR)"
	# sometimes --upgrade leaves extra packages around
	cat src/interface_py/requirements_buildonly.txt src/interface_py/requirements_runtime.txt src/interface_py/requirements_runtime_demos.txt > requirements.txt
	sed 's/==.*//g' requirements.txt|grep -v "#" > requirements_plain.txt
	-xargs -a requirements_plain.txt -n 1 -P $(NUMPROCS) $(PYTHON) -m pip uninstall -y
	rm -rf requirements_plain.txt requirements.txt

#########################################
# FULL BUILD AND INSTALL TARGETS
#########################################

fullinstall: clean alldeps build install
	mkdir -p src/interface_py/$(DIST_DIR)/$(PLATFORM)/ && mv src/interface_py/dist/*.whl src/interface_py/$(DIST_DIR)/$(PLATFORM)/

buildinstall: alldeps build install
	mkdir -p src/interface_py/$(DIST_DIR)/$(PLATFORM)/ && mv src/interface_py/dist/*.whl src/interface_py/$(DIST_DIR)/$(PLATFORM)/

#########################################
# DOCKER TARGETS
#########################################

DOCKER_CUDA_VERSION?=9

ifeq (${DOCKER_CUDA_VERSION},9)
    DOCKER_CUDNN_VERSION?=7
else
    DOCKER_CUDNN_VERSION?=5
endif

docker-build:
	@echo "+-- Building Wheel in Docker --+"
	rm -rf src/interface_py/dist/*
	export CONTAINER_NAME="local-make-build-cuda$(DOCKER_CUDA_VERSION)" ;\
	export versionTag=$(BASE_VERSION) ;\
	export extratag="-cuda$(DOCKER_CUDA_VERSION)" ;\
	export dockerimage="nvidia/cuda:$(DOCKER_CUDA_VERSION).0-cudnn$(DOCKER_CUDNN_VERSION)-devel-centos7" ;\
	bash scripts/make-docker-devel.sh

docker-runtime:
	@echo "+--Building Runtime Docker Image Part 2 (-nccl-cuda9) --+"
	export CONTAINER_NAME="local-make-runtime-cuda$(DOCKER_CUDA_VERSION)" ;\
	export versionTag=$(BASE_VERSION) ;\
	export extratag="-cuda$(DOCKER_CUDA_VERSION)" ;\
	export fullVersionTag=$(BASE_VERSION) ;\
	export dockerimage="nvidia/cuda:$(DOCKER_CUDA_VERSION).0-cudnn$(DOCKER_CUDNN_VERSION)-runtime-centos7" ;\
	bash scripts/make-docker-runtime.sh

docker-runtime-run:
	@echo "+-Running Docker Runtime Image (-cuda9) --+"
	export fullVersionTag=$(BASE_VERSION) ;\
	nvidia-docker run --init --rm --name "localmake-runtime-run" -d -t -u `id -u`:`id -g` --entrypoint=bash opsh2oai/h2o4gpu-$$(BASE_VERSION)-cuda$(DOCKER_CUDA_VERSION)-runtime:latest

docker-runtests:
	@echo "+-- Run tests in docker (-nccl-cuda9) --+"
	export CONTAINER_NAME="localmake-runtests" ;\
	export extratag="-cuda$(DOCKER_CUDA_VERSION)" ;\
	export dockerimage="nvidia/cuda:$(DOCKER_CUDA_VERSION).0-cudnn$(DOCKER_CUDNN_VERSION)-devel-centos7" ;\
	export target="dotest" ;\
	bash scripts/make-docker-runtests.sh

get_docker:
	wget https://s3.amazonaws.com/h2o-release/h2o4gpu/releases/bleeding-edge/ai/h2o/h2o4gpu/$(MAJOR_MINOR)-cuda$(DOCKER_CUDA_VERSION)/h2o4gpu-$(BASE_VERSION)-cuda$(DOCKER_CUDA_VERSION)-runtime.tar.bz2

docker-runtime-load:
	pbzip2 -dc h2o4gpu-$(BASE_VERSION)-cuda$(DOCKER_CUDA_VERSION)-runtime.tar.bz2 | nvidia-docker load

run_in_docker:
	-mkdir -p log ; nvidia-docker run --name localhost --rm -p 8888:8888 -u `id -u`:`id -g` -v `pwd`/log:/log --entrypoint=./run.sh opsh2oai/h2o4gpu-$(BASE_VERSION)-cuda$(DOCKER_CUDA_VERSION)-runtime &
	-find log -name jupyter* -type f -printf '%T@ %p\n' | sort -k1 -n | awk '{print $2}' | tail -1 | xargs cat | grep token | grep http | grep -v NotebookApp

.PHONY: docker-build  docker-runtime docker-runtime-run docker-runtests get-docker docker-runtime-load run-rin-docker

############### CPU
docker-build-cpu:
	@echo "+-- Building Wheel in Docker (-cpu) --+"
	rm -rf src/interface_py/dist/*.whl ; rm -rf src/interface_py/dist4/*.whl
	export CONTAINER_NAME="localmake-build" ;\
	export versionTag=$(BASE_VERSION) ;\
	export extratag="-cpu" ;\
	export dockerimage="centos:6" ;\
	export H2O4GPU_BUILD="" ;\
	export H2O4GPU_SUFFIX="" ;\
	export makeopts="" ;\
	export dist="dist8" ;\
	bash scripts/make-docker-devel.sh

docker-runtime-cpu:
	@echo "+--Building Runtime Docker Image Part 2 (-cpu) --+"
	export CONTAINER_NAME="localmake-runtime" ;\
	export versionTag=$(BASE_VERSION) ;\
	export extratag="-cpu" ;\
	export encodedFullVersionTag=$(BASE_VERSION) ;\
	export fullVersionTag=$(BASE_VERSION) ;\
	export buckettype="releases/bleeding-edge" ;\
	export dockerimage="centos:6" ;\
	bash scripts/make-docker-runtime.sh

docker-runtime-cpu-run:
	@echo "+-Running Docker Runtime Image (-nccl-cuda9) --+"
	export CONTAINER_NAME="localmake-runtime-run" ;\
	export versionTag=$(BASE_VERSION) ;\
	export extratag="-cpu" ;\
	export encodedFullVersionTag=$(BASE_VERSION) ;\
	export fullVersionTag=$(BASE_VERSION) ;\
	export buckettype="releases/bleeding-edge" ;\
	export dockerimage="centos:6" ;\
	docker run --init --rm --name $${CONTAINER_NAME} -d -t -u `id -u`:`id -g` --entrypoint=bash opsh2oai/h2o4gpu-$${versionTag}$${extratag}-runtime:latest

docker-runtests-cpu:
	@echo "+-- Run tests in docker (-nccl-cuda9) --+"
	export CONTAINER_NAME="localmake-runtests" ;\
	export extratag="-cpu" ;\
	export dockerimage="centos:6" ;\
	export dist="dist4" ;\
	export target="dotest" ;\
	bash scripts/make-docker-runtests.sh

get_docker-cpu:
	wget https://s3.amazonaws.com/h2o-release/h2o4gpu/releases/bleeding-edge/ai/h2o/h2o4gpu/$(MAJOR_MINOR)-cpu/h2o4gpu-$(BASE_VERSION)-cpu-runtime.tar.bz2

docker-runtime-cpu-load:
	pbzip2 -dc h2o4gpu-$(BASE_VERSION)-cpu-runtime.tar.bz2 | docker load

run_in_docker-cpu:
	-mkdir -p log ; docker run --name localhost --rm -p 8888:8888 -u `id -u`:`id -g` -v `pwd`/log:/log --entrypoint=./run.sh opsh2oai/h2o4gpu-$(BASE_VERSION)-cpu-runtime &
	-find log -name jupyter* -type f -printf '%T@ %p\n' | sort -k1 -n | awk '{print $2}' | tail -1 | xargs cat | grep token | grep http | grep -v NotebookApp


#########################################
# TARGETS INSTALLING LIBRARIES
#########################################

# http://developer2.download.nvidia.com/compute/cuda/9.0/secure/rc/docs/sidebar/CUDA_Quick_Start_Guide.pdf?_ZyOB0PlGZzBUluXp3FtoWC-LMsTsc5H6SxIaU0i9pGNyWzZCgE-mhnAg2m66Nc3WMDvxWvvQWsXGMqr1hUliGOZvoothMTVnDe12dQQgxwS4Asjoz8XiOvPYOjV6yVQtkFhvDztUlJbNSD4srPWUU2-XegCRFII8_FIpxXERaWV
libcuda9:
	# wget https://developer.nvidia.com/compute/cuda/9.0/rc/local_installers/cuda-repo-ubuntu1604-9-0-local-rc_9.0.103-1_amd64-deb
	sudo dpkg --install cuda-repo-ubuntu1604-9-0-local-rc_9.0.103-1_amd64.deb
	# wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
	sudo apt-key add 7fa2af80.pub
	sudo apt-get update
	sudo apt-get install cuda

# http://docs.nvidia.com/deeplearning/sdk/nccl-install-guide/index.html
libnccl2:
	# cuda8 nccl2
	#wget https://developer.nvidia.com/compute/machine-learning/nccl/secure/v2.0/prod/nccl-repo-ubuntu1604-2.0.5-ga-cuda8.0_2-1_amd64-deb
	# cuda9 nccl2
	# wget https://developer.nvidia.com/compute/machine-learning/nccl/secure/v2.0/prod/nccl-repo-ubuntu1604-2.0.5-ga-cuda9.0_2-1_amd64-deb
	sudo dpkg -i nccl-repo-ubuntu1604-2.0.5-ga-cuda9.0_2-1_amd64.deb
	sudo apt update
	sudo apt-key add /var/nccl-repo-2.0.5-ga-cuda9.0/7fa2af80.pub
	sudo apt install libnccl2 libnccl-dev

liblightgbm: # only done if user directly requests, never an explicit dependency
	echo "See https://github.com/Microsoft/LightGBM/wiki/Installation-Guide#with-gpu-support for details"
	echo "sudo apt-get install libboost-dev libboost-system-dev libboost-filesystem-dev cmake"
	rm -rf LightGBM ; result=`git clone --recursive https://github.com/Microsoft/LightGBM`
	cd LightGBM && mkdir build ; cd build && cmake .. -DUSE_GPU=1 -DOpenCL_LIBRARY=$(CUDA_HOME)/lib64/libOpenCL.so -DOpenCL_INCLUDE_DIR=$(CUDA_HOME)/include/ && make -j && cd ../python-package ; $(PYTHON) setup.py install --precompile --gpu && cd ../ && $(PYTHON) -m pip install arff tqdm keras runipy h5py

libsklearn:	# assume already submodule gets sklearn
	@echo "----- Make sklearn wheel -----"
	bash scripts/prepare_sklearn.sh # repeated calls don't hurt
	rm -rf sklearn && mkdir -p sklearn && cd scikit-learn && $(PYTHON) setup.py sdist bdist_wheel

apply-sklearn: libsklearn apply-sklearn_simple

apply-sklearn_simple:
    #	bash ./scripts/apply_sklearn.sh
    ## apply sklearn
	bash ./scripts/apply_sklearn_pipinstall.sh
    ## link-up recursively
	bash ./scripts/apply_sklearn_link.sh
    # handle base __init__.py file appending
	bash ./scripts/apply_sklearn_initmerge.sh

apply-sklearn_pipinstall:
	bash ./scripts/apply_sklearn_pipinstall.sh

apply-sklearn_link:
	bash ./scripts/apply_sklearn_link.sh

apply-sklearn_initmerge:
	bash ./scripts/apply_sklearn_initmerge.sh

.PHONY: mrproper
mrproper: clean
	@echo "----- Cleaning properly -----"
	git clean -f -d -x

#########################################
# TEST TARGETS
#########################################

#WIP
dotestdemos:
	rm -rf ./tmp/
	mkdir -p ./tmp/
	bash scripts/convert_ipynb2py.sh
    # can't do -n auto due to limits on GPU memory
	#pytest -s --verbose --durations=10 -n 1 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-test.xml examples/py 2> ./tmp/h2o4gpu-examplespy.$(LOGEXT).log
	-$(PYTHON) -m pip install pytest-ipynb # can't put in requirements since problem with jenkins and runipy
	py.test -v -s examples/py 2> ./tmp/h2o4gpu-examplespy.$(LOGEXT).log


dotest:
	rm -rf ./tmp/
	mkdir -p ./tmp/
  # can't do -n auto due to limits on GPU memory
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-test.xml tests/python/open_data 2> ./tmp/h2o4gpu-test.$(LOGEXT).log
	# Test R package when appropriate
	bash scripts/test_r_pkg.sh

dotestfast:
	rm -rf ./tmp/
	mkdir -p ./tmp/
    # can't do -n auto due to limits on GPU memory
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast1.xml tests/python/open_data/glm/test_glm_simple.py 2> ./tmp/h2o4gpu-testfast1.$(LOGEXT).log
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast2.xml tests/python/open_data/gbm/test_xgb_sklearn_wrapper.py 2> ./tmp/h2o4gpu-testfast2.$(LOGEXT).log
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast3.xml tests/python/open_data/svd/test_tsvd.py 2> ./tmp/h2o4gpu-testfast3.$(LOGEXT).log
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast4.xml tests/python/open_data/kmeans/test_kmeans.py 2> ./tmp/h2o4gpu-testfast4.$(LOGEXT).log

dotestfast_nonccl:
	rm -rf ./tmp/
	mkdir -p ./tmp/
	# can't do -n auto due to limits on GPU memory
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast1.xml tests/python/open_data/glm/test_glm_simple.py 2> ./tmp/h2o4gpu-testfast1.$(LOGEXT).log
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast3.xml tests/python/open_data/svd/test_tsvd.py 2> ./tmp/h2o4gpu-testfast3.$(LOGEXT).log
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testfast4.xml tests/python/open_data/kmeans/test_kmeans.py 2> ./tmp/h2o4gpu-testfast4.$(LOGEXT).log

dotestsmall:
	rm -rf ./tmp/
	rm -rf build/test-reports 2>/dev/null
	mkdir -p ./tmp/
    # can't do -n auto due to limits on GPU memory
	pytest -s --verbose --durations=10 -n 3 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testsmall.xml tests/python/small 2> ./tmp/h2o4gpu-testsmall.$(LOGEXT).log

dotestbig:
	mkdir -p ./tmp/
	pytest -s --verbose --durations=10 -n 1 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testbig.xml tests/python/big 2> ./tmp/h2o4gpu-testbig.$(LOGEXT).log

#########################################
# BENCHMARKING TARGETS
#########################################

dotestperf:
	mkdir -p ./tmp/
	-CHECKPERFORMANCE=1 DISABLEPYTEST=1 pytest -s --verbose --durations=10 -n 1 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-test.xml tests/python/open_data 2> ./tmp/h2o4gpu-testperf.$(LOGEXT).log
	bash tests/python/open_data/showresults.sh &> ./tmp/h2o4gpu-testperf-results.$(LOGEXT).log

dotestsmallperf:
	mkdir -p ./tmp/
	-CHECKPERFORMANCE=1 DISABLEPYTEST=1 pytest -s --verbose --durations=10 -n 1 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testsmallperf.xml tests/python/small 2> ./tmp/h2o4gpu-testsmallperf.$(LOGEXT).log
	bash tests/python/open_data/showresults.sh &> ./tmp/h2o4gpu-testsmallperf-results.$(LOGEXT).log

dotestbigperf:
	mkdir -p ./tmp/
	-CHECKPERFORMANCE=1 DISABLEPYTEST=1 pytest -s --verbose --durations=10 -n 1 --fulltrace --full-trace --junit-xml=build/test-reports/h2o4gpu-testbigperf.xml tests/python/big 2> ./tmp/h2o4gpu-testbigperf.$(LOGEXT).log
	bash tests/python/open_data/showresults.sh  &> ./tmp/h2o4gpu-testbigperf-results.$(LOGEXT).log # still just references results directory in base path

######################### use python instead of pytest (required in some cases if pytest leads to hang)

dotestperfpython:
	mkdir -p ./tmp/
	-bash tests/python/open_data/getresults.sh $(LOGEXT)
	bash tests/python/open_data/showresults.sh

dotestbigperfpython:
	mkdir -p ./tmp/
	-bash testsbig/getresultsbig.sh $(LOGEXT)
	bash tests/python/open_data/showresults.sh # still just references results directory in base path

################### H2O.ai public tests for pass/fail

testdemos: dotestdemos

test: build_quick dotest

testquick: dotest

################ H2O.ai public tests for performance

testperf: build_quick dotestperf # faster if also run sync_open_data before doing this test

################### H2O.ai private tests for pass/fail

testsmall: build_quick sync_open_data sync_other_data dotestsmall

testsmallquick: dotestsmall

testbig: build_quick sync_open_data sync_other_data dotestbig

testbigquick: dotestbig

################ H2O.ai private tests for performance

testsmallperf: build_quick sync_open_data sync_other_data dotestsmallperf

testbigperf: build_quick sync_open_data sync_other_data dotestbigperf

testsmallperfquick: dotestsmallperf

testbigperfquick: dotestbigperf

#################### CPP Tests

test_cpp:
	$(MAKE) -j test_cpp -C src/

clean_test_cpp:
	$(MAKE) -j clean_cpp_tests -C src/

#########################################
# BUILD INFO TARGETS
#########################################

# Generate local build info
src/interface_py/h2o4gpu/BUILD_INFO.txt:
	@echo "build=\"$(H2O4GPU_BUILD)\"" > $@
	@echo "suffix=\"$(H2O4GPU_SUFFIX)\"" >> $@
	@echo "commit=\"$(H2O4GPU_COMMIT)\"" >> $@
	@echo "branch=\"`git rev-parse HEAD | git branch -a --contains | grep -v detached | sed -e 's~remotes/origin/~~g' -e 's~^ *~~' | sort | uniq | tr '*\n' ' '`\"" >> $@
	@echo "describe=\"`git describe --always --dirty`\"" >> $@
	@echo "build_os=\"`uname -a`\"" >> $@
	@echo "build_machine=\"`hostname`\"" >> $@
	@echo "build_date=\"$(H2O4GPU_BUILD_DATE)\"" >> $@
	@echo "build_user=\"`id -u -n`\"" >> $@
	@echo "base_version=\"$(BASE_VERSION)\"" >> $@
	@echo "h2o4gpu_commit=\"$(H2O4GPU_COMMIT)\"" >> $@

build/VERSION.txt: src/interface_py/h2o4gpu/BUILD_INFO.txt
	@mkdir -p build
	cd src/interface_py/; $(PYTHON) setup.py --version > ../../build/VERSION.txt

.PHONY: base_version
base_version:
	@echo $(BASE_VERSION)

# Refresh the build info only locally, let Jenkins to generate its own
ifeq ($(CI),)
src/interface_py/h2o4gpu/BUILD_INFO.txt: .ALWAYS_REBUILD
endif

Jenkinsfiles:
	bash scripts/make_jenkinsfiles.sh

.PHONY: ALWAYS_REBUILD
.ALWAYS_REBUILD:
