#!/bin/bash

VERSION=$1
NEW_WRAP=$2

[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

if [ "$VERSION" == "10.6.194" -o "$VERSION" == "11.8.172" ]; then 
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python3 \
        ninja-build \
        xz-utils \
        zip
        
    pip install virtualenv
else
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python \
        xz-utils \
        zip
fi

sudo apt-get update
sudo apt-get install -y libatomic1-i386-cross
sudo rm -rf /var/lib/apt/lists/*
#export LD_LIBRARY_PATH=”LD_LIBRARY_PATH:/usr/i686-linux-gnu/lib/”
echo "/usr/i686-linux-gnu/lib" > i686.conf
sudo mv i686.conf /etc/ld.so.conf.d/
sudo ldconfig

cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
cd depot_tools
git reset --hard 8d16d4a
cd ..
export DEPOT_TOOLS_UPDATE=0
export PATH=$(pwd)/depot_tools:$PATH
gclient


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['android']" >> .gclient
cd ~/v8/v8
./build/install-build-deps-android.sh
git checkout refs/tags/$VERSION

echo "=====[ fix DEPS ]===="
node -e "const fs = require('fs'); fs.writeFileSync('./DEPS', fs.readFileSync('./DEPS', 'utf-8').replace(\"Var('chromium_url') + '/external/github.com/kennethreitz/requests.git'\", \"'https://github.com/kennethreitz/requests'\"));"

gclient sync


# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

if [ "$VERSION" == "11.8.172" ]; then 
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/remove_uchar_include_v11.8.172.patch
fi

if [ "$NEW_WRAP" == "with_new_wrap" ]; then 
  echo "=====[ wrap new delete ]====="
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/wrap_new_delete_v$VERSION.patch
fi

echo "=====[ add ArrayBuffer_New_Without_Stl ]====="
node $GITHUB_WORKSPACE/node-script/add_arraybuffer_new_without_stl.js .

node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION $NEW_WRAP

echo "=====[ Building V8 ]====="
if [ "$VERSION" == "11.8.172"  ]; then 
    gn gen out.gn/arm.release --args="target_os=\"android\" target_cpu=\"arm\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true strip_absolute_paths_from_debug_symbols=false strip_debug_info=false symbol_level=1 use_custom_libcxx=false use_custom_libcxx_for_host=true v8_enable_sandbox=false v8_enable_maglev=false"
elif [ "$VERSION" == "10.6.194" ]; then
    gn gen out.gn/arm.release --args="target_os=\"android\" target_cpu=\"arm\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true strip_absolute_paths_from_debug_symbols=false strip_debug_info=false symbol_level=1 use_custom_libcxx=false use_custom_libcxx_for_host=true v8_enable_sandbox=false"
else
    gn gen out.gn/arm.release --args="target_os=\"android\" target_cpu=\"arm\" is_debug=false v8_enable_i18n_support=false v8_target_cpu=\"arm\" use_goma=false v8_use_snapshot=true v8_use_external_startup_data=false v8_static_library=true strip_absolute_paths_from_debug_symbols=false strip_debug_info=false symbol_level=1 use_custom_libcxx=false use_custom_libcxx_for_host=true"
fi
ninja -C out.gn/arm.release -t clean
ninja -v -C out.gn/arm.release wee8

if [ "$VERSION" == "9.4.146.24" ]; then 
  third_party/android_ndk/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/arm-linux-androideabi/bin/strip -g -S -d --strip-debug --verbose out.gn/arm.release/obj/libwee8.a
fi

mkdir -p output/v8/Lib/Android/armeabi-v7a
if [ "$NEW_WRAP" == "with_new_wrap" ]; then 
  third_party/android_ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy --redefine-sym=_Znwm=__puerts_wrap__Znwm --redefine-sym=_ZdlPv=__puerts_wrap__ZdlPv --redefine-sym=_Znam=__puerts_wrap__Znam --redefine-sym=_ZdaPv=__puerts_wrap__ZdaPv --redefine-sym=_ZnwmRKSt9nothrow_t=__puerts_wrap__ZnwmRKSt9nothrow_t --redefine-sym=_ZnamRKSt9nothrow_t=__puerts_wrap__ZnamRKSt9nothrow_t out.gn/arm.release/obj/libwee8.a
fi
cp out.gn/arm.release/obj/libwee8.a output/v8/Lib/Android/armeabi-v7a/
mkdir -p output/v8/Bin/Android/armeabi-v7a
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/armeabi-v7a \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/armeabi-v7a \;
