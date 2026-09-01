#import <Foundation/Foundation.h>

extern void SpeedReadInstallHermeticNetworkGuard(void);

__attribute__((constructor))
static void SpeedReadInstallHermeticNetworkGuardAtBundleLoad(void) {
    SpeedReadInstallHermeticNetworkGuard();
}
