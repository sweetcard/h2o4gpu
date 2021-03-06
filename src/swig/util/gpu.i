/* File : gpu.i */
%{
extern int cudaresetdevice(int wDev, int nDev);
extern int get_compute_capability(int d_idx, int *major, int *minor, int *ratioperf);
extern void get_gpu_info_c(unsigned int *n_gpus, int *gpu_percent_usage, unsigned long long *gpu_total_memory, unsigned long long *gpu_free_memory, char **gpu_name, int *majors, int *minors);
extern int cudaresetdevice_bare(void);
%}

// Original from http://www.swig.org/Doc1.3/Python.html#Python_nn59
// UNICODE improvements by https://stackoverflow.com/questions/33306957/passing-numpy-string-array-to-c-using-swig
// This tells SWIG to treat char ** as a special case
%typemap(in) char ** {
  /* Check if is a list */
    if (PyList_Check($input)) {
        int size = PyList_Size($input);
        Py_ssize_t i = 0;
        $1 = (char **) malloc((size+1)*sizeof(char *));
        for (i = 0; i < size; i++) {
            PyObject *o = PyList_GetItem($input,i);
            if (PyUnicode_Check(o))
                $1[i] = PyUnicode_AsUTF8(PyList_GetItem($input,i));
            else {
                //PyErr_SetString(PyExc_TypeError,"list must contain strings");
                PyErr_Format(PyExc_TypeError, "list must contain strings. %d/%d element was not string.", i, size);
                free($1);
                return NULL;
            }
        }
        $1[i] = 0;
    } else {
        PyErr_SetString(PyExc_TypeError,"not a list");
        return NULL;
    }
}

// This cleans up the char ** array we malloc'd before the function call
%typemap(freearg) char ** {
  free((char *) $1);
}

%apply int *OUTPUT {int *major, int *minor, int *ratioperf}
%apply int *OUTPUT {unsigned int *n_gpus}
%apply (int *INPLACE_ARRAY1) {int *gpu_percent_usage};
%apply (int *INPLACE_ARRAY1) {int *majors};
%apply (int *INPLACE_ARRAY1) {int *minors};
%apply (unsigned long long *INPLACE_ARRAY1) {unsigned long long *gpu_total_memory};
%apply (unsigned long long *INPLACE_ARRAY1) {unsigned long long *gpu_free_memory};

extern int cudaresetdevice(int wDev, int nDev);
extern int get_compute_capability(int d_idx, int *major, int *minor, int *ratioperf);
extern void get_gpu_info_c(unsigned int *n_gpus, int *gpu_percent_usage, unsigned long long *gpu_total_memory, unsigned long long *gpu_free_memory, char **gpu_name, int *majors, int *minors);
extern int cudaresetdevice_bare(void);
