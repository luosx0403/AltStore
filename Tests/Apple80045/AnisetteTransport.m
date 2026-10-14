#import <Foundation/Foundation.h>
#import "ALTAnisetteData.h"

static void check(BOOL passed, const char *message)
{
    if (!passed) { fprintf(stderr, "FAIL %s\n", message); exit(1); }
    printf("PASS %s\n", message);
}

int main(void)
{
    @autoreleasepool {
        NSString *mac = @"<fixture-Mac> <macOS;26.6;fixture> <com.apple.AuthKit/1 (com.apple.akd/1.0)>";
        NSString *android = @"<Pixel 5> <Android;11;RQ3A.211001.001> <com.apple.AuthKit/1 (com.apple.akd/1.0)>";
        ALTAnisetteData *data = [[ALTAnisetteData alloc] initWithMachineID:@"fixture-machine"
            oneTimePassword:@"fixture-otp" localUserID:@"fixture-user" routingInfo:17106176
            deviceUniqueIdentifier:@"fixture-device" deviceSerialNumber:@"fixture-serial"
            deviceDescription:mac date:[NSDate dateWithTimeIntervalSince1970:1704067200]
            locale:[NSLocale localeWithLocaleIdentifier:@"en_US"] timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

        check(data.json[@"authenticationDeviceDescription"] == nil, "legacy JSON omits optional identity");
        ALTAnisetteData *legacy = [[ALTAnisetteData alloc] initWithJSON:data.json];
        check(legacy.authenticationDeviceDescription == nil && [legacy isEqual:data], "legacy JSON decodes without identity");
        NSError *error = nil;
        NSData *oldArchive = [NSKeyedArchiver archivedDataWithRootObject:data requiringSecureCoding:YES error:&error];
        ALTAnisetteData *oldDecoded = [NSKeyedUnarchiver unarchivedObjectOfClass:ALTAnisetteData.class fromData:oldArchive error:&error];
        check(error == nil && oldDecoded.authenticationDeviceDescription == nil, "legacy secure archive still decodes");

        data.authenticationDeviceDescription = android;
        NSDictionary *message = @{@"identifier": @"AnisetteDataResponse", @"version": @1, @"anisetteData": data.json};
        NSData *wire = [NSJSONSerialization dataWithJSONObject:message options:0 error:&error];
        NSDictionary *decodedMessage = [NSJSONSerialization JSONObjectWithData:wire options:0 error:&error];
        ALTAnisetteData *clientData = [[ALTAnisetteData alloc] initWithJSON:decodedMessage[@"anisetteData"]];
        check(error == nil && [clientData.authenticationDeviceDescription isEqual:android], "server JSON response carries Android provenance to client");
        check([clientData.deviceDescription isEqual:mac], "SMS and Developer identity stays Mac");
        ALTAnisetteData *copy = [data copy];
        check([copy.authenticationDeviceDescription isEqual:android] && [copy isEqual:data] && copy.hash == data.hash, "copy preserves provider identity and equality");
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:data requiringSecureCoding:YES error:&error];
        ALTAnisetteData *restored = [NSKeyedUnarchiver unarchivedObjectOfClass:ALTAnisetteData.class fromData:archive error:&error];
        check(error == nil && [restored.authenticationDeviceDescription isEqual:android], "secure archive preserves provider identity");
        copy.authenticationDeviceDescription = nil;
        check(![copy isEqual:data], "different authentication provenance is not equal");
        puts("8 native anisette transport regression cases passed.");
    }
    return 0;
}
