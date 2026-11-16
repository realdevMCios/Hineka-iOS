#import "HinekaJavaRuntimeBridge.h"
#include <jni.h>
#include <stdlib.h>
#include <string.h>

extern void loadfunctions(void);

static NSString *g_hinekaJavaLastError = nil;

static NSString *HinekaSetRuntimeError(NSString *message) {
    g_hinekaJavaLastError = [message copy];
    return nil;
}

static BOOL HinekaClearPendingException(JNIEnv *env, NSString *stage) {
    if (!(*env)->ExceptionCheck(env)) {
        return NO;
    }

    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
    g_hinekaJavaLastError = [NSString stringWithFormat:@"Java exception at %@.", stage];
    return YES;
}

NSString * _Nullable HinekaJavaRunSmokeTest(
    NSString *javaHomePath,
    NSString *classPath
) {
    g_hinekaJavaLastError = nil;

    if (![NSThread isMainThread]) {
        return HinekaSetRuntimeError(@"The experimental JVM smoke test must run on the main thread.");
    }

    if (javaHomePath.length == 0 || classPath.length == 0) {
        return HinekaSetRuntimeError(@"Missing Java home or smoke-test JAR path.");
    }

    NSString *modulesPath = [javaHomePath stringByAppendingPathComponent:@"lib/modules"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:modulesPath] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:classPath]) {
        return HinekaSetRuntimeError(@"The bundled Java modules image or smoke-test JAR is missing.");
    }

    NSArray<NSString *> *cachePaths = NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory,
        NSUserDomainMask,
        YES
    );
    NSString *cacheRoot = cachePaths.firstObject;
    if (cacheRoot.length == 0) {
        return HinekaSetRuntimeError(@"Could not locate the app cache directory.");
    }

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
        return HinekaSetRuntimeError(directoryError.localizedDescription);
    }

    NSString *javaHomeOption = [@"-Djava.home=" stringByAppendingString:javaHomePath];
    NSString *classPathOption = [@"-Djava.class.path=" stringByAppendingString:classPath];
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
            return HinekaSetRuntimeError(@"Could not allocate Java VM options.");
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
        return HinekaSetRuntimeError(
            [NSString stringWithFormat:@"JNI_CreateJavaVM failed (status %d).", (int)createResult]
        );
    }

    NSString *output = nil;
    jclass testClass = (*env)->FindClass(env, "HinekaRuntimeSmokeTest");
    BOOL findClassThrew = HinekaClearPendingException(env, @"FindClass");
    if (testClass == NULL || findClassThrew) {
        if (testClass == NULL && g_hinekaJavaLastError == nil) {
            g_hinekaJavaLastError = @"Could not find HinekaRuntimeSmokeTest.";
        }
        goto cleanup;
    }

    jmethodID runMethod = (*env)->GetStaticMethodID(
        env,
        testClass,
        "run",
        "()Ljava/lang/String;"
    );
    BOOL getMethodThrew = HinekaClearPendingException(env, @"GetStaticMethodID");
    if (runMethod == NULL || getMethodThrew) {
        if (runMethod == NULL && g_hinekaJavaLastError == nil) {
            g_hinekaJavaLastError = @"Could not find the Java smoke-test method.";
        }
        goto cleanup;
    }

    jstring javaOutput = (jstring)(*env)->CallStaticObjectMethod(env, testClass, runMethod);
    BOOL javaCallThrew = HinekaClearPendingException(env, @"Java smoke test");
    if (javaOutput == NULL || javaCallThrew) {
        if (javaOutput == NULL && g_hinekaJavaLastError == nil) {
            g_hinekaJavaLastError = @"The Java smoke test returned no result.";
        }
        goto cleanup;
    }

    const char *utf8Output = (*env)->GetStringUTFChars(env, javaOutput, NULL);
    BOOL getStringThrew = HinekaClearPendingException(env, @"GetStringUTFChars");
    if (utf8Output == NULL || getStringThrew) {
        if (utf8Output == NULL && g_hinekaJavaLastError == nil) {
            g_hinekaJavaLastError = @"Could not read the Java smoke-test result.";
        }
        goto cleanup;
    }

    output = [NSString stringWithUTF8String:utf8Output];
    (*env)->ReleaseStringUTFChars(env, javaOutput, utf8Output);
    if (output == nil && g_hinekaJavaLastError == nil) {
        g_hinekaJavaLastError = @"The Java smoke-test result was not valid UTF-8.";
    }

cleanup:
    {
        jint destroyResult = (*javaVM)->DestroyJavaVM(javaVM);
        if (destroyResult != JNI_OK && output != nil) {
            g_hinekaJavaLastError = [NSString stringWithFormat:
                @"Java VM shutdown returned status %d.", (int)destroyResult];
            output = nil;
        }
    }

    return output;
}

NSString * _Nullable HinekaJavaLastError(void) {
    return g_hinekaJavaLastError;
}
