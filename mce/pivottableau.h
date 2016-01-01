/*
 * MATLAB Compiler: 2.2
 * Date: Sat Nov 30 14:13:31 2002
 * Arguments: "-B" "macro_default" "-O" "all" "-O" "fold_scalar_mxarrays:on"
 * "-O" "fold_non_scalar_mxarrays:on" "-O" "optimize_integer_for_loops:on" "-O"
 * "array_indexing:on" "-O" "optimize_conditionals:on" "-x" "-W" "mex" "-L" "C"
 * "-t" "-T" "link:mexlibrary" "libmatlbmx.mlib" "-h" "simplex1" 
 */

#ifndef MLF_V2
#define MLF_V2 1
#endif

#ifndef __pivottableau_h
#define __pivottableau_h 1

#ifdef __cplusplus
extern "C" {
#endif

#include "libmatlb.h"

extern void InitializeModule_pivottableau(void);
extern void TerminateModule_pivottableau(void);
extern _mexLocalFunctionTable _local_function_table_pivottableau;

extern mxArray * mlfPivottableau(mxArray * * basicptr,
                                 mxArray * * cost,
                                 mxArray * intableau,
                                 mxArray * inbasicptr,
                                 ...);
extern void mlxPivottableau(int nlhs,
                            mxArray * plhs[],
                            int nrhs,
                            mxArray * prhs[]);

#ifdef __cplusplus
}
#endif

#endif
