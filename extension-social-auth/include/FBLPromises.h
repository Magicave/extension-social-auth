#ifndef FBLPROMISES_SHIM_H
#define FBLPROMISES_SHIM_H

#if __has_include(<PromisesObjC/FBLPromises.h>)
#import <PromisesObjC/FBLPromises.h>
#elif __has_include(<FBLPromises/FBLPromises.h>)
#import <FBLPromises/FBLPromises.h>
#else
#error "FBLPromises.h shim could not locate PromisesObjC headers"
#endif

#endif
