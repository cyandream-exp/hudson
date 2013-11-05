#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    (repo forall -c "git reset --hard") >/dev/null
    echo $1
    exit 1
  fi
}

if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

if [ -z "$WORKSPACE" ]
then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN" ]
then
  echo CLEAN not specified
  exit 1
fi

if [ -z "$REPO_BRANCH" ]
then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ ! -z "$GERRIT_CHANGES" ]
	then
	echo $GERRIT_CHANGES > workfile.txt
	export GERRITDEVICE=`grep 'kidream/android_device' workfile.txt`
	rm -f workfile.txt
fi

if [ -z "$DEVICE" ]
then
	if [ ! -z "$GERRIT_CHANGE_ID" ]
		then
  	  if [ "$GERRIT_PROJECT" = "$GERRITDEVICE" ]
	  	then
	  	echo $GERRITDEVICE > workfile.txt
	  	if [ "$GERRITDEVICE" = "kidream/android_device_samsung_tuna" ]
			  then
		  	export DEVICE=maguro
  	  	elif [ "$GERRITDEVICE" =~ "kidream/android_device_samsung" ]
			then
		  	export DEVICE=`grep 'kidream/android_device_samsung_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "kidream/android_device_lge" ]
		  	then
		  	export DEVICE=`grep 'kidream/android_device_lge_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "kidream/android_device_htc" ]
		  	then
		  	export DEVICE=`grep 'kidream/android_device_htc_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "kidream/android_device_sony" ]
		  	then
		  	export DEVICE=`grep 'kidream/android_device_sony_' workfile.txt`
	  	elif [ "$GERRITDEVICE" =~ "kidream/android_device_motorola" ]
		  	then
		  	export DEVICE=`grep 'kidream/android_device_motorola_' workfile.txt`
	  	else
		  	echo compiling gerrit changes for $GERRITDEVICE not supported yet, stopping.
	      	rm -f workfile.txt
		  	exit 1
	  	fi
	  	rm -f workfile.txt
	  	unset GERRITDEVICE
	else
		export DEVICE=mako
  	  fi
  else
      echo DEVICE not specified
      exit 1
	fi
fi

if [ -z "$RELEASE_TYPE" ]
then
  echo RELEASE_TYPE not specified
  exit 1
fi

if [ -z "$SYNC_PROTO" ]
then
  SYNC_PROTO=http
fi
export LUNCH=full_$DEVICE-userdebug

export PYTHONDONTWRITEBYTECODE=1

# colorization fix in Jenkins
export CL_RED="\"\033[31m\""
export CL_GRN="\"\033[32m\""
export CL_YLW="\"\033[33m\""
export CL_BLU="\"\033[34m\""
export CL_MAG="\"\033[35m\""
export CL_CYN="\"\033[36m\""
export CL_RST="\"\033[0m\""

cd $WORKSPACE
rm -rf archive
mkdir -p archive
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export PATH=~/bin:$PATH

export USE_CCACHE=1
export CCACHE_NLEVELS=4
export BUILD_WITH_COLORS=0

platform=`uname -s`
if [ "$platform" = "Darwin" ]
then
  export BUILD_MAC_SDK_EXPERIMENTAL=1
  # creating a symlink...
  rm -rf /Volumes/android/tools/hudson.model.JDK/Ubuntu
  ln -s /Library/Java/JavaVirtualMachines/jdk1.7.0_25.jdk/Contents/Home /Volumes/android/tools/hudson.model.JDK/Ubuntu
fi

REPO=$(which repo)
if [ -z "$REPO" ]
then
  mkdir -p ~/bin
  curl https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

if [[ "$REPO_BRANCH" =~ "kitkat" || $REPO_BRANCH =~ "kd-4.4" ]]; then 
   JENKINS_BUILD_DIR=kitkat
else
   JENKINS_BUILD_DIR=$REPO_BRANCH
fi

export JENKINS_BUILD_DIR

mkdir -p $JENKINS_BUILD_DIR
cd $JENKINS_BUILD_DIR

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ -z "$CORE_BRANCH" ]
then
  CORE_BRANCH=$REPO_BRANCH
fi

if [ ! -z "$RELEASE_MANIFEST" ]
then
  MANIFEST="-m $RELEASE_MANIFEST"
else
  RELEASE_MANIFEST=""
  MANIFEST=""
fi

rm -rf .repo/manifests*
rm -f .repo/local_manifests/dyn-*.xml
repo init -u $SYNC_PROTO://github.com/kidream/android.git -b $CORE_BRANCH $MANIFEST
check_result "repo init failed."


echo "get proprietary stuff..."
if [ ! -d vendor/kd-priv ]
then
git clone git@bitbucket.org:yanniks/android_vendor_kd-priv.git vendor/kd-priv
fi

cd vendor/kd-priv
## Get rid of possible local changes
git reset --hard
git pull -s resolve
cd ../..
bash vendor/kd-priv/setup

# make sure ccache is in PATH
if [[ "$REPO_BRANCH" =~ "kitkat" || $REPO_BRANCH =~ "kd-4.4" ]]
then
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilts/misc/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.kk_ccache
else
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilt/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.ics_ccache
fi

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

mkdir -p .repo/local_manifests
rm -f .repo/local_manifest.xml

check_result "Bootstrap failed"

echo Core Manifest:
cat .repo/manifest.xml

## TEMPORARY: Some kernels are building _into_ the source tree and messing
## up posterior syncs due to changes
rm -rf kernel/*

echo Syncing...
repo sync -d -c > /dev/null
check_result "repo sync failed."
if [ -z "$GERRIT_CHANGE_NUMBER" ]
then
  echo ""
else
  export GERRIT_XLATION_LINT=true
  export GERRIT_CHANGES=$GERRIT_CHANGE_NUMBER
  if [ "$GERRIT_PATCHSET_NUMBER" = "1" ]
  then
    export KD_EXTRAVERSION=gerrit-$GERRIT_CHANGE_NUMBER
  else
    export KD_EXTRAVERSION=gerrit-$GERRIT_CHANGE_NUMBER.$GERRIT_PATCHSET_NUMBER
  fi
fi
echo Sync complete.

if [ -f .last_branch ]
then
  LAST_BRANCH=$(cat .last_branch)
else
  echo "Last build branch is unknown, assume clean build"
  LAST_BRANCH=$REPO_BRANCH-$CORE_BRANCH$RELEASE_MANIFEST
fi

if [ "$LAST_BRANCH" != "$REPO_BRANCH-$CORE_BRANCH$RELEASE_MANIFEST" ]
then
  echo "Branch has changed since the last build happened here. Forcing cleanup."
  CLEAN="true"
fi

. build/envsetup.sh
# Workaround for failing translation checks in common hardware repositories
if [ ! -z "$GERRIT_XLATION_LINT" ]
then
    LUNCH=$(echo $LUNCH@$DEVICEVENDOR | sed -f $WORKSPACE/hudson/shared-repo.map)
fi

lunch $LUNCH
check_result "lunch failed."

# save manifest used for build (saving revisions as current HEAD)

# include only the auto-generated locals
TEMPSTASH=$(mktemp -d)

# save it
repo manifest -o $WORKSPACE/archive/manifest.xml -r

# restore all local manifests
mv $TEMPSTASH/* .repo/local_manifests/ 2>/dev/null
rmdir $TEMPSTASH

rm -f $OUT/system/build.prop
rm -f $OUT/*.zip*

UNAME=$(uname)

if [ ! -z "$BUILD_USER_ID" ]
then
  export RELEASE_TYPE=KD_EXPERIMENTAL
fi

if [ "$RELEASE_TYPE" = "KD_NIGHTLY" ]
then
  if [ ! -z "$GERRIT_CHANGE_NUMBER" ]
  then
    export KD_EXPERIMENTAL=true
  fi
elif [ "$RELEASE_TYPE" = "KD_EXPERIMENTAL" ]
then
  export KD_EXPERIMENTAL=true
elif [ "$RELEASE_TYPE" = "KD_RELEASE" ]
then
  # ics needs this
  export KD_RELEASE=true
  if [ "$SIGNED" = "true" ]
  then
    SIGN_BUILD=true
  fi
fi

if [ ! -z "$KD_EXTRAVERSION" ]
then
  export KD_EXPERIMENTAL=true
fi

if [ ! -z "$GERRIT_CHANGES" ]
then
  export KD_EXPERIMENTAL=true
  IS_HTTP=$(echo $GERRIT_CHANGES | grep http)
  if [ -z "$IS_HTTP" ]
  then
    python $WORKSPACE/hudson/repopick.py $GERRIT_CHANGES
    check_result "gerrit picks failed."
  else
    python $WORKSPACE/hudson/repopick.py $(curl $GERRIT_CHANGES)
    check_result "gerrit picks failed."
  fi
  if [ ! -z "$GERRIT_XLATION_LINT" ]
  then
    python $WORKSPACE/hudson/xlationlint.py $GERRIT_CHANGES
    check_result "basic XML lint failed."
  fi
fi

if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "50.0" ]
then
  ccache -M 50G
fi

WORKSPACE=$WORKSPACE LUNCH=$LUNCH bash $WORKSPACE/hudson/changes/buildlog.sh 2>&1

LAST_CLEAN=0
if [ -f .clean ]
then
  LAST_CLEAN=$(date -r .clean +%s)
fi
TIME_SINCE_LAST_CLEAN=$(expr $(date +%s) - $LAST_CLEAN)
# convert this to hours
TIME_SINCE_LAST_CLEAN=$(expr $TIME_SINCE_LAST_CLEAN / 60 / 60)
if [ $TIME_SINCE_LAST_CLEAN -gt "24" -o $CLEAN = "true" ]
then
  echo "Cleaning!"
  touch .clean
  make clobber
else
  echo "Skipping clean: $TIME_SINCE_LAST_CLEAN hours since last clean."
fi

echo "$REPO_BRANCH-$CORE_BRANCH$RELEASE_MANIFEST" > .last_branch

time mka

check_result "Build failed."

# archive the build.prop as well
ZIP=$(ls $WORKSPACE/archive/*.zip)
unzip -p $ZIP system/build.prop > $WORKSPACE/archive/build.prop

# CORE: save manifest used for build (saving revisions as current HEAD)

# Stash away other possible manifests
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests $TEMPSTASH

repo manifest -o $WORKSPACE/archive/core.xml -r

rmdir $TEMPSTASH

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive

echo "release new build..."
bash vendor/kd-priv/release/release $RELEASE_TYPE
