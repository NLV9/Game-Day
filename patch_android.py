import re, sys, os
root = sys.argv[1]

# Manifest: permissions + notification receivers
mp = os.path.join(root, 'android/app/src/main/AndroidManifest.xml')
m = open(mp, encoding='utf-8').read()
perms = ('<uses-permission android:name="android.permission.INTERNET"/>\n'
         '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
         '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n')
recv = ('<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>\n'
        '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n'
        '<intent-filter>\n<action android:name="android.intent.action.BOOT_COMPLETED"/>\n'
        '<action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n'
        '<action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n'
        '<action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n</intent-filter>\n</receiver>\n')
m = m.replace('<application', perms + '<application', 1)
m = m.replace('</application>', recv + '</application>', 1)
m = m.replace('android:label="game_day"', 'android:label="GDS"')
open(mp, 'w', encoding='utf-8').write(m)

# Gradle: core library desugaring + no code shrinking (shrinking breaks the notification plugin)
base = os.path.join(root, 'android/app')
kts = os.path.join(base, 'build.gradle.kts')
grv = os.path.join(base, 'build.gradle')
if os.path.exists(kts):
    g = open(kts, encoding='utf-8').read()
    g = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', g, count=1)
    g = re.sub(r'(buildTypes\s*\{\s*(?:getByName\("release"\)|release)\s*\{)',
               r'\1\n            isMinifyEnabled = false\n            isShrinkResources = false', g, count=1)
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")\n}\n'
    open(kts, 'w', encoding='utf-8').write(g)
else:
    g = open(grv, encoding='utf-8').read()
    g = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        coreLibraryDesugaringEnabled true', g, count=1)
    g = re.sub(r'(buildTypes\s*\{\s*release\s*\{)',
               r'\1\n            minifyEnabled false\n            shrinkResources false', g, count=1)
    g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'\n}\n"
    open(grv, 'w', encoding='utf-8').write(g)

# Kotlin/Java target mismatch only warns
gp = os.path.join(root, 'android/gradle.properties')
with open(gp, 'a', encoding='utf-8') as f:
    f.write('\nkotlin.jvm.target.validation.mode=warning\n')
print('patched')
