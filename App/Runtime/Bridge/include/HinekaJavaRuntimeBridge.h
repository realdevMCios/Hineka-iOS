#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Starts a short-lived OpenJDK Mobile Zero VM, invokes the Java smoke test,
/// returns its text output, and then destroys that VM.
/// Call only from the iOS main thread during this proof-of-concept phase.
FOUNDATION_EXPORT NSString * _Nullable HinekaJavaRunSmokeTest(
    NSString *javaHomePath,
    NSString *classPath,
    NSError * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
