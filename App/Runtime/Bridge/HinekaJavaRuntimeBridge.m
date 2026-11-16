#import "HinekaJavaRuntimeBridge.h"
#include <jni.h>
#include <stdlib.h>
#include <string.h>

extern void loadfunctions(void);

static NSString * const HinekaJavaRuntimeErrorDomain = @"com.realdevmcios.hineka.java-runtime";

static NSError *HinekaMakeRuntimeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:HinekaJavaRuntimeErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL HinekaClearPendingException(JNIEnv *env, NSString *stage, NSError **error) {
    if (!(*env)->ExceptionCheck(env)) {
        return NO;
    }

    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);

    if (error != NULL) {
        *error = HinekaMakeRuntimeError(20, [NSString stringWithFormat:@"Java exception at %@.", stage]);
    }
    return YES;
}

NSString * _Nullable HinekaJavaRunSmokeTest(
    NSString *javaHomePath,
    NSString *classPath,
    NSError **error
) {
    if (![NSThread isMainThread]) {
        if (error != NULL) {
            *error = HinekaMakeRuntimeError(1, @"The experimental JVM smoke test must run on the main thread.");
        }
        return nil;
    }

    if (javaHomePath.length == 0 || classPath.length == 0) {
        if (error != NULL) {
            *error = HinekaMakeRuntimeError(2, @"Missing Java home or smoke-test JAR path.");
        }
        return nil;
    }

    NSString *modulesPath = [javaHomePath stringByAppendingPathComponent:@"lib/modules"];
    NSString *jarPath = classPath;

    if (![[NSFileManager defaultManager] fileExistsAtPath:modulesPath] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:jarPath]) {
        if (error != NULL) {
            *error = HinekaMakeRuntimeError(3, @"The bundled Java modules image or smoke-test JAR is missing.");
        }
        return nil;
    }

    NSArray<NSString *> *cachePaths = NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory,
        NSUserDomainMask,
        YES
    );
    NSString *cacheRoot = cachePaths.firstObject;
    NSString *homePath = [cacheRoot stringByAppendingPathComponent:@"HinekaJavaHome"];
    NSString *tempPath = [cacheRoot stringByAppendingPathComponent:@"HinekaJavaTemp"];

    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:homePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&directoryError];
    if (directoryError == nil) {
        [[NSFileManager defaultManager] createDirectoryAtPath:tempPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&directoryError];
    }
    if (directoryError != nil) {
        if (error != NULL) {
            *error = directoryError;
        }
        return nil;
    }

    NSString *javaHomeOption = [@"-Djava.home=" stringByAppendingString:javaHomePath];
    NSString *classPathOption = [@"-Djava.class.path=" stringByAppendingString:jarPath];
    NSString *userHomeOption = [@"-Duser.home=" stringByAppendingString:homePath];
    NSString *tempOption = [@"-Djava.io.tmpdir=" stringByAppendingString:tempPath];

    JavaVMOption options[4];
    memset(options, 0, sizeof(options));

    NSArray<NSString *> *optionValues = @[
        javaHomeOption,
        classPathOption,
        userHomeOption,
        tempOption
    ];

    for (NSUInteger index = 0; index < optionValues.count; index++) {
        options[index].optionString = strdup(optionValues[index].UTF8String);
        if (options[index].optionString == NULL) {
            for (NSUInteger freeIndex = 0; freeIndex < index; freeIndex++) {
                free(options[freeIndex].optionString);
            }
            if (error != NULL) {
                *error = HinekaMakeRuntimeError(4, @"Could not allocate Java VM options.");
            }
            return nil;
        }
    }

    JavaVMInitArgs vmArgs;
    memset(&vmArgs, 0, sizeof(vmArgs));
    vmArgs.version = JNI_VERSION_1_8;
    vmArgs.nOptions = (jint)optionValues.count;
    vmArgs.options = options;
    vmArgs.ignoreUnrecognized = JNI_FALSE;

    // OpenJDK Mobile's iOS static build requires this generated native-symbol map.
    loadfunctions();

    JavaVM *javaVM = NULL;
    JNIEnv *env = NULL;
    jint createResult = JNI_CreateJavaVM(&javaVM, (void **)&env, &vmArgs);

    for (NSUInteger index = 0; index < optionValues.count; index++) {
        free(options[index].optionString);
    }

    if (createResult != JNI_OK || javaVM == NULL || env == NULL) {
        if (error != NULL) {
            *error = HinekaMakeRuntimeError(
                5,
                [NSString stringWithFormat:@"JNI_CreateJavaVM failed (status %d).", (int)createResult]
            );
        }
        return nil;
    }

    NSString *output = nil;
    jclass testClass = (*env)->FindClass(env, "HinekaRuntimeSmokeTest");
    if (testClass == NULL || HinekaClearPendingException(env, @"FindClass", error)) {
        if (testClass == NULL && error != NULL && *error == nil) {
            *error = HinekaMakeRuntimeError(6, @"Could not find HinekaRuntimeSmokeTest.");
        }
        goto cleanup;
    }

    jmethodID runMethod = (*env)->GetStaticMethodID(
        env,
        testClass,
        "run",
        "()Ljava/lang/String;"
    );
    if (runMethod == NULL || HinekaClearPendingException(env, @"GetStaticMethodID", error)) {
        if (runMethod == NULL && error != NULL && *error == nil) {
            *error = HinekaMakeRuntimeError(7, @"Could not find the Java smoke-test method.");
        }
        goto cleanup;
    }

    jstring javaOutput = (jstring)(*env)->CallStaticObjectMethod(env, testClass, runMethod);
    if (javaOutput == NULL || HinekaClearPendingException(env, @"Java smoke test", error)) {
        if (javaOutput == NULL && error != NULL && *error == nil) {
            *error = HinekaMakeRuntimeError(8, @"The Java smoke test returned no result.");
        }
        goto cleanup;
    }

    const char *utf8Output = (*env)->GetStringUTFChars(env, javaOutput, NULL);
    if (utf8Output == NULL || HinekaClearPendingException(env, @"GetStringUTFChars", error)) {
        if (utf8Output == NULL && error != NULL && *error == nil) {
            *error = HinekaMakeRuntimeError(9, @"Could not read the Java smoke-test result.");
        }
        goto cleanup;
    }

    output = [NSString stringWithUTF8String:utf8Output];
    (*env)->ReleaseStringUTFChars(env, javaOutput, utf8Output);

cleanup:
    {
        jint destroyResult = (*javaVM)->DestroyJavaVM(javaVM);
        if (destroyResult != JNI_OK && output != nil) {
            if (error != NULL) {
                *error = HinekaMakeRuntimeError(
                    10,
                    [NSString stringWithFormat:@"Java VM shutdown returned status %d.", (int)destroyResult]
                );
            }
            output = nil;
        }
    }

    return output;
}
