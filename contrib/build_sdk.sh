#!/bin/bash

##
 # @file contrib/build_sdk.sh
 # @brief Builds MEGA SDK static library and static examples
 #
 # (c) 2013-2014 by Mega Limited, Auckland, New Zealand
 #
 # This file is part of the MEGA SDK - Client Access Engine.
 #
 # Applications using the MEGA API must present a valid application key
 # and comply with the the rules set forth in the Terms of Service.
 #
 # The MEGA SDK is distributed in the hope that it will be useful,
 # but WITHOUT ANY WARRANTY; without even the implied warranty of
 # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 #
 # @copyright Simplified (2-clause) BSD License.
 #
 # You should have received a copy of the license along with this
 # program.
##

# Warn about /bin/sh ins't bash.
if [ -z "$BASH_VERSION" ] ; then
    echo "WARNING: The shell running this script isn't bash."
fi

# global vars
use_local=0
use_dynamic=0
disable_freeimage=0
disable_ssl=0
download_only=0
enable_megaapi=0
make_opts=""
config_opts=""
no_examples=""
configure_only=0
disable_posix_threads=""
enable_sodium=0
enable_libuv=0
android_build=0
enable_cryptopp=0

on_exit_error() {
    echo "ERROR! Please check log files. Exiting.."
}

on_exit_ok() {
    if [ $configure_only -eq 0 ]; then
        echo "Successfully compiled MEGA SDK!"
    else
        echo "Successfully configured MEGA SDK!"
    fi
}

print_distro_help()
{
    # yum: CentOS, Fedora, RedHat
    type yum >/dev/null 2>&1
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Please execute the following command:  sudo yum install gcc gcc-c++ libtool unzip autoconf make wget glibc-devel-static"
        return
    fi

    # apt-get: Debian, Ubuntu
    type apt-get >/dev/null 2>&1
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Please execute the following command:  sudo apt-get install gcc c++ libtool-bin unzip autoconf m4 make wget"
        echo " (or 'libtool' on older Debian / Ubuntu distro versions)"
        return
    fi
}

check_apps()
{
    if [ -z "${BASH}" ]
    then
        echo "Please run this script with the BASH shell"
        exit 1
    elif [ ${BASH_VERSINFO} -lt 3 ]
    then
        printf "BASH version 3 or greater is required"
        exit 1
    fi

    APPS=(bash gcc c++ libtool tar unzip autoconf make autoreconf wget automake m4)
    for app in ${APPS[@]}; do
        type ${app} >/dev/null 2>&1 || { echo "${app} is not installed. Please install it first and re-run the script."; print_distro_help; exit 1; }
        hash ${app} 2>/dev/null || { echo "${app} is not installed. Please install it first and re-run the script."; print_distro_help; exit 1; }
    done
}

package_download() {
    local name=$1
    local url=$2
    local file=$local_dir/$3

    if [ $use_local -eq 1 ]; then
        echo "Using local file for $name"
        return
    fi

    echo "Downloading $name"

    if [ -f $file ]; then
        rm -f $file || true
    fi

	# use packages previously downloaded in obs server(linux). if not present, download from URL specified
	cp /srv/dependencies_manually_downloaded/$3 $file || \
	wget --no-check-certificate -c $url -O $file --progress=bar:force -t 2 -T 30 || exit 1

    
    
    
    
}

package_extract() {
    local name=$1
    local file=$local_dir/$2
    local dir=$3

    echo "Extracting $name"

    local filename=$(basename "$file")
    local extension="${filename##*.}"

    if [ ! -f $file ]; then
        echo "File $file does not exist!"
    fi

    if [ -d $dir ]; then
        rm -fr $dir || exit 1
    fi

    if [ $extension == "gz" ]; then
        tar -xzf $file &> $name.extract.log || exit 1
    elif [ $extension == "zip" ]; then
        unzip $file -d $dir &> $name.extract.log || exit 1
    else
        echo "Unsupported extension!"
        exit 1
    fi
}

