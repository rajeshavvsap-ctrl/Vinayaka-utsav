"""Adjusts the Android project that `flutter create` generates in CI:
min SDK 23, app name, release signing with the Play upload key (when the
UPLOAD_* environment variables are set), and an https <queries> entry so the
app can open the update download link."""
import os, re, sys

gradle = 'android/app/build.gradle.kts'
kts = os.path.exists(gradle)
if not kts:
    gradle = 'android/app/build.gradle'
s = open(gradle).read()

s = re.sub(r'minSdk(Version)?( *=)? *flutter\.minSdkVersion', 'minSdk = 23', s)

if kts:
    block = '''
    signingConfigs {
        create("upload") {
            val ks = System.getenv("UPLOAD_KEYSTORE_PATH")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("UPLOAD_KEY_ALIAS")
                keyPassword = System.getenv("UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {'''
    pick = ('signingConfig = if (System.getenv("UPLOAD_KEYSTORE_PATH") != null) '
            'signingConfigs.getByName("upload") else signingConfigs.getByName("debug")')
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', pick)
else:
    block = '''
    signingConfigs {
        upload {
            if (System.getenv("UPLOAD_KEYSTORE_PATH") != null) {
                storeFile file(System.getenv("UPLOAD_KEYSTORE_PATH"))
                storePassword System.getenv("UPLOAD_STORE_PASSWORD")
                keyAlias System.getenv("UPLOAD_KEY_ALIAS")
                keyPassword System.getenv("UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {'''
    pick = ('signingConfig System.getenv("UPLOAD_KEYSTORE_PATH") != null ? '
            'signingConfigs.upload : signingConfigs.debug')
    s = s.replace('signingConfig = signingConfigs.debug', pick).replace('signingConfig signingConfigs.debug', pick)

if 'signingConfigs {' not in s:
    s = s.replace('\n    buildTypes {', block, 1)
if 'getByName("upload")' not in s and 'signingConfigs.upload' not in s:
    sys.exit('Could not patch release signing in ' + gradle)
open(gradle, 'w').write(s)

m = 'android/app/src/main/AndroidManifest.xml'
x = open(m).read()
x = x.replace('android:label="vinayaka_utsav"', 'android:label="Vinayaka Utsav"')
view = ('<intent><action android:name="android.intent.action.VIEW"/>'
        '<data android:scheme="https"/></intent>')
if '<queries>' in x:
    x = x.replace('<queries>', '<queries>\n        ' + view, 1)
else:
    x = x.replace('</manifest>', '    <queries>' + view + '</queries>\n</manifest>')
open(m, 'w').write(x)
print(open(gradle).read())