package_configure() {
    local name=$1
    local dir=$2
    local install_dir="$3"
    local params="$4"

    local conf_f1="./config"
    local conf_f2="./configure"
    local autogen="./autogen.sh"

    echo "Configuring $name"

    local cwd=$(pwd)
    cd $dir || exit 1

    if [ -f $autogen ]; then
        $autogen
    fi

    if [ -f $conf_f1 ]; then
        $conf_f1 --prefix=$install_dir $params &> ../$name.conf.log || exit 1
    elif [ -f $conf_f2 ]; then
        $conf_f2 $config_opts --prefix=$install_dir $params &> ../$name.conf.log || exit 1
    else
        local exit_code=$?
        echo "Failed to configure $name, exit status: $exit_code"
        exit 1
    fi

    cd $cwd
}

package_build() {
    local name=$1
    local dir=$2

    if [ "$#" -eq 3 ]; then
        local target=$3
    else
        local target=""
    fi

    echo "Building $name"

    local cwd=$(pwd)
    cd $dir

    make $make_opts $target &> ../$name.build.log

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Failed to build $name, exit status: $exit_code"
        exit 1
    fi
    cd $cwd
}

package_install() {
    local name=$1
    local dir=$2
    local install_dir=$3

    if [ "$#" -eq 4 ]; then
        local target=$4
    else
        local target=""
    fi

    echo "Installing $name"

    local cwd=$(pwd)
    cd $dir
    make install $target &> ../$name.install.log
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Failed to install $name, exit status: $exit_code"
        exit 1
    fi
    cd $cwd

    # some packages install libraries to "lib64" folder
    local lib64=$install_dir/lib64
    local lib=$install_dir/lib
    if [ -d $lib64 ]; then
        cp -f $lib64/* $lib/
    fi
}

openssl_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="OpenSSL"
    local openssl_ver="1.0.2g"
    local openssl_url="https://www.openssl.org/source/openssl-$openssl_ver.tar.gz"
    local openssl_file="openssl-$openssl_ver.tar.gz"
    local openssl_dir="openssl-$openssl_ver"
    local openssl_params="--openssldir=$install_dir no-shared shared"
    local loc_make_opts=$make_opts

    package_download $name $openssl_url $openssl_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $openssl_file $openssl_dir

    if [ $android_build -eq 1 ]; then
        echo "Configuring $name"
        local cwd=$(pwd)
        cd $openssl_dir
        perl -pi -e 's/install: all install_docs install_sw/install: install_docs install_sw/g' Makefile.org
        ./config shared no-ssl2 no-ssl3 no-comp no-hw no-engine --prefix=$install_dir
        make depend || exit 1
        cd $cwd
    else
        # handle MacOS
        if [ "$(uname)" == "Darwin" ]; then
            # OpenSSL compiles 32bit binaries, we need to explicitly tell to use x86_64 mode
            if [ "$(uname -m)" == "x86_64" ]; then
                echo "Configuring $name"
                local cwd=$(pwd)
                cd $openssl_dir
                ./Configure darwin64-x86_64-cc --prefix=$install_dir $openssl_params &> ../$name.conf.log || exit 1
                cd $cwd
            else
                package_configure $name $openssl_dir $install_dir "$openssl_params"
            fi
        else
            package_configure $name $openssl_dir $install_dir "$openssl_params"
        fi
    fi

    # OpenSSL has issues with parallel builds, let's use the default options
    make_opts=""
    package_build $name $openssl_dir
    make_opts=$loc_make_opts

    package_install $name $openssl_dir $install_dir
}

cryptopp_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="Crypto++"
    local cryptopp_ver="562"
    local cryptopp_url="http://www.cryptopp.com/cryptopp$cryptopp_ver.zip"
    local cryptopp_file="cryptopp$cryptopp_ver.zip"
    local cryptopp_dir="cryptopp$cryptopp_ver"
    local cryptopp_mobile_url="http://www.cryptopp.com/w/images/a/a0/Cryptopp-mobile.zip"
    local cryptopp_mobile_file="Cryptopp-mobile.zip"

    package_download $name $cryptopp_url $cryptopp_file
    if [ $android_build -eq 1 ]; then
        package_download $name $cryptopp_mobile_url $cryptopp_mobile_file
    fi
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $cryptopp_file $cryptopp_dir
    if [ $android_build -eq 1 ]; then
        local file=$local_dir/$cryptopp_mobile_file
        unzip -o $file -d $cryptopp_dir || exit 1
    fi
    #modify Makefile so that it does not use specific cpu architecture optimizations
    sed "s#CXXFLAGS += -march=native#CXXFLAGS += #g" -i $cryptopp_dir/GNUmakefile
    package_build $name $cryptopp_dir static
    package_install $name $cryptopp_dir $install_dir
}

sodium_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="Sodium"
    local sodium_ver="1.0.8"
    local sodium_url="https://download.libsodium.org/libsodium/releases/libsodium-$sodium_ver.tar.gz"
    local sodium_file="sodium-$sodium_ver.tar.gz"
    local sodium_dir="libsodium-$sodium_ver"
    if [ $use_dynamic -eq 1 ]; then
        local sodium_params="--enable-shared"
    else
        local sodium_params="--disable-shared --enable-static"
    fi

    package_download $name $sodium_url $sodium_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $sodium_file $sodium_dir
    package_configure $name $sodium_dir $install_dir "$sodium_params"
    package_build $name $sodium_dir
    package_install $name $sodium_dir $install_dir
}

libuv_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="libuv"
    local libuv_ver="v1.8.0"
    local libuv_url="http://dist.libuv.org/dist/$libuv_ver/libuv-$libuv_ver.tar.gz"
    local libuv_file="libuv-$libuv_ver.tar.gz"
    local libuv_dir="libuv-$libuv_ver"
    if [ $use_dynamic -eq 1 ]; then
        local libuv_params="--enable-shared"
    else
        local libuv_params="--disable-shared --enable-static"
    fi

    package_download $name $libuv_url $libuv_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $libuv_file $libuv_dir

    # linking with static library requires -fPIC
    if [ $use_dynamic -eq 0 ]; then
        export CFLAGS="-fPIC"
    fi
    package_configure $name $libuv_dir $install_dir "$libuv_params"
    if [ $use_dynamic -eq 0 ]; then
        unset CFLAGS
    fi

    package_build $name $libuv_dir
    package_install $name $libuv_dir $install_dir
}

zlib_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="Zlib"
    local zlib_ver="1.2.8"
    local zlib_url="http://zlib.net/zlib-$zlib_ver.tar.gz"
    local zlib_file="zlib-$zlib_ver.tar.gz"
    local zlib_dir="zlib-$zlib_ver"
    local loc_conf_opts=$config_opts
    if [ $use_dynamic -eq 1 ]; then
        local zlib_params=""
    else
        local zlib_params="--static"
    fi

    package_download $name $zlib_url $zlib_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $zlib_file $zlib_dir

    # doesn't recognize --host=xxx
    config_opts=""

    # Windows must use Makefile.gcc
    if [ "$(expr substr $(uname -s) 1 10)" != "MINGW32_NT" ]; then
        package_configure $name $zlib_dir $install_dir "$zlib_params"
        package_build $name $zlib_dir
        package_install $name $zlib_dir $install_dir
    else
        export BINARY_PATH=$install_dir/bin
        export INCLUDE_PATH=$install_dir/include
        export LIBRARY_PATH=$install_dir/lib
        package_build $name $zlib_dir "-f win32/Makefile.gcc"
        package_install $name $zlib_dir $install_dir "-f win32/Makefile.gcc"
        unset BINARY_PATH
        unset INCLUDE_PATH
        unset LIBRARY_PATH
    fi
    config_opts=$loc_conf_opts

}

sqlite_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="SQLite"
    local sqlite_ver="3100100"
    local sqlite_url="http://www.sqlite.org/2016/sqlite-autoconf-$sqlite_ver.tar.gz"
    local sqlite_file="sqlite-$sqlite_ver.tar.gz"
    local sqlite_dir="sqlite-autoconf-$sqlite_ver"
    if [ $use_dynamic -eq 1 ]; then
        local sqlite_params="--enable-shared"
    else
        local sqlite_params="--disable-shared --enable-static"
    fi

    package_download $name $sqlite_url $sqlite_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $sqlite_file $sqlite_dir
    package_configure $name $sqlite_dir $install_dir "$sqlite_params"
    package_build $name $sqlite_dir
    package_install $name $sqlite_dir $install_dir
}

cares_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="c-ares"
    local cares_ver="1.10.0"
    local cares_url="http://c-ares.haxx.se/download/c-ares-$cares_ver.tar.gz"
    local cares_file="cares-$cares_ver.tar.gz"
    local cares_dir="c-ares-$cares_ver"
    if [ $use_dynamic -eq 1 ]; then
        local cares_params="--enable-shared"
    else
        local cares_params="--disable-shared --enable-static"
    fi

    package_download $name $cares_url $cares_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $cares_file $cares_dir
    package_configure $name $cares_dir $install_dir "$cares_params"
    package_build $name $cares_dir
    package_install $name $cares_dir $install_dir
}

curl_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="cURL"
    local curl_ver="7.46.0"
    local curl_url="http://curl.haxx.se/download/curl-$curl_ver.tar.gz"
    local curl_file="curl-$curl_ver.tar.gz"
    local curl_dir="curl-$curl_ver"
    local openssl_flags=""

    # use local or system OpenSSL
    if [ $disable_ssl -eq 0 ]; then
        openssl_flags="--with-ssl=$install_dir"
    else
        openssl_flags="--with-ssl"
    fi

    if [ $use_dynamic -eq 1 ]; then
        local curl_params="--disable-ftp --disable-file --disable-ldap --disable-ldaps --disable-rtsp --disable-dict \
            --disable-telnet --disable-tftp --disable-pop3 --disable-imap --disable-smtp --disable-gopher --disable-sspi \
            --without-librtmp --without-libidn --without-libssh2 --enable-ipv6 --disable-manual \
            --with-zlib=$install_dir --enable-ares=$install_dir $openssl_flags"
    else
        local curl_params="--disable-ftp --disable-file --disable-ldap --disable-ldaps --disable-rtsp --disable-dict \
            --disable-telnet --disable-tftp --disable-pop3 --disable-imap --disable-smtp --disable-gopher --disable-sspi \
            --without-librtmp --without-libidn --without-libssh2 --enable-ipv6 --disable-manual \
            --disable-shared --with-zlib=$install_dir --enable-ares=$install_dir $openssl_flags"
    fi

    package_download $name $curl_url $curl_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $curl_file $curl_dir
    package_configure $name $curl_dir $install_dir "$curl_params"
    package_build $name $curl_dir
    package_install $name $curl_dir $install_dir
}

readline_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="Readline"
    local readline_ver="6.3"
    local readline_url="ftp://ftp.cwru.edu/pub/bash/readline-$readline_ver.tar.gz"
    local readline_file="readline-$readline_ver.tar.gz"
    local readline_dir="readline-$readline_ver"
    if [ $use_dynamic -eq 1 ]; then
        local readline_params="--enable-shared"
    else
        local readline_params="--disable-shared --enable-static"
    fi

    package_download $name $readline_url $readline_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $readline_file $readline_dir
    package_configure $name $readline_dir $install_dir "$readline_params"
    package_build $name $readline_dir
    package_install $name $readline_dir $install_dir
}

termcap_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="Termcap"
    local termcap_ver="1.3.1"
    local termcap_url="http://ftp.gnu.org/gnu/termcap/termcap-$termcap_ver.tar.gz"
    local termcap_file="termcap-$termcap_ver.tar.gz"
    local termcap_dir="termcap-$termcap_ver"
    if [ $use_dynamic -eq 1 ]; then
        local termcap_params="--enable-shared"
    else
        local termcap_params="--disable-shared --enable-static"
    fi

    package_download $name $termcap_url $termcap_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $termcap_file $termcap_dir
    package_configure $name $termcap_dir $install_dir "$termcap_params"
    package_build $name $termcap_dir
    package_install $name $termcap_dir $install_dir
}

freeimage_pkg() {
    local build_dir=$1
    local install_dir=$2
    local cwd=$3
    local name="FreeImage"
    local freeimage_ver="3170"
    local freeimage_url="http://downloads.sourceforge.net/freeimage/FreeImage$freeimage_ver.zip"
    local freeimage_file="freeimage-$freeimage_ver.zip"
    local freeimage_dir_extract="freeimage-$freeimage_ver"
    local freeimage_dir="freeimage-$freeimage_ver/FreeImage"

    package_download $name $freeimage_url $freeimage_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $freeimage_file $freeimage_dir_extract

    # replace Makefile on MacOS
    if [ "$(uname)" == "Darwin" ]; then
        cp $cwd/contrib/FreeImage.Makefile.osx $freeimage_dir/Makefile.osx
    fi

    if [ $android_build -eq 1 ]; then
        sed -i '/#define HAVE_SEARCH_H 1/d' $freeimage_dir/Source/LibTIFF4/tif_config.h
    fi

    if [ $use_dynamic -eq 0 ]; then
        export FREEIMAGE_LIBRARY_TYPE=STATIC
    fi

    if [ "$(expr substr $(uname -s) 1 10)" != "MINGW32_NT" ]; then
        package_build $name $freeimage_dir
        # manually copy header and library
        cp $freeimage_dir/Dist/FreeImage.h $install_dir/include || exit 1
        cp $freeimage_dir/Dist/libfreeimage* $install_dir/lib || exit 1
    # MinGW
    else
        package_build $name $freeimage_dir "-f Makefile.mingw"
        # manually copy header and library
        cp $freeimage_dir/Dist/FreeImage.h $install_dir/include || exit 1
        # ignore if not present
        cp $freeimage_dir/Dist/FreeImage.dll $install_dir/lib || 1
        cp $freeimage_dir/Dist/FreeImage.lib $install_dir/lib || 1
        cp $freeimage_dir/Dist/libFreeImage.a $install_dir/lib || 1
    fi
}

# we can't build vanilla ReadLine under MinGW
readline_win_pkg() {
    local build_dir=$1
    local install_dir=$2
    local name="Readline"
    local readline_ver="5.0"
    local readline_url="http://gnuwin32.sourceforge.net/downlinks/readline-bin-zip.php"
    local readline_file="readline-bin.zip"
    local readline_dir="readline-bin"

    package_download $name $readline_url $readline_file
    if [ $download_only -eq 1 ]; then
        return
    fi

    package_extract $name $readline_file $readline_dir

    # manually copy binary files
    cp -R $readline_dir/include/* $install_dir/include/ || exit 1
    # fix library name
    cp $readline_dir/lib/libreadline.dll.a $install_dir/lib/libreadline.a || exit 1
}

build_sdk() {
    local install_dir=$1
    local debug=$2
    local static_flags=""
    local readline_flags=""
    local freeimage_flags=""
    local megaapi_flags=""
    local openssl_flags=""
    local sodium_flags="--without-sodium"
    local cwd=$(pwd)

    echo "Configuring MEGA SDK"

    ./autogen.sh || exit 1

    # use either static build (by the default) or dynamic
    if [ $use_dynamic -eq 1 ]; then
        static_flags="--enable-shared"
    else
        static_flags="--disable-shared --enable-static"
    fi

    # disable freeimage
    if [ $disable_freeimage -eq 0 ]; then
        freeimage_flags="--with-freeimage=$install_dir"
    else
        freeimage_flags="--without-freeimage"
    fi

    # enable megaapi
    if [ $enable_megaapi -eq 0 ]; then
        megaapi_flags="--disable-megaapi"
    fi

    # add readline and termcap flags if building examples
    if [ -z "$no_examples" ]; then
        readline_flags=" \
            --with-readline=$install_dir \
            --with-termcap=$install_dir \
            "
    fi

    if [ $disable_ssl -eq 0 ]; then
        openssl_flags="--with-openssl=$install_dir"
    fi

    if [ $enable_sodium -eq 1 ]; then
        sodium_flags="--with-sodium=$install_dir"
    fi

    if [ "$(expr substr $(uname -s) 1 10)" != "MINGW32_NT" ]; then
        ./configure \
            $static_flags \
            --disable-silent-rules \
            --disable-curl-checks \
            $megaapi_flags \
            $openssl_flags \
            --with-cryptopp=$install_dir \
            $sodium_flags \
            --with-zlib=$install_dir \
            --with-sqlite=$install_dir \
            --with-cares=$install_dir \
            --with-curl=$install_dir \
            $freeimage_flags \
            $readline_flags \
            $disable_posix_threads \
            $no_examples \
            $config_opts \
            --prefix=$install_dir \
            $debug || exit 1
    # Windows (MinGW) build, uses WinHTTP instead of cURL + c-ares, without OpenSSL
    else
        ./configure \
            $static_flags \
            --disable-silent-rules \
            --without-openssl \
            $megaapi_flags \
            --with-cryptopp=$install_dir \
            $sodium_flags \
            --with-zlib=$install_dir \
            --with-sqlite=$install_dir \
            --without-cares \
            --without-curl \
            --with-winhttp=$cwd \
            $freeimage_flags \
            $readline_flags \
            $disable_posix_threads \
            $no_examples \
            $config_opts \
            --prefix=$install_dir \
            $debug || exit 1
    fi

    echo "MEGA SDK is configured"

    if [ $configure_only -eq 0 ]; then
        echo "Building MEGA SDK"
        make clean
        make -j9 || exit 1
        make install
    fi
}

display_help() {
    local app=$(basename "$0")
    echo ""
    echo "Usage:"
    echo " $app [-a] [-c] [-h] [-d] [-f] [-l] [-m opts] [-n] [-o path] [-p path] [-r] [-s] [-t] [-w] [-x opts] [-y] [-q]"
    echo ""
    echo "By the default this script builds static megacli executable."
    echo "This script can be run with numerous options to configure and build MEGA SDK."
    echo ""
    echo "Options:"
    echo " -a : Enable MegaApi"
    echo " -c : Configure MEGA SDK and exit, do not build it"
    echo " -d : Enable debug build"
    echo " -f : Disable FreeImage"
    echo " -l : Use local software archive files instead of downloading"
    echo " -n : Disable example applications"
    echo " -s : Disable OpenSSL"
    echo " -r : Enable Android build"
    echo " -t : Disable POSIX Threads support"
    echo " -u : Enable Sodium cryptographic library"
    echo " -v : Enable libuv"
    echo " -w : Download software archives and exit"
    echo " -y : Build dynamic library and executable (instead of static)"
    echo " -m [opts]: make options"
    echo " -x [opts]: configure options"
    echo " -o [path]: Directory to store and look for downloaded archives"
    echo " -p [path]: Installation directory"
    echo " -q : Use Crypto++"
    echo ""
}

main() {
    local cwd=$(pwd)
    local work_dir=$cwd"/sdk_build"
    local build_dir=$work_dir/"build"
    local install_dir=$work_dir/"install"
    local debug=""
    # by the default store archives in work_dir
    local_dir=$work_dir

    while getopts ":hacdflm:no:p:rstuvyx:wq" opt; do
        case $opt in
            h)
                display_help $0
                exit
                ;;
            a)
                echo "* Enabling MegaApi"
                enable_megaapi=1
                ;;
            c)
                echo "* Configure only"
                configure_only=1
                ;;
            d)
                echo "* DEBUG build"
                debug="--enable-debug"
                ;;
            f)
                echo "* Disabling external FreeImage"
                disable_freeimage=1
                ;;
            l)
                echo "* Using local files"
                use_local=1
                ;;
            m)
                make_opts="$OPTARG"
                ;;
            n)
                no_examples="--disable-examples"
                ;;
            o)
                local_dir=$(readlink -f $OPTARG)
                if [ ! -d $local_dir ]; then
                    mkdir -p $local_dir || exit 1
                fi
                echo "* Storing local archive files in $local_dir"
                ;;
            p)
                install_dir=$(readlink -f $OPTARG)
                echo "* Installing into $install_dir"
                ;;
            q)
                echo "* Enabling external Crypto++"
                enable_cryptopp=1
                ;;
            r)
                echo "* Building for Android"
                android_build=1
                ;;
            s)
                echo "* Disabling OpenSSL"
                disable_ssl=1
                ;;
            t)
                disable_posix_threads="--disable-posix-threads"
                ;;
            u)
                enable_sodium=1
                echo "* Enabling external Sodium."
                ;;
            v)
                enable_libuv=1
                echo "* Enabling external libuv."
                ;;
            w)
                download_only=1
                echo "* Downloading software archives only."
                ;;
            x)
                config_opts="$OPTARG"
                echo "* Using configuration options: $config_opts"
                ;;
            y)
                use_dynamic=1
                echo "* Building dynamic library and executable."
                ;;
            \?)
                display_help $0
                exit
                ;;
            *)
                display_help $0
                exit
                ;;
        esac
    done
    shift $((OPTIND-1))

    check_apps

    if [ "$(expr substr $(uname -s) 1 10)" = "MINGW32_NT" ]; then
        if [ ! -f "$cwd/winhttp.h" -o ! -f "$cwd/winhttp.lib"  ]; then
            echo "ERROR! Windows build requires WinHTTP header and library to be present in MEGA SDK project folder!"
            echo "Please get both winhttp.h and winhttp.lib files an put them into the MEGA SDK project's root folder."
            exit 1
        fi
    fi

    trap on_exit_error EXIT

    if [ $download_only -eq 0 ]; then
        if [ ! -d $build_dir ]; then
            mkdir -p $build_dir || exit 1
        fi
        if [ ! -d $install_dir ]; then
            mkdir -p $install_dir || exit 1
        fi

        cd $build_dir
    fi

    rm -fr *.log

    export PREFIX=$install_dir
    local old_pkg_conf=$PKG_CONFIG_PATH
    export PKG_CONFIG_PATH=$install_dir/lib/pkgconfig/
    export LD_LIBRARY_PATH="$install_dir/lib"
    export LD_RUN_PATH="$install_dir/lib"

    if [ $android_build -eq 1 ]; then
        echo "SYSROOT: $SYSROOT"
    fi

    if [ "$(expr substr $(uname -s) 1 10)" != "MINGW32_NT" ]; then
        if [ $disable_ssl -eq 0 ]; then
            openssl_pkg $build_dir $install_dir
        fi
    fi
    
    if [ $enable_cryptopp -eq 1 ]; then
        cryptopp_pkg $build_dir $install_dir
    fi
	
    if [ $enable_sodium -eq 1 ]; then
        sodium_pkg $build_dir $install_dir
    fi

    zlib_pkg $build_dir $install_dir
    sqlite_pkg $build_dir $install_dir
    if [ "$(expr substr $(uname -s) 1 10)" != "MINGW32_NT" ]; then
        cares_pkg $build_dir $install_dir
        curl_pkg $build_dir $install_dir
    fi

    if [ $enable_libuv -eq 1 ]; then
        libuv_pkg $build_dir $install_dir
    fi

    if [ $disable_freeimage -eq 0 ]; then
        freeimage_pkg $build_dir $install_dir $cwd
    fi

    # Build readline and termcap if no_examples isn't set
    if [ -z "$no_examples" ]; then
        if [ "$(expr substr $(uname -s) 1 10)" != "MINGW32_NT" ]; then
            readline_pkg $build_dir $install_dir
            termcap_pkg $build_dir $install_dir
        else
           readline_win_pkg  $build_dir $install_dir
       fi
    fi

    if [ $download_only -eq 0 ]; then
        cd $cwd

        build_sdk $install_dir $debug
    fi

    unset PREFIX
    unset LD_RUN_PATH
    unset LD_LIBRARY_PATH
    export PKG_CONFIG_PATH=$old_pkg_conf
    trap on_exit_ok EXIT
}

main "$@"
